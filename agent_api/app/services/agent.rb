# O agente: liga o Gemini às tools do MCP server.
#
#   1. Descoberta: pergunta ao MCP quais tools existem (tools/list) e as converte
#      em `functionDeclarations` do Gemini. O modelo só "enxerga" o que o MCP anuncia.
#   2. O modelo decide: responde em texto OU pede uma/várias `functionCall`.
#   3. Para cada functionCall, o agente executa `tools/call` no MCP e devolve o
#      resultado ao modelo como `functionResponse`.
#   4. Repete até o modelo responder em texto (ou atingir MAX_TURNS).
class Agent
  MAX_TURNS = 8

  class TooManyTurns < StandardError; end

  Result = Data.define(:answer, :steps)

  def initialize(mcp: McpClient.new, gemini: GeminiClient.new)
    @mcp = mcp
    @gemini = gemini
  end

  def ask(question)
    declarations = function_declarations
    contents = [ { role: "user", parts: [ { text: question } ] } ]
    steps = []

    MAX_TURNS.times do
      model_content = @gemini.generate(contents: contents, function_declarations: declarations,
                                       system_instruction: system_instruction)
      contents << model_content # mantém o histórico (inclui thoughtSignature exigida pelo Gemini)

      calls = model_content.fetch("parts", []).filter_map { |part| part["functionCall"] }
      return Result.new(answer: final_text(model_content), steps: steps) if calls.empty?

      contents << { role: "user", parts: calls.map { |call| execute(call, steps) } }
    end

    raise TooManyTurns, "O modelo não concluiu a resposta em #{MAX_TURNS} rodadas"
  end

  # tools/list do MCP -> formato de functionDeclarations do Gemini.
  # `parametersJsonSchema` aceita JSON Schema, então o inputSchema do MCP passa quase direto.
  def function_declarations
    @mcp.list_tools.map do |tool|
      {
        name: tool["name"],
        description: tool["description"],
        parametersJsonSchema: tool["inputSchema"].except("$schema")
      }
    end
  end

  private

  def execute(call, steps)
    args = call["args"] || {}
    result = @mcp.call_tool(call["name"], args)
    steps << { tool: call["name"], args: args, error: result[:error], result: result[:text].truncate(600) }

    {
      functionResponse: {
        id: call["id"],
        name: call["name"],
        response: result[:error] ? { error: result[:text] } : { output: result[:text] }
      }.compact
    }
  end

  def final_text(content)
    content["parts"].reject { |p| p["thought"] }.filter_map { |p| p["text"] }.join.strip
  end

  def system_instruction
    <<~PROMPT
      Você é um assistente de viagem simpático e objetivo. Responda sempre em português do Brasil.
      Hoje é #{Date.current.strftime("%d/%m/%Y")}.
      Use as ferramentas disponíveis sempre que a pergunta depender de dados reais (feriados,
      câmbio, clima, países, CEP, orçamento). Não invente valores: se precisar de uma cotação
      para calcular um orçamento, consulte a cotação antes. Você pode chamar várias ferramentas.
      Se uma ferramenta falhar, explique o problema ao usuário.
    PROMPT
  end
end
