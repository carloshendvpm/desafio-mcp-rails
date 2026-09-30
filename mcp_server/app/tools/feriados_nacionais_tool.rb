class FeriadosNacionaisTool < ApplicationTool
  tool_name "feriados_nacionais"
  description "Lista os feriados nacionais do Brasil em um ano (BrasilAPI). " \
              "Indica quais já passaram, útil para planejar viagens em feriados."
  input_schema(
    properties: {
      ano: { type: "integer", description: "Ano com 4 dígitos. Padrão: ano atual." }
    }
  )
  annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: true)

  def self.run(ano: Date.current.year)
    feriados = HttpJson.get("https://brasilapi.com.br/api/feriados/v1/#{ano.to_i}")

    feriados.map do |f|
      data = Date.parse(f["date"])
      { data: f["date"], nome: f["name"], dia_semana: f["weekday"], ja_passou: data < Date.current }
    end
  end
end
