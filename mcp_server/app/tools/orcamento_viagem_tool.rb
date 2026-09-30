# Tool puramente local (sem API externa): mostra que uma tool pode ser só lógica.
# Não busca a cotação sozinha de propósito — o modelo precisa encadear
# `cotacao_moeda` antes e passar o valor aqui.
class OrcamentoViagemTool < ApplicationTool
  tool_name "orcamento_viagem"
  description "Calcula o orçamento total de uma viagem em reais a partir do gasto diário em moeda " \
              "estrangeira. Requer a cotação atual (use a tool cotacao_moeda antes)."
  input_schema(
    properties: {
      dias: { type: "integer", minimum: 1, description: "Duração da viagem em dias" },
      gasto_diario: { type: "number", minimum: 0, description: "Gasto previsto por dia na moeda local" },
      moeda: { type: "string", description: "Código ISO da moeda do gasto diário, ex: JPY" },
      cotacao_em_reais: { type: "number", exclusiveMinimum: 0, description: "Quanto 1 unidade da moeda vale em BRL" },
      custos_fixos_reais: { type: "number", minimum: 0, description: "Custos fixos já em reais (passagem, seguro). Padrão: 0" }
    },
    required: [ "dias", "gasto_diario", "moeda", "cotacao_em_reais" ]
  )
  annotations(read_only_hint: true, idempotent_hint: true)

  IOF_CARTAO = 0.035 # IOF sobre compras internacionais no cartão (2025+)

  def self.run(dias:, gasto_diario:, moeda:, cotacao_em_reais:, custos_fixos_reais: 0)
    total_moeda = dias * gasto_diario
    total_reais = total_moeda * cotacao_em_reais
    iof = total_reais * IOF_CARTAO

    {
      dias: dias,
      total_na_moeda: "#{total_moeda.round(2)} #{moeda.upcase}",
      gastos_em_reais: total_reais.round(2),
      iof_cartao_reais: iof.round(2),
      custos_fixos_reais: custos_fixos_reais.round(2),
      total_geral_reais: (total_reais + iof + custos_fixos_reais).round(2),
      media_por_dia_reais: ((total_reais + iof) / dias).round(2)
    }
  end
end
