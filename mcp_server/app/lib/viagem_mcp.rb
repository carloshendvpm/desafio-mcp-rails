# Registro das tools e construção do servidor MCP.
# Um servidor novo por request: o transporte é stateless (JSON-RPC sobre HTTP),
# então não há sessão para manter entre chamadas.
module ViagemMcp
  TOOLS = [
    FeriadosNacionaisTool,
    CotacaoMoedaTool,
    InfoPaisTool,
    ClimaCidadeTool,
    BuscarCepTool,
    OrcamentoViagemTool
  ].freeze

  def self.server
    MCP::Server.new(
      name: "viagem-mcp",
      title: "Assistente de Viagem",
      version: "1.0.0",
      instructions: "Ferramentas para planejar viagens: feriados, câmbio, países, clima, CEP e orçamento.",
      tools: TOOLS
    )
  end
end
