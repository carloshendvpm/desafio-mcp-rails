# 🧳 Desafio MCP + Rails — Agente de Viagem

Dois serviços Rails independentes:

| Serviço | Porta | O que faz |
|---|---|---|
| [`mcp_server/`](mcp_server) | 3001 | **Servidor MCP** com 6 tools de viagem (gem oficial [`mcp`](https://github.com/modelcontextprotocol/ruby-sdk)) |
| [`agent_api/`](agent_api) | 3000 | **API do agente**: recebe a pergunta, usa o **Gemini** e consome as tools do MCP |

```
Usuário ──POST /ask──▶ Agent API ──generateContent──▶ Gemini
                          │  ▲                            │
                          │  └──── functionCall ◀─────────┘
                          │
                          ├──tools/call (JSON-RPC)──▶ MCP Server ──▶ Tool ──▶ API pública
                          │  ◀──── resultado ─────────┘
                          │
                          └──functionResponse──▶ Gemini ──▶ resposta final ──▶ Usuário
```

## Tools

| Tool | Fonte | Exemplo |
|---|---|---|
| `feriados_nacionais` | BrasilAPI | próximos feriados do ano |
| `cotacao_moeda` | AwesomeAPI | JPY → BRL agora |
| `info_pais` | dataset `world-countries` (jsDelivr) | capital, moeda, idioma, DDI |
| `clima_cidade` | Open-Meteo | previsão de até 14 dias |
| `buscar_cep` | BrasilAPI | endereço de um CEP |
| `orcamento_viagem` | *local, sem API* | total em R$ + IOF (depende de `cotacao_moeda`) |

## Como funciona

**1. MCP Server (`mcp_server`)**
- Cada tool é uma classe em `app/tools/` que herda de `ApplicationTool < MCP::Tool`, com `description`, `input_schema` (JSON Schema) e `self.run(**args)`.
- `app/lib/viagem_mcp.rb` registra as tools em um `MCP::Server`.
- `McpController#handle` (`POST /mcp`) repassa o corpo JSON-RPC para `server.handle_json`. A gem cuida de `initialize`, `tools/list`, `tools/call` e da validação dos argumentos.
- Se uma API externa falha, a tool responde `isError: true` com uma mensagem, e o servidor não cai. O modelo pode explicar o erro ou tentar de outro jeito.

**2. Agent API (`agent_api`)**
- `McpClient` é um cliente JSON-RPC mínimo, escrito à mão para o protocolo ficar visível: `tools/list` e `tools/call`.
- `GeminiClient` chama a API REST `generateContent` do Gemini com `functionDeclarations`.
- `Agent` é o loop do agente:
  1. **Descoberta**: faz `tools/list` e converte cada tool em `functionDeclaration`. O `inputSchema` do MCP vira `parametersJsonSchema`.
  2. Envia a pergunta com as tools. **O modelo decide** com base no nome, na descrição e no schema de cada tool.
  3. Se vier `functionCall`, o agente executa `tools/call` no MCP e devolve o resultado como `functionResponse`.
  4. Repete até vir texto, no máximo 8 rodadas. O histórico inteiro vai em cada chamada, porque o modelo é stateless.
- `POST /ask` retorna `{ answer, steps }`. `steps` mostra quais tools foram chamadas, com quais argumentos e o que retornaram.
- `GET /` abre uma página de demo. `GET /tools` mostra o que o agente descobriu no MCP.

## Rodando

Requisitos: Ruby 3.4 e uma chave do Gemini.

```bash
cd mcp_server && bundle install && cd ..
cd agent_api && bundle install && cp .env.example .env && cd ..   # coloque sua GEMINI_API_KEY no .env
bin/dev                                                           # sobe as duas portas
```

Abra <http://localhost:3000> ou:

```bash
curl -s localhost:3000/ask -H 'Content-Type: application/json' \
  -d '{"question":"Vou pro Japão no próximo feriado por 5 dias gastando 15000 ienes/dia. Quanto dá em reais e como está o clima em Tóquio?"}'
```

Falando MCP direto com o servidor:

```bash
curl -s localhost:3001/mcp -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'

curl -s localhost:3001/mcp -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"buscar_cep","arguments":{"cep":"01310-100"}}}'
```

O servidor também funciona com o MCP Inspector: `npx @modelcontextprotocol/inspector`, com transporte Streamable HTTP e URL `http://localhost:3001/mcp`.

## Testes

```bash
(cd mcp_server && bin/rails test)   # tools com APIs externas stubadas (WebMock) + protocolo MCP
(cd agent_api && bin/rails test)    # loop do agente com dublês, cliente MCP, erros
```

## Perguntas para testar

- "Qual o próximo feriado nacional?" → 1 tool
- "Vou pro Japão no próximo feriado por 5 dias gastando 15000 ienes/dia. Quanto dá em reais e como está o clima em Tóquio?" → feriados, cotação, clima e orçamento encadeados
- "Que moeda usam na Argentina e quanto ela vale hoje?" → `info_pais` e depois `cotacao_moeda`, porque o resultado de uma tool alimenta a outra
- "Qual o endereço do CEP 01310-100?"
