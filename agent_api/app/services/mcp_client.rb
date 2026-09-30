# Cliente MCP mínimo, escrito à mão para deixar o protocolo visível.
# MCP é JSON-RPC 2.0; aqui usamos o transporte HTTP: cada mensagem é um POST.
#
#   initialize  -> handshake (versão do protocolo, capabilities)
#   tools/list  -> descoberta: nome, descrição e JSON Schema de cada tool
#   tools/call  -> execução: { name, arguments } -> { content: [...], isError }
class McpClient
  class Error < StandardError; end

  PROTOCOL_VERSION = "2025-06-18".freeze

  def initialize(url: ENV.fetch("MCP_SERVER_URL", "http://localhost:3001/mcp"))
    @url = url
    @next_id = 0
  end

  def initialize_session
    rpc("initialize", protocolVersion: PROTOCOL_VERSION, capabilities: {},
                      clientInfo: { name: "agent-api", version: "1.0.0" })
  end

  # => [{ "name" => "buscar_cep", "description" => "...", "inputSchema" => {...} }, ...]
  def list_tools
    rpc("tools/list").fetch("tools")
  end

  # => { text: "resultado da tool", error: false }
  def call_tool(name, arguments = {})
    result = rpc("tools/call", name: name, arguments: arguments)
    text = result.fetch("content", []).filter_map { |c| c["text"] }.join("\n")

    { text: text, error: result["isError"] == true }
  end

  private

  def rpc(method, params = {})
    body = { jsonrpc: "2.0", id: @next_id += 1, method: method, params: params }
    response = connection.post(@url, body)

    raise Error, "MCP #{method}: #{response.body["error"]["message"]}" if response.body["error"]
    response.body.fetch("result")
  rescue Faraday::Error => e
    raise Error, "Não foi possível falar com o MCP server em #{@url}: #{e.message}"
  end

  def connection
    @connection ||= Faraday.new(headers: { "Accept" => "application/json, text/event-stream" },
                                request: { timeout: 30, open_timeout: 5 }) do |f|
      f.request :json
      f.response :raise_error
      f.response :json
    end
  end
end
