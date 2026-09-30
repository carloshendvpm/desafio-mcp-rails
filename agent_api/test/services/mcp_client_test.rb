require "test_helper"

class McpClientTest < ActiveSupport::TestCase
  def stub_rpc(result: nil, error: nil)
    stub_request(:post, "http://mcp.test/mcp")
      .to_return(body: { jsonrpc: "2.0", id: 1, result: result, error: error }.compact.to_json,
                 headers: { "Content-Type" => "application/json" })
  end

  test "list_tools envia tools/list em JSON-RPC" do
    stub_rpc(result: { tools: [ { name: "buscar_cep" } ] })

    assert_equal "buscar_cep", McpClient.new.list_tools.first["name"]
    assert_requested(:post, "http://mcp.test/mcp") { |req| JSON.parse(req.body)["method"] == "tools/list" }
  end

  test "call_tool junta o conteúdo de texto e o flag de erro" do
    stub_rpc(result: { content: [ { type: "text", text: "CEP não encontrado" } ], isError: true })

    assert_equal({ text: "CEP não encontrado", error: true }, McpClient.new.call_tool("buscar_cep", cep: "0"))
  end

  test "erro JSON-RPC vira McpClient::Error" do
    stub_rpc(error: { code: -32602, message: "Tool not found: x" })

    assert_raises(McpClient::Error) { McpClient.new.call_tool("x") }
  end

  test "servidor fora do ar vira McpClient::Error" do
    stub_request(:post, "http://mcp.test/mcp").to_raise(Faraday::ConnectionFailed.new("refused"))

    assert_raises(McpClient::Error) { McpClient.new.list_tools }
  end
end
