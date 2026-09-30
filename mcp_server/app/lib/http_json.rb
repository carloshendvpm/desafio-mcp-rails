# Helper HTTP compartilhado pelas tools: GET que devolve JSON já parseado.
# Qualquer falha de rede/HTTP vira HttpJson::Error, que o ApplicationTool
# transforma em resposta de erro da tool (isError: true) em vez de derrubar o servidor.
module HttpJson
  class Error < StandardError; end

  def self.get(url, params = {})
    connection.get(url, params).body
  rescue Faraday::ResourceNotFound
    raise Error, "Nada encontrado (404) em #{url}"
  rescue Faraday::Error => e
    raise Error, "Falha ao consultar #{url}: #{e.message}"
  end

  def self.connection
    @connection ||= Faraday.new(request: { timeout: 10, open_timeout: 5 }) do |f|
      f.response :raise_error
      f.response :json
    end
  end
end
