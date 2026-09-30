require "test_helper"

class AskTest < ActionDispatch::IntegrationTest
  test "POST /ask sem pergunta retorna 400" do
    post "/ask", params: {}, as: :json
    assert_response :bad_request
  end

  test "MCP fora do ar retorna 502 com mensagem" do
    stub_request(:post, "http://mcp.test/mcp").to_raise(Faraday::ConnectionFailed.new("refused"))

    post "/ask", params: { question: "oi" }, as: :json

    assert_response :bad_gateway
    assert_includes response.parsed_body["error"], "MCP server"
  end
end
