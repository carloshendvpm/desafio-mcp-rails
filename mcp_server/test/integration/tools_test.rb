require "test_helper"

class ToolsTest < ActionDispatch::IntegrationTest
  test "feriados_nacionais" do
    stub_json("https://brasilapi.com.br/api/feriados/v1/2026",
              [ { date: "2026-12-25", name: "Natal", type: "national", weekday: "sexta-feira" } ])

    error, text = call_tool("feriados_nacionais", ano: 2026)

    refute error
    assert_includes text, "Natal"
  end

  test "cotacao_moeda" do
    stub_json("https://economia.awesomeapi.com.br/json/last/USD-BRL",
              USDBRL: { name: "Dólar Americano/Real Brasileiro", bid: "5.40", high: "5.5", low: "5.3", pctChange: "0.1", create_date: "2026-09-30" })

    error, text = call_tool("cotacao_moeda", moeda: "usd")

    refute error
    assert_equal 5.40, JSON.parse(text)["valor_em_reais"]
  end

  test "cotacao_moeda rejeita código inválido sem chamar a API" do
    error, text = call_tool("cotacao_moeda", moeda: "dolar")

    assert error
    assert_includes text, "inválido"
  end

  test "info_pais encontra pelo nome em português sem acento" do
    InfoPaisTool.instance_variable_set(:@countries, nil)
    stub_json(InfoPaisTool::DATASET_URL, [ {
      name: { common: "Japan", official: "Japan" }, cca2: "JP", cca3: "JPN", altSpellings: [],
      translations: { por: { common: "Japão", official: "Japão" } }, capital: [ "Tokyo" ],
      currencies: { JPY: { name: "Japanese yen", symbol: "¥" } }, languages: { jpn: "Japanese" },
      region: "Asia", subregion: "Eastern Asia", idd: { root: "+8", suffixes: [ "1" ] }, flag: "🇯🇵", borders: []
    } ])

    error, text = call_tool("info_pais", nome: "japao")

    refute error
    data = JSON.parse(text)
    assert_equal "JPY", data.dig("moedas", 0, "codigo")
    assert_equal "+81", data["ddi"]
  ensure
    InfoPaisTool.instance_variable_set(:@countries, nil)
  end

  test "clima_cidade geocodifica e traduz a condição" do
    stub_request(:get, %r{geocoding-api.open-meteo.com}).to_return(
      body: { results: [ { name: "Tóquio", country: "Japão", timezone: "Asia/Tokyo", latitude: 35.6, longitude: 139.6 } ] }.to_json,
      headers: { "Content-Type" => "application/json" })
    stub_request(:get, %r{api.open-meteo.com/v1/forecast}).to_return(
      body: { daily: { time: [ "2026-10-01" ], temperature_2m_min: [ 18 ], temperature_2m_max: [ 25 ],
                       precipitation_probability_max: [ 60 ], weather_code: [ 63 ] } }.to_json,
      headers: { "Content-Type" => "application/json" })

    error, text = call_tool("clima_cidade", cidade: "Tóquio")

    refute error
    assert_equal "chuva", JSON.parse(text).dig("previsao", 0, "condicao")
  end

  test "buscar_cep aceita hífen" do
    stub_json("https://brasilapi.com.br/api/cep/v2/01310100",
              cep: "01310100", street: "Avenida Paulista", neighborhood: "Bela Vista", city: "São Paulo", state: "SP")

    error, text = call_tool("buscar_cep", cep: "01310-100")

    refute error
    assert_equal "Avenida Paulista", JSON.parse(text)["logradouro"]
  end

  test "buscar_cep 404 vira erro da tool, não do servidor" do
    stub_request(:get, "https://brasilapi.com.br/api/cep/v2/00000000").to_return(status: 404)

    error, text = call_tool("buscar_cep", cep: "00000000")

    assert error
    assert_includes text, "404"
  end

  test "orcamento_viagem calcula com IOF" do
    error, text = call_tool("orcamento_viagem", dias: 5, gasto_diario: 100, moeda: "USD", cotacao_em_reais: 5.0, custos_fixos_reais: 1000)

    refute error
    data = JSON.parse(text)
    assert_equal 2500.0, data["gastos_em_reais"]
    assert_equal 87.5, data["iof_cartao_reais"]
    assert_equal 3587.5, data["total_geral_reais"]
  end

  test "argumento obrigatório ausente é validado pela gem" do
    error, text = call_tool("orcamento_viagem", dias: 5)

    assert error
    assert_includes text, "Missing required arguments"
  end
end
