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
  MAX_HISTORY = 10 # mensagens anteriores (pergunta/resposta) enviadas como contexto

  class TooManyTurns < StandardError; end

  Result = Data.define(:answer, :steps)

  def initialize(mcp: McpClient.new, gemini: GeminiClient.new)
    @mcp = mcp
    @gemini = gemini
  end

  # `history`: turnos anteriores da conversa, [{ "role" => "user"|"model", "text" => "..." }].
  # A API continua stateless: quem guarda a conversa é o cliente, que a reenvia a cada pergunta.
  def ask(question, history: [])
    declarations = function_declarations
    contents = history_contents(history) + [ { role: "user", parts: [ { text: question } ] } ]
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

  def history_contents(history)
    history.last(MAX_HISTORY).filter_map do |message|
      role, text = message.values_at("role", "text")
      next unless %w[user model].include?(role) && text.present?

      { role: role, parts: [ { text: text.to_s } ] }
    end
  end

  def final_text(content)
    content["parts"].reject { |p| p["thought"] }.filter_map { |p| p["text"] }.join.strip
  end

  def system_instruction
    <<~PROMPT
      Você é um assistente de viagem. Responda em português do Brasil, de forma direta e curta.
      Hoje é #{Date.current.strftime("%d/%m/%Y")}.

      Regras:
      - Dados reais (feriados, férias, câmbio, clima, países, CEP) vêm só das ferramentas. Nunca estime
        nem invente preços, custo de vida ou qualquer valor que nenhuma ferramenta retornou.
      - Toda conversão para reais e todo orçamento passam pela ferramenta orcamento_viagem
        (com a cotação obtida em cotacao_moeda). Não faça contas de câmbio por conta própria.
      - Se faltar dado para o orçamento (quantos dias, gasto diário), responda o que já dá
        para responder e termine pedindo o que falta em uma única frase.
      - Na previsão do tempo, mostre só os dias relevantes para a viagem.
      - Formato: markdown simples (negrito e listas curtas). Sem títulos, sem separadores,
        no máximo um emoji. Idealmente até 10 linhas.
      - Se uma ferramenta falhar, diga isso em uma frase e siga com o resto.
    PROMPT
  end
end
