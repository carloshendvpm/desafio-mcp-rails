class InfoPaisTool < ApplicationTool
  DATASET_URL = "https://cdn.jsdelivr.net/npm/world-countries/countries.json".freeze

  tool_name "info_pais"
  description "Informações de um país para viajantes: capital, moeda (código ISO), idiomas, " \
              "região, DDI e países vizinhos. Aceita o nome em português ou inglês."
  input_schema(
    properties: {
      nome: { type: "string", description: "Nome do país, ex: Japão, Argentina, France" }
    },
    required: [ "nome" ]
  )
  annotations(read_only_hint: true, open_world_hint: true)

  def self.run(nome:)
    alvo = normalize(nome)
    pais = countries.find { |c| nomes_de(c).include?(alvo) }
    raise ArgumentError, "País não encontrado: #{nome}" unless pais

    {
      nome: pais.dig("translations", "por", "common") || pais.dig("name", "common"),
      nome_oficial: pais.dig("name", "official"),
      codigo: pais["cca2"],
      capital: pais["capital"],
      moedas: pais["currencies"].map { |codigo, m| { codigo: codigo, nome: m["name"], simbolo: m["symbol"] } },
      idiomas: pais["languages"].values,
      regiao: pais["region"],
      sub_regiao: pais["subregion"],
      ddi: "#{pais.dig("idd", "root")}#{Array(pais.dig("idd", "suffixes")).one? ? pais.dig("idd", "suffixes", 0) : ""}",
      bandeira: pais["flag"],
      vizinhos: pais["borders"]
    }
  end

  # O dataset (~1.4MB) é baixado uma vez e fica em memória no processo.
  def self.countries
    @countries ||= HttpJson.get(DATASET_URL)
  end

  def self.nomes_de(country)
    [
      country.dig("name", "common"), country.dig("name", "official"),
      country.dig("translations", "por", "common"), country.dig("translations", "por", "official"),
      country["cca2"], country["cca3"], *country["altSpellings"]
    ].compact.map { |n| normalize(n) }
  end

  def self.normalize(text)
    I18n.transliterate(text.to_s).downcase.strip
  end
end
