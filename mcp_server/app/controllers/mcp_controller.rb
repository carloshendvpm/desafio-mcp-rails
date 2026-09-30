# Endpoint MCP (Streamable HTTP, modo stateless com respostas JSON).
# Recebe JSON-RPC (initialize, tools/list, tools/call...) e delega para a gem `mcp`.
class McpController < ApplicationController
  def handle
    response_json = ViagemMcp.server.handle_json(request.body.read)

    if response_json
      render json: response_json
    else
      head :accepted # notificações JSON-RPC não têm resposta
    end
  end
end
