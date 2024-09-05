module ErrorHandling
  class RequestError < StandardError; end

  def self.handle_error(response, logger)
    unless response.respond_to?(:code) && response.respond_to?(:message) &&
           response.code.is_a?(Integer) && response.message.is_a?(String)
      error_message = "Invalid response object received: #{response.inspect}"
      logger.error(error_message)
      raise RequestError, error_message
    end

    error_message = "Request failed with code #{response.code}: #{response.message}"
    logger.error(error_message)

    # Verificar se a API retorna informações adicionais
    if response.respond_to?(:headers) && response.headers['X-Error-Details']
      error_message += " Additional details: #{response.headers['X-Error-Details']}"
    end

    raise RequestError, error_message
  end
end
