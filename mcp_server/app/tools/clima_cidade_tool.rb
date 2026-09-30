class ClimaCidadeTool < ApplicationTool
  # Códigos WMO usados pelo Open-Meteo -> descrição em português.
  WEATHER_CODES = {
    0 => "céu limpo", 1 => "predominantemente limpo", 2 => "parcialmente nublado", 3 => "nublado",
    45 => "neblina", 48 => "neblina com geada",
    51 => "garoa fraca", 53 => "garoa", 55 => "garoa forte",
    61 => "chuva fraca", 63 => "chuva", 65 => "chuva forte",
    71 => "neve fraca", 73 => "neve", 75 => "neve forte",
    80 => "pancadas de chuva fracas", 81 => "pancadas de chuva", 82 => "pancadas de chuva fortes",
    95 => "trovoadas", 96 => "trovoadas com granizo", 99 => "trovoadas fortes com granizo"
  }.freeze

  tool_name "clima_cidade"
  description "Previsão do tempo em qualquer cidade do mundo (Open-Meteo), de hoje até 14 dias à frente: " \
              "temperatura mínima/máxima, chance de chuva e condição do céu. Para uma data futura, " \
              "peça dias suficientes para alcançá-la e use só os dias relevantes."
  input_schema(
    properties: {
      cidade: { type: "string", description: "Nome da cidade, ex: Tóquio, Buenos Aires, Recife" },
      dias: { type: "integer", minimum: 1, maximum: 14, description: "Quantidade de dias de previsão (1 a 14). Padrão: 3." }
    },
    required: [ "cidade" ]
  )
  annotations(read_only_hint: true, open_world_hint: true)

  def self.run(cidade:, dias: 3)
    local = HttpJson.get("https://geocoding-api.open-meteo.com/v1/search",
                         name: cidade, count: 1, language: "pt")["results"]&.first
    raise ArgumentError, "Cidade não encontrada: #{cidade}" unless local

    previsao = HttpJson.get("https://api.open-meteo.com/v1/forecast",
                            latitude: local["latitude"], longitude: local["longitude"],
                            daily: "temperature_2m_max,temperature_2m_min,precipitation_probability_max,weather_code",
                            timezone: "auto", forecast_days: dias.to_i.clamp(1, 14))["daily"]

    {
      cidade: local["name"],
      pais: local["country"],
      fuso_horario: local["timezone"],
      previsao: previsao["time"].each_with_index.map do |data, i|
        {
          data: data,
          minima_c: previsao["temperature_2m_min"][i],
          maxima_c: previsao["temperature_2m_max"][i],
          chance_chuva_pct: previsao["precipitation_probability_max"][i],
          condicao: WEATHER_CODES.fetch(previsao["weather_code"][i], "código #{previsao["weather_code"][i]}")
        }
      end
    }
  end
end
