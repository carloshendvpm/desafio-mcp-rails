require "test_helper"

class RequisitosSeguroViagemTest < ActionDispatch::IntegrationTest
  setup do
    InfoPaisTool.instance_variable_set(:@countries, nil)
    pais = ->(cca2, pt, en) { { name: { common: en, official: en }, cca2: cca2, cca3: "#{cca2}X", altSpellings: [], translations: { por: { common: pt, official: pt } } } }
    stub_json(InfoPaisTool::DATASET_URL, [ pais.("PT", "Portugal", "Portugal"), pais.("AR", "Argentina", "Argentina"), pais.("TH", "Tailândia", "Thailand") ])
  end

  teardown { InfoPaisTool.instance_variable_set(:@countries, nil) }

  def consultar(pais)
    error, text = call_tool("requisitos_seguro_viagem", pais: pais)
    refute error, text
    JSON.parse(text)
  end

  test "país do Espaço Schengen exige seguro com cobertura mínima e fonte" do
    regra = consultar("portugal")

    assert_equal "obrigatorio", regra["status"]
    assert_equal "Espaço Schengen", regra["regra"]
    assert_equal "€30.000", regra["cobertura_minima"]
    assert regra["fonte"].present? && regra["revisado_em"].present?
  end

  test "regra em mudança sai como verificar, não como afirmação" do
    assert_equal "verificar", consultar("Argentina")["status"]
  end

  test "país sem regra cadastrada cai no padrão recomendado" do
    regra = consultar("Thailand")

    assert_equal "recomendado", regra["status"]
    assert_nil regra["regra"]
    assert_includes regra["detalhes"], "Não há regra cadastrada"
  end

  test "toda regra do YAML tem status válido, fonte e data de revisão" do
    RequisitosSeguroViagemTool.regras["regras"].each do |regra|
      assert_includes %w[obrigatorio verificar recomendado], regra["status"], regra["nome"]
      assert regra["fonte"].present?, regra["nome"]
      assert Date.parse(regra["revisado_em"]), regra["nome"]
    end
  end

  test "Espaço Schengen tem os 29 países" do
    schengen = RequisitosSeguroViagemTool.regras["regras"].find { |r| r["nome"] == "Espaço Schengen" }
    assert_equal 29, schengen["paises"].uniq.size
  end
end
