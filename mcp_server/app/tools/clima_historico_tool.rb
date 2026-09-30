# Clima típico de uma cidade nas datas da viagem, calculado a partir das mesmas datas nos últimos
# anos (Open-Meteo Archive), com sugestão do que levar na mala. Serve para viagens além dos 14 dias
# de previsão da clima_cidade.
class ClimaHistoricoTool < ApplicationTool
  ANOS = 5
  MAX_DIAS = 31
  DAILY = "temperature_2m_max,temperature_2m_min,precipitation_sum,snowfall_sum,wind_speed_10m_max".freeze

  tool_name "clima_historico"
  description "Clima típico de uma cidade num período (as mesmas datas nos últimos 5 anos) e sugestão " \
              "de roupas para a mala: médias de temperatura, frequência de chuva e neve, e vento. " \
              "Use para viagens daqui a mais de 14 dias ou para decidir o que levar. " \
              "Não é previsão: para os próximos 14 dias, use clima_cidade."
  input_schema(
    properties: {
      cidade: { type: "string", description: "Nome da cidade, ex: Lisboa, Bariloche, Tóquio" },
      data_inicio: { type: "string", format: "date", description: "Primeiro dia da viagem (AAAA-MM-DD)" },
      data_fim: { type: "string", format: "date", description: "Último dia da viagem (AAAA-MM-DD), no máximo 31 dias depois" }
    },
    required: [ "cidade", "data_inicio", "data_fim" ]
  )
  annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: true)

  def self.run(cidade:, data_inicio:, data_fim:)
    inicio = Date.parse(data_inicio)
    fim = Date.parse(data_fim)
    raise ArgumentError, "data_fim deve ser depois de data_inicio" if fim < inicio
    raise ArgumentError, "Período máximo de #{MAX_DIAS} dias" if (fim - inicio).to_i >= MAX_DIAS

    local = ClimaCidadeTool.geocode(cidade)
    dias = dias_historicos(local, inicio, fim)
    resumo = resumir(dias)

    {
      cidade: local["name"],
      pais: local["country"],
      periodo: "#{inicio.strftime("%d/%m")} a #{fim.strftime("%d/%m")}",
      base: "mesmas datas de #{ultimo_ano(fim) - ANOS + 1} a #{ultimo_ano(fim)} (#{dias.size} dias medidos)",
      **resumo,
      o_que_levar: sugestao_de_roupas(resumo),
      aviso: "Média histórica, não previsão. Perto da viagem, confira a previsão com clima_cidade."
    }
  end

  # O último ano com as datas inteiras no passado: se a viagem é em dezembro/2026 e hoje é setembro,
  # o último dezembro completo é o de 2025.
  def self.ultimo_ano(fim)
    anos_atras = fim.change(year: Date.current.year) < Date.current ? 0 : 1
    Date.current.year - anos_atras
  end

  # Uma única chamada cobrindo os 5 anos; depois ficam só as datas da viagem em cada ano.
  def self.dias_historicos(local, inicio, fim)
    deslocamento_base = fim.year - ultimo_ano(fim)
    datas_da_viagem = (0...ANOS).flat_map do |i|
      anos = deslocamento_base + i
      (inicio.prev_year(anos)..fim.prev_year(anos)).map(&:iso8601)
    end.to_set

    daily = HttpJson.get("https://archive-api.open-meteo.com/v1/archive",
                         latitude: local["latitude"], longitude: local["longitude"],
                         start_date: inicio.prev_year(deslocamento_base + ANOS - 1).iso8601,
                         end_date: fim.prev_year(deslocamento_base).iso8601,
                         daily: DAILY, timezone: "auto")["daily"]

    daily["time"].each_index.filter_map do |d|
      next unless datas_da_viagem.include?(daily["time"][d])
      next unless daily["temperature_2m_max"][d] && daily["temperature_2m_min"][d]

      {
        max: daily["temperature_2m_max"][d], min: daily["temperature_2m_min"][d],
        chuva_mm: daily["precipitation_sum"][d].to_f, neve_cm: daily["snowfall_sum"][d].to_f,
        vento: daily["wind_speed_10m_max"][d]
      }
    end
  end

  def self.resumir(dias)
    raise HttpJson::Error, "Sem dados históricos para esse período" if dias.empty?

    media = ->(valores) { (valores.sum / valores.size.to_f).round(1) + 0.0 } # + 0.0 evita "-0.0"
    pct = ->(qtd) { (100.0 * qtd / dias.size).round }

    {
      temperatura_c: {
        media_minima: media.(dias.map { _1[:min] }),
        media_maxima: media.(dias.map { _1[:max] }),
        menor_registrada: dias.map { _1[:min] }.min,
        maior_registrada: dias.map { _1[:max] }.max
      },
      dias_com_chuva_pct: pct.(dias.count { _1[:chuva_mm] >= 1 }),
      chuva_media_mm_dia: media.(dias.map { _1[:chuva_mm] }),
      dias_com_neve_pct: pct.(dias.count { _1[:neve_cm] > 0 }),
      vento_max_medio_kmh: media.(dias.filter_map { _1[:vento] })
    }
  end

  def self.sugestao_de_roupas(resumo)
    minima = resumo.dig(:temperatura_c, :media_minima)
    maxima = resumo.dig(:temperatura_c, :media_maxima)
    itens = []

    if minima < 3 then itens << "casaco pesado, gorro, luvas e cachecol"
    elsif minima < 10 then itens << "casaco quente e segunda pele para manhãs e noites"
    elsif minima < 16 then itens << "jaqueta ou casaco leve para a noite"
    end

    if maxima >= 28 then itens << "roupas leves, protetor solar, óculos escuros e chapéu"
    elsif maxima >= 22 then itens << "camisetas e roupas leves para o dia"
    elsif maxima < 12 then itens << "calças e blusas quentes também durante o dia"
    end

    itens << "vista-se em camadas: o dia e a noite têm mais de 10°C de diferença" if maxima - minima >= 10

    chuva = resumo[:dias_com_chuva_pct]
    if chuva >= 40 then itens << "guarda-chuva e jaqueta impermeável (chove em #{chuva}% dos dias)"
    elsif chuva >= 20 then itens << "guarda-chuva compacto (chove em #{chuva}% dos dias)"
    end

    itens << "calçado impermeável e antiderrapante (neve em #{resumo[:dias_com_neve_pct]}% dos dias)" if resumo[:dias_com_neve_pct].positive?
    itens << "corta-vento (ventos fortes são comuns)" if resumo[:vento_max_medio_kmh] >= 30
    itens << "calçado confortável para caminhar" if itens.empty?
    itens
  end
end
