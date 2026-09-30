class AskController < ApplicationController
  rescue_from McpClient::Error, GeminiClient::Error, Agent::TooManyTurns do |e|
    render json: { error: e.message }, status: :bad_gateway
  end

  # POST /ask { "question": "...", "history": [{ "role": "user"|"model", "text": "..." }] }
  def create
    question = params.require(:question)
    history = params.fetch(:history, []).map { |m| m.permit(:role, :text).to_h }
    result = Agent.new.ask(question, history: history)

    render json: { question: question, answer: result.answer, steps: result.steps }
  end

  # GET /tools — o que o agente descobriu no MCP server (tools/list)
  def tools
    render json: McpClient.new.list_tools
  end
end
