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
| `planejar_ferias` | BrasilAPI + regras CLT | melhores datas de férias emendando feriados e fins de semana |
| `requisitos_seguro_viagem` | *tabela local* (`config/seguro_viagem.yml`) | se o destino exige seguro, a cobertura mínima e a fonte da regra |
| `clima_historico` | Open-Meteo Archive | clima típico nas datas da viagem (últimos 5 anos) + o que levar na mala |

### `planejar_ferias`: férias CLT emendando feriados

Recebe a divisão das férias (ex: `[30]`, `[15, 15]`, `[14, 10, 6]`) e testa todas as datas de início possíveis. Para cada uma, estende o descanso para trás e para frente enquanto os dias forem fim de semana ou feriado nacional. Depois ordena as opções pelo total de dias de descanso. Regras da CLT aplicadas:

- As férias contam em dias corridos (art. 130). São até 3 períodos, um com pelo menos 14 dias e os outros com pelo menos 5 (art. 134 §1).
- As férias não podem começar nos 2 dias antes de um feriado ou do repouso semanal (art. 134 §3). Na prática, nunca começam na sexta, no sábado, no domingo, num feriado ou na véspera de um.
- O empregado precisa ser avisado 30 dias antes (art. 135), por isso a busca começa em hoje + 30. O pagamento sai até 2 dias antes do início (art. 145). As duas datas vão na resposta.
- Quando há vários períodos, eles são encaixados do maior para o menor, sem sobreposição.

Limitações: considera só feriados nacionais (o Carnaval vem da BrasilAPI, mas é ponto facultativo) e jornada de segunda a sexta.

### `requisitos_seguro_viagem`: exigência de seguro por destino

As regras ficam em [`config/seguro_viagem.yml`](mcp_server/config/seguro_viagem.yml), por código ISO do país, e cada regra traz `fonte` e `revisado_em`. O `status` é um destes:

- `obrigatorio`: exigido na entrada (ex: Espaço Schengen, com mínimo de €30.000).
- `verificar`: regra em mudança. A tool não afirma nada e pede para confirmar.
- `recomendado`: não é exigido na entrada.

Países fora da tabela caem num padrão que recomenda confirmar no consulado. O nome do país é resolvido pelo mesmo lookup da `info_pais`. Regras de entrada mudam, então a tabela precisa de revisão periódica. Um teste garante que toda regra tem status válido, fonte e data.

### `clima_historico`: o que levar na mala

Busca numa única chamada as mesmas datas da viagem nos últimos 5 anos e calcula as médias de mínima e máxima, a porcentagem de dias com chuva e com neve e o vento. A partir disso sugere roupas: casaco pesado, camadas quando o dia e a noite têm grande diferença, guarda-chuva, calçado para neve etc. Serve para viagens além dos 14 dias da `clima_cidade`, e a resposta deixa claro que é média histórica, não previsão.

Falhas de rede passageiras (conexão ou timeout) ganham uma nova tentativa automática no `HttpJson`, compartilhado por todas as tools.

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
- `POST /ask` recebe `{ question, history? }` e retorna `{ answer, steps }`. `steps` mostra quais tools foram chamadas, com quais argumentos e o que retornaram.
- **Conversa:** a API é stateless. O cliente (a página de demo) guarda as trocas e reenvia as últimas 10 em `history: [{ role: "user"|"model", text }]`. Assim o agente pode pedir um dado que falta ("quantos dias?") e o usuário responde na mensagem seguinte.
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

## Conectando o MCP server no Claude

O `mcp_server` segue o protocolo MCP padrão, então funciona com qualquer cliente MCP, não só com o nosso agente. As tools, as descrições e os schemas são os mesmos, e é o Claude quem decide quando chamar cada tool.

Suba só o servidor: `cd mcp_server && bin/rails s -p 3001`.

### Claude Code

O repo já traz um [`.mcp.json`](.mcp.json). Abra o `claude` na raiz do projeto e aprove o servidor `viagem` quando ele perguntar. Para usar em qualquer pasta:

```bash
claude mcp add --transport http viagem http://localhost:3001/mcp
```

Depois é só perguntar, por exemplo: *"quais as melhores datas pra tirar 10 dias de férias em 2027?"*. O Claude chama `mcp__viagem__planejar_ferias`. O comando `/mcp` mostra as tools descobertas.

Também dá para testar sem abrir o modo interativo:

```bash
claude -p "Qual a melhor data pra 10 dias de férias em 2027?" \
  --mcp-config .mcp.json --strict-mcp-config --allowedTools "mcp__viagem__planejar_ferias"
```

### Claude Desktop

O Claude Desktop inicia servidores locais como processos (stdio). O pacote [`mcp-remote`](https://www.npmjs.com/package/mcp-remote) faz a ponte até o nosso HTTP. Em `claude_desktop_config.json` (Settings → Developer → Edit Config):

```json
{
  "mcpServers": {
    "viagem": {
      "command": "npx",
      "args": ["-y", "mcp-remote", "http://localhost:3001/mcp"]
    }
  }
}
```

Reinicie o app e as tools aparecem no menu de ferramentas da conversa. No Windows com WSL2, o `localhost` do Windows já alcança o servidor rodando no WSL.

### claude.ai (conector personalizado)

O claude.ai conecta pela internet, então o servidor precisa de uma URL pública em HTTPS. Para uma demo, use um túnel:

```bash
ngrok http 3001   # gera https://xxxx.ngrok-free.app (hosts do ngrok já liberados em development.rb)
```

Em **Settings → Connectors → Add custom connector**, informe `https://xxxx.ngrok-free.app/mcp`.

> ⚠️ O `/mcp` não tem autenticação: qualquer um com a URL do túnel pode chamar as tools. Use o túnel só durante a demo. Em produção, o caminho seria OAuth, que a spec do MCP prevê.

### Detalhes de protocolo que fazem isso funcionar

- **Streamable HTTP stateless:** cada `POST /mcp` é independente e a resposta é JSON. `GET` e `DELETE` respondem `405`, o que diz ao cliente que não há stream SSE nem sessão para encerrar.
- **Annotations:** todas as tools são anunciadas com `readOnlyHint: true` e `destructiveHint: false`. Clientes como o Claude usam isso para decidir quanto cuidado pedir antes de executar.

## Testes

```bash
(cd mcp_server && bin/rails test)   # tools (inclui regras CLT de férias) com APIs externas stubadas (WebMock) + protocolo MCP
(cd agent_api && bin/rails test)    # loop do agente com dublês, cliente MCP, erros
```

## Perguntas para testar

- "Qual o próximo feriado nacional?" → 1 tool
- "Vou pro Japão no próximo feriado por 5 dias gastando 15000 ienes/dia. Quanto dá em reais e como está o clima em Tóquio?" → feriados, cotação, clima e orçamento encadeados
- "Que moeda usam na Argentina e quanto ela vale hoje?" → `info_pais` e depois `cotacao_moeda`, porque o resultado de uma tool alimenta a outra
- "Qual o endereço do CEP 01310-100?"
- "Tenho 30 dias de férias em 2027 e quero dividir em 3 períodos. Quais as melhores datas pra emendar com feriados?"
- "Vou pra Lisboa de 10 a 20 de dezembro. Preciso de seguro viagem? Que roupas eu levo?" → `requisitos_seguro_viagem` e `clima_historico`
- "Quero tirar 10 dias de férias ainda esse ano e ir pra Buenos Aires gastando 150 mil pesos por dia. Quando é melhor e quanto sai?" → `planejar_ferias`, `cotacao_moeda` e `orcamento_viagem`
