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

  # GET abriria um stream SSE e DELETE encerraria uma sessão. Este servidor é stateless e só
  # responde JSON, então segue a spec do Streamable HTTP: 405 diz ao cliente para usar só POST.
  def method_not_allowed
    response.set_header("Allow", "POST")
    head :method_not_allowed
  end
end
