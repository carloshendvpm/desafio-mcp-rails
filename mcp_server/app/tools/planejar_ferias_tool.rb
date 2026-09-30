# Encontra as melhores datas para tirar férias CLT emendando fins de semana e
# feriados nacionais — a ideia do "Folga Extra": mesmos dias de férias, mais dias de descanso.
#
# Regras da CLT aplicadas:
# - Férias contam em dias corridos (art. 130).
# - Até 3 períodos: um com pelo menos 14 dias e os demais com pelo menos 5 (art. 134 §1).
# - Não podem começar nos 2 dias que antecedem feriado ou o repouso semanal (domingo) (art. 134 §3).
# - Aviso ao empregado com 30 dias de antecedência (art. 135) -> busca começa em hoje + 30.
# - Pagamento até 2 dias antes do início (art. 145).
class PlanejarFeriasTool < ApplicationTool
  AVISO_PREVIO_DIAS = 30
  MAX_DIAS_ANO = 30

  tool_name "planejar_ferias"
  description "Planeja férias CLT para maximizar o descanso emendando fins de semana e feriados " \
              "nacionais. Recebe a divisão das férias em períodos (ex: [30], [15, 15] ou [14, 10, 6]) " \
              "e sugere datas de início válidas pela CLT, com o total de dias de descanso e quantos " \
              "dias extras cada opção ganha. Valida as regras de fracionamento da CLT. " \
              "Considera só feriados nacionais (não estaduais/municipais) e trabalho de segunda a sexta."
  input_schema(
    properties: {
      periodos: {
        type: "array", items: { type: "integer", minimum: 5, maximum: 30 }, minItems: 1, maxItems: 3,
        description: "Duração de cada período de férias em dias corridos. Soma até 30. Ex: [30] ou [20, 10]"
      },
      ano: { type: "integer", description: "Ano em que as férias devem começar. Padrão: ano atual." },
      a_partir_de: {
        type: "string", format: "date",
        description: "Data mais cedo para começar (AAAA-MM-DD). Padrão: hoje + 30 dias (aviso prévio da CLT)."
      },
      opcoes: { type: "integer", minimum: 1, maximum: 5, description: "Alternativas por período. Padrão: 3." }
    },
    required: [ "periodos" ]
  )
  annotations(read_only_hint: true, open_world_hint: true)

  def self.run(periodos:, ano: nil, a_partir_de: nil, opcoes: 3)
    validar_periodos!(periodos)

    inicio_busca = a_partir_de ? Date.parse(a_partir_de) : Date.current + AVISO_PREVIO_DIAS
    ano = (ano || inicio_busca.year).to_i
    inicio_busca = [ inicio_busca, Date.new(ano, 1, 1) ].max
    fim_busca = Date.new(ano, 12, 31)
    raise ArgumentError, "Não há datas disponíveis em #{ano} a partir de #{inicio_busca}" if inicio_busca > fim_busca

    feriados = feriados_nacionais(ano) # { Date => "nome" }
    ocupados = []

    # Maiores períodos primeiro: eles têm menos encaixes bons.
    resultado = periodos.sort.reverse.map do |dias|
      candidatas = candidatas(dias, inicio_busca, fim_busca, feriados)
      alternativas = sem_sobreposicao(candidatas, opcoes)
      escolhida = candidatas.find { |c| ocupados.none? { |o| sobrepoe?(c, o) } }
      ocupados << escolhida if escolhida

      { dias_de_ferias: dias, sugestao: escolhida && formatar(escolhida), alternativas: alternativas.map { |c| formatar(c) } }
    end

    {
      periodos: resultado,
      total_dias_ferias: periodos.sum,
      total_dias_descanso_sugeridos: resultado.sum { |r| r.dig(:sugestao, :dias_de_descanso).to_i },
      busca: { de: inicio_busca.iso8601, ate: fim_busca.iso8601 },
      regras_consideradas: [
        "Férias em dias corridos; início não pode cair na sexta, sábado, domingo, feriado ou nos 2 dias antes de um feriado",
        "Aviso ao empregado com 30 dias de antecedência e pagamento até 2 dias antes do início",
        "Só feriados nacionais; confirme feriados estaduais/municipais e a política da empresa",
        "Carnaval é ponto facultativo: confirme se a empresa folga"
      ]
    }
  end

  def self.validar_periodos!(periodos)
    periodos = Array(periodos).map(&:to_i)
    raise ArgumentError, "Divida as férias em no máximo 3 períodos" if periodos.size > 3
    raise ArgumentError, "Nenhum período pode ter menos de 5 dias corridos" if periodos.any? { |p| p < 5 }
    raise ArgumentError, "A soma dos períodos não pode passar de #{MAX_DIAS_ANO} dias" if periodos.sum > MAX_DIAS_ANO
    if periodos.size > 1 && periodos.none? { |p| p >= 14 }
      raise ArgumentError, "Ao dividir as férias, um dos períodos precisa ter pelo menos 14 dias corridos"
    end
  end

  # Todas as datas de início válidas, da que rende mais descanso para a que rende menos.
  def self.candidatas(dias, inicio_busca, fim_busca, feriados)
    (inicio_busca..fim_busca).select { |d| inicio_permitido?(d, feriados) }.map do |inicio|
      fim = inicio + dias - 1
      descanso_inicio = inicio
      descanso_inicio -= 1 while folga?(descanso_inicio - 1, feriados)
      descanso_fim = fim
      descanso_fim += 1 while folga?(descanso_fim + 1, feriados)

      {
        inicio: inicio, fim: fim, dias: dias, descanso_inicio: descanso_inicio, descanso_fim: descanso_fim,
        descanso: (descanso_fim - descanso_inicio).to_i + 1,
        feriados: (descanso_inicio..descanso_fim).filter_map { |d| feriados[d] && "#{feriados[d]} (#{d.strftime("%d/%m")})" }
      }
    end.sort_by { |c| [ -c[:descanso], c[:inicio] ] }
  end

  def self.inicio_permitido?(data, feriados)
    return false if folga?(data, feriados)
    return false if data.friday? # 2 dias antes do repouso semanal (domingo): sexta e sábado

    feriados.none? { |feriado, _| (1..2).cover?((feriado - data).to_i) }
  end

  def self.folga?(data, feriados)
    data.saturday? || data.sunday? || feriados.key?(data)
  end

  def self.sem_sobreposicao(candidatas, limite)
    candidatas.each_with_object([]) do |c, escolhidas|
      escolhidas << c if escolhidas.none? { |e| sobrepoe?(c, e) }
      break escolhidas if escolhidas.size == limite
    end
  end

  def self.sobrepoe?(a, b)
    a[:descanso_inicio] <= b[:descanso_fim] && b[:descanso_inicio] <= a[:descanso_fim]
  end

  def self.formatar(c)
    {
      inicio_ferias: c[:inicio].iso8601,
      fim_ferias: c[:fim].iso8601,
      descanso_de: c[:descanso_inicio].iso8601,
      descanso_ate: c[:descanso_fim].iso8601,
      dias_de_descanso: c[:descanso],
      dias_extras: c[:descanso] - c[:dias],
      feriados_emendados: c[:feriados],
      avisar_ate: (c[:inicio] - AVISO_PREVIO_DIAS).iso8601,
      pagamento_ate: (c[:inicio] - 2).iso8601
    }
  end

  # Férias podem terminar no ano seguinte, então buscamos os dois anos.
  def self.feriados_nacionais(ano)
    [ ano, ano + 1 ].flat_map { |a| HttpJson.get("https://brasilapi.com.br/api/feriados/v1/#{a}") }
                    .to_h { |f| [ Date.parse(f["date"]), f["name"] ] }
  end
end
