# Consulta local (sem API): as regras ficam em config/seguro_viagem.yml, com fonte e data de revisão.
# O nome do país é resolvido pelo mesmo lookup da info_pais (português, inglês ou código ISO).
class RequisitosSeguroViagemTool < ApplicationTool
  AVISO = "Regras de entrada mudam: confirme no consulado ou no site oficial do país antes de viajar.".freeze

  tool_name "requisitos_seguro_viagem"
  description "Diz se o país de destino exige seguro viagem de turistas brasileiros, a cobertura mínima " \
              "e o que precisa estar coberto, com a fonte e a data de revisão da regra. " \
              "Aceita o nome do país em português ou inglês."
  input_schema(
    properties: {
      pais: { type: "string", description: "País de destino, ex: Portugal, Cuba, United States" }
    },
    required: [ "pais" ]
  )
  annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)

  def self.run(pais:)
    country = InfoPaisTool.find_country(pais)
    codigo = country["cca2"]
    regra = regras["regras"].find { |r| r["paises"].include?(codigo) }

    {
      pais: country.dig("translations", "por", "common") || country.dig("name", "common"),
      codigo: codigo,
      regra: regra&.dig("nome"),
      status: (regra || regras["padrao"])["status"],
      cobertura_minima: regra&.dig("cobertura_minima"),
      coberturas_exigidas: regra&.dig("coberturas"),
      detalhes: (regra || regras["padrao"])["detalhes"],
      fonte: regra&.dig("fonte"),
      revisado_em: regra&.dig("revisado_em"),
      aviso: AVISO
    }.compact
  end

  def self.regras
    @regras ||= YAML.load_file(Rails.root.join("config/seguro_viagem.yml"))
  end
end
