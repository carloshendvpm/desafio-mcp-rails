class AskController < ApplicationController
  rescue_from McpClient::Error, GeminiClient::Error, Agent::TooManyTurns do |e|
    render json: { error: e.message }, status: :bad_gateway
  end

  # POST /ask { "question": "..." }
  def create
    question = params.require(:question)
    result = Agent.new.ask(question)

    render json: { question: question, answer: result.answer, steps: result.steps }
  end

  # GET /tools — o que o agente descobriu no MCP server (tools/list)
  def tools
    render json: McpClient.new.list_tools
  end
end
