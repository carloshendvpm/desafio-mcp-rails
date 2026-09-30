require "test_helper"

class PlanejarFeriasTest < ActionDispatch::IntegrationTest
  # Um único feriado numa sexta-feira: 15/10/2027.
  setup do
    stub_json("https://brasilapi.com.br/api/feriados/v1/2027", [ { date: "2027-10-15", name: "Feriado Teste" } ])
    stub_json("https://brasilapi.com.br/api/feriados/v1/2028", [])
  end

  def planejar(**args)
    error, text = call_tool("planejar_ferias", { ano: 2027, a_partir_de: "2027-10-01" }.merge(args))
    [ error, error ? text : JSON.parse(text) ]
  end

  test "emenda o feriado com os fins de semana" do
    error, plano = planejar(periodos: [ 5 ])

    refute error
    sugestao = plano.dig("periodos", 0, "sugestao")
    # Férias seg 18/10 a sex 22/10 + feriado sex 15/10 e dois fins de semana = 10 dias de descanso
    assert_equal "2027-10-18", sugestao["inicio_ferias"]
    assert_equal "2027-10-15", sugestao["descanso_de"]
    assert_equal "2027-10-24", sugestao["descanso_ate"]
    assert_equal 10, sugestao["dias_de_descanso"]
    assert_equal 5, sugestao["dias_extras"]
    assert_equal [ "Feriado Teste (15/10)" ], sugestao["feriados_emendados"]
    assert_equal "2027-10-16", sugestao["pagamento_ate"]
    assert_equal "2027-09-18", sugestao["avisar_ate"]
  end

  test "períodos fracionados não se sobrepõem" do
    error, plano = planejar(periodos: [ 6, 14 ])

    refute error
    assert_equal [ 14, 6 ], plano["periodos"].map { |p| p["dias_de_ferias"] }
    a, b = plano["periodos"].map { |p| p["sugestao"] }
    assert b["descanso_de"] > a["descanso_ate"] || b["descanso_ate"] < a["descanso_de"]
  end

  test "nunca sugere início proibido pela CLT" do
    _, plano = planejar(periodos: [ 5 ], opcoes: 5)

    inicios = plano["periodos"].flat_map { |p| p["alternativas"] }.map { |a| Date.parse(a["inicio_ferias"]) }
    assert inicios.none? { |d| d.friday? || d.saturday? || d.sunday? }
    refute_includes inicios, Date.new(2027, 10, 13) # 2 dias antes do feriado
    refute_includes inicios, Date.new(2027, 10, 14)
  end

  test "valida o fracionamento da CLT" do
    assert_includes planejar(periodos: [ 10, 10 ]).last, "pelo menos 14 dias"
    assert_includes planejar(periodos: [ 20, 20 ]).last, "não pode passar de 30"
    # Regras que o JSON Schema expressa (maxItems) são barradas pela própria gem, antes da tool rodar
    assert_includes planejar(periodos: [ 14, 5, 5, 5 ]).last, "Invalid arguments"
  end
end
