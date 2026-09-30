class BuscarCepTool < ApplicationTool
  tool_name "buscar_cep"
  description "Consulta um CEP brasileiro e retorna endereço, bairro, cidade, UF e coordenadas (BrasilAPI)."
  input_schema(
    properties: {
      cep: { type: "string", description: "CEP com 8 dígitos, com ou sem hífen, ex: 01310-100" }
    },
    required: [ "cep" ]
  )
  annotations(read_only_hint: true, open_world_hint: true)

  def self.run(cep:)
    digitos = cep.to_s.gsub(/\D/, "")
    raise ArgumentError, "CEP deve ter 8 dígitos: #{cep}" unless digitos.length == 8

    dados = HttpJson.get("https://brasilapi.com.br/api/cep/v2/#{digitos}")

    {
      cep: dados["cep"],
      logradouro: dados["street"],
      bairro: dados["neighborhood"],
      cidade: dados["city"],
      uf: dados["state"],
      coordenadas: dados.dig("location", "coordinates")
    }
  end
end
