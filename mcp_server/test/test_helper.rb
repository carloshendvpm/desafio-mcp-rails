ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"

module ActiveSupport
  class TestCase
    # Chama o endpoint MCP como um cliente faria (JSON-RPC via HTTP POST).
    def rpc(method, params = {})
      post "/mcp", params: { jsonrpc: "2.0", id: 1, method: method, params: params }.to_json,
                   headers: { "Content-Type" => "application/json" }
      ::JSON.parse(response.body)
    end

    def call_tool(name, arguments = {})
      result = rpc("tools/call", name: name, arguments: arguments)["result"]
      [ result["isError"], result.dig("content", 0, "text") ]
    end

    def stub_json(url, body)
      stub_request(:get, url).to_return(body: body.to_json, headers: { "Content-Type" => "application/json" })
    end
  end
end
