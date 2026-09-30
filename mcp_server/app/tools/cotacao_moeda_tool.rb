class CotacaoMoedaTool < ApplicationTool
  tool_name "cotacao_moeda"
  description "Cotação atual de uma moeda estrangeira em reais (BRL), via AwesomeAPI. " \
              "Use o código ISO 4217 da moeda (ex: USD, EUR, JPY, ARS, GBP)."
  input_schema(
    properties: {
      moeda: { type: "string", description: "Código ISO 4217 da moeda, ex: USD" }
    },
    required: [ "moeda" ]
  )
  annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: true)

  def self.run(moeda:)
    codigo = moeda.to_s.strip.upcase
    raise ArgumentError, "Código de moeda inválido: #{moeda}" unless codigo.match?(/\A[A-Z]{3}\z/)

    cotacao = HttpJson.get("https://economia.awesomeapi.com.br/json/last/#{codigo}-BRL").fetch("#{codigo}BRL")

    {
      moeda: codigo,
      descricao: cotacao["name"],
      valor_em_reais: cotacao["bid"].to_f,
      maxima_dia: cotacao["high"].to_f,
      minima_dia: cotacao["low"].to_f,
      variacao_percentual: cotacao["pctChange"].to_f,
      atualizado_em: cotacao["create_date"]
    }
  end
end
