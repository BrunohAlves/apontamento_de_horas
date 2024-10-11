module ErrorHandling
  class RequestError < StandardError; end
  class TimeoutError < StandardError; end

  # Método para lidar com erros de requisição HTTP
  def self.handle_error(response, logger)
    return unless response

    # Captura o código de status e monta uma mensagem de erro baseada nele
    error_message = case response.code
                    when 400..499
                      "Erro do cliente (#{response.code}): #{response.message}"
                    when 500..599
                      "Erro do servidor (#{response.code}): #{response.message}"
                    else
                      "Falha na requisição com código #{response.code}: #{response.message}"
                    end

    # Se houver detalhes de erro adicionais nos cabeçalhos da resposta, adicioná-los à mensagem de erro
    if response.headers&.key?('X-Error-Details')
      error_message += " Detalhes adicionais: #{response.headers['X-Error-Details']}"
    end
  end

  # Método genérico para lidar com exceções
  def self.log_exception(e, logger)
    logger.error("Erro: #{e.message}")
    logger.error(e.backtrace.join("\n")) if e.backtrace
  end

  # Método para repetir operações falhas, com tentativas limitadas
  def self.with_retry(max_attempts = 5, logger, delay: 5, &block)
    attempts = 0
    begin
      attempts += 1
      yield
    rescue StandardError => e
      logger.error("Tentativa #{attempts} falhou: #{e.message}")
      if attempts < max_attempts
        logger.info("Tentando novamente (#{attempts}/#{max_attempts})...")
        sleep(delay)
        retry
      else
        logger.error("Todas as tentativas falharam após #{max_attempts} tentativas.")
        raise e
      end
    end
  end
end
