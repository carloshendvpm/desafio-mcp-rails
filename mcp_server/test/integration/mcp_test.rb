require "test_helper"

class McpTest < ActionDispatch::IntegrationTest
  test "initialize anuncia o servidor e a capability de tools" do
    result = rpc("initialize", protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "test", version: "1" })["result"]

    assert_equal "viagem-mcp", result.dig("serverInfo", "name")
    assert result.dig("capabilities", "tools")
  end

  test "tools/list expõe as 7 tools com schema" do
    tools = rpc("tools/list").dig("result", "tools")

    assert_equal %w[feriados_nacionais cotacao_moeda info_pais clima_cidade buscar_cep orcamento_viagem planejar_ferias],
                 tools.map { |t| t["name"] }
    assert tools.all? { |t| t["description"].present? && t.dig("inputSchema", "type") == "object" }
  end

  test "notificação não tem corpo de resposta" do
    post "/mcp", params: { jsonrpc: "2.0", method: "notifications/initialized" }.to_json,
                 headers: { "Content-Type" => "application/json" }
    assert_response :accepted
  end

  test "GET e DELETE respondem 405 (sem stream SSE nem sessão)" do
    get "/mcp"
    assert_response :method_not_allowed
    assert_equal "POST", response.headers["Allow"]

    delete "/mcp"
    assert_response :method_not_allowed
  end

  test "tools são anunciadas como somente leitura e não destrutivas" do
    annotations = rpc("tools/list").dig("result", "tools").map { |t| t["annotations"] }

    assert annotations.all? { |a| a["readOnlyHint"] == true && a["destructiveHint"] == false }
  end

  test "tool inexistente devolve erro JSON-RPC" do
    assert rpc("tools/call", name: "nao_existe", arguments: {})["error"]
  end
end
