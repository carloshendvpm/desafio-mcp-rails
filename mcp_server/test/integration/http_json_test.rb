require "test_helper"

class HttpJsonTest < ActiveSupport::TestCase
  test "tenta de novo uma vez quando a conexão falha" do
    stub_request(:get, "https://api.test/x")
      .to_raise(Faraday::ConnectionFailed.new("timeout")).then
      .to_return(body: { ok: true }.to_json, headers: { "Content-Type" => "application/json" })

    assert_equal({ "ok" => true }, HttpJson.get("https://api.test/x"))
  end

  test "desiste depois da nova tentativa e vira HttpJson::Error" do
    stub_request(:get, "https://api.test/x").to_raise(Faraday::ConnectionFailed.new("timeout"))

    assert_raises(HttpJson::Error) { HttpJson.get("https://api.test/x") }
    assert_requested(:get, "https://api.test/x", times: 2)
  end

  test "404 não é repetido" do
    stub_request(:get, "https://api.test/x").to_return(status: 404)

    assert_raises(HttpJson::Error) { HttpJson.get("https://api.test/x") }
    assert_requested(:get, "https://api.test/x", times: 1)
  end
end
