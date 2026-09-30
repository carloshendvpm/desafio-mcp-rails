# Classe base das tools. Cada tool implementa `self.run(**args)` e devolve
# um Hash/Array (serializado como JSON) ou uma String.
#
# A gem `mcp` chama `self.call(**args, server_context:)` quando chega um
# `tools/call`; aqui centralizamos a conversão para MCP::Tool::Response.
class ApplicationTool < MCP::Tool
  class << self
    def call(server_context: nil, **args)
      ok(run(**args))
    rescue HttpJson::Error, ArgumentError => e
      error(e.message)
    end

    def run(**)
      raise NotImplementedError
    end

    private

    def ok(data)
      text = data.is_a?(String) ? data : JSON.pretty_generate(data)
      MCP::Tool::Response.new([ { type: "text", text: text } ])
    end

    def error(message)
      MCP::Tool::Response.new([ { type: "text", text: message } ], error: true)
    end
  end
end
