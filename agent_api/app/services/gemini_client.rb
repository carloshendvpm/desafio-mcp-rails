# Cliente REST do Gemini (generateContent), sem SDK.
# Recebe o histórico da conversa (`contents`) e as tools declaradas, e devolve
# o `content` do modelo: partes de texto e/ou `functionCall`.
class GeminiClient
  class Error < StandardError; end

  BASE_URL = "https://generativelanguage.googleapis.com/v1beta/models".freeze

  def initialize(api_key: ENV.fetch("GEMINI_API_KEY"), model: ENV.fetch("GEMINI_MODEL", "gemini-flash-latest"))
    @api_key = api_key
    @model = model
  end

  def generate(contents:, function_declarations: [], system_instruction: nil)
    body = { contents: contents }
    body[:tools] = [ { functionDeclarations: function_declarations } ] if function_declarations.any?
    body[:systemInstruction] = { parts: [ { text: system_instruction } ] } if system_instruction

    response = connection.post("#{BASE_URL}/#{@model}:generateContent", body)
    response.body.dig("candidates", 0, "content") ||
      raise(Error, "Gemini não retornou conteúdo: #{response.body.dig("candidates", 0, "finishReason") || response.body}")
  rescue Faraday::Error => e
    raise Error, "Erro na API do Gemini: #{e.response&.dig(:body, "error", "message") || e.message}"
  end

  private

  def connection
    @connection ||= Faraday.new(headers: { "x-goog-api-key" => @api_key },
                                request: { timeout: 90, open_timeout: 5 }) do |f|
      f.request :json
      f.response :raise_error
      f.response :json
    end
  end
end
