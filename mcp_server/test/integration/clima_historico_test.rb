require "test_helper"

class ClimaHistoricoTest < ActionDispatch::IntegrationTest
  ARCHIVE = %r{archive-api\.open-meteo\.com/v1/archive}

  setup do
    travel_to Date.new(2026, 9, 30)
    stub_request(:get, %r{geocoding-api.open-meteo.com}).to_return(
      body: { results: [ { name: "Bariloche", country: "Argentina", latitude: -41.1, longitude: -71.3 } ] }.to_json,
      headers: { "Content-Type" => "application/json" })
  end

  # dias: { "AAAA-MM-DD" => [max, min, chuva_mm, neve_cm] }
  def stub_archive(dias)
    stub_request(:get, ARCHIVE).to_return(
      body: { daily: { time: dias.keys,
                       temperature_2m_max: dias.values.map { _1[0] }, temperature_2m_min: dias.values.map { _1[1] },
                       precipitation_sum: dias.values.map { _1[2] }, snowfall_sum: dias.values.map { _1[3] || 0 },
                       wind_speed_10m_max: dias.values.map { 10 } } }.to_json,
      headers: { "Content-Type" => "application/json" })
  end

  def consultar(inicio = "2027-07-10", fim = "2027-07-11")
    error, text = call_tool("clima_historico", cidade: "Bariloche", data_inicio: inicio, data_fim: fim)
    [ error, error ? text : JSON.parse(text) ]
  end

  test "faz uma chamada para os 5 anos e usa só as datas da viagem" do
    stub_archive("2022-07-10" => [ 6, -1, 0 ], "2022-07-12" => [ 30, 20, 0 ], "2026-07-11" => [ 4, -3, 5 ])

    _, clima = consultar

    # julho/2027 ainda não aconteceu; o último julho completo é 2026 -> 2022 a 2026
    assert_requested(:get, %r{#{ARCHIVE}\?.*end_date=2026-07-11.*start_date=2022-07-10}, times: 1)
    assert_equal "mesmas datas de 2022 a 2026 (2 dias medidos)", clima["base"] # 12/07 ficou de fora
  end

  test "calcula médias e sugere roupas de frio e neve" do
    stub_archive("2025-07-10" => [ 6, -1, 0, 0 ], "2025-07-11" => [ 4, -3, 5, 3 ])

    error, clima = consultar

    refute error
    assert_equal({ "media_minima" => -2.0, "media_maxima" => 5.0, "menor_registrada" => -3, "maior_registrada" => 6 },
                 clima["temperatura_c"])
    assert_equal 50, clima["dias_com_chuva_pct"]
    assert_equal 50, clima["dias_com_neve_pct"]
    assert_includes clima["o_que_levar"].join, "casaco pesado"
    assert_includes clima["o_que_levar"].join, "antiderrapante"
  end

  test "calor sugere roupas leves e protetor" do
    stub_archive("2025-07-10" => [ 31, 22, 0 ], "2025-07-11" => [ 30, 23, 0 ])

    _, clima = consultar

    assert_equal [ "roupas leves, protetor solar, óculos escuros e chapéu" ], clima["o_que_levar"]
  end

  test "rejeita período maior que 31 dias ou invertido" do
    assert_includes consultar("2027-07-01", "2027-09-01").last, "Período máximo"
    assert_includes consultar("2027-07-10", "2027-07-01").last, "depois de"
  end
end
