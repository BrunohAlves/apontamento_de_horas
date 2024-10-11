require_relative '../connector/clockify_connector'
require_relative '../connector/redmine_connector'
require 'logger'

module ConnectorManager
  # Inicializa o conector do Clockify
  def self.get_clockify_connector(api_key_clockify, email, workspace_name, logger)
    raise ArgumentError, 'Chave da API Clockify é obrigatória' if api_key_clockify.nil?

    begin
      clockify_client = ClockifyConnector::Client.new(api_key_clockify, email, workspace_name, logger)
      raise 'Conector Clockify não foi inicializado.' if clockify_client.nil?

      logger.info 'Conectado ao Clockify com sucesso.'
      clockify_client
    rescue HTTParty::Error => e
      logger.error "Erro ao conectar ao Clockify: #{e.message}"
      raise
    end
  end

  # Inicializa o conector do Redmine
  def self.get_redmine_connector(api_key_redmine, clockify_connector, logger)
    raise ArgumentError, 'Chave da API Redmine é obrigatória' if api_key_redmine.nil?

    begin
      redmine_client = RedmineConnector::Client.new(api_key_redmine, clockify_connector, logger)
      raise 'Conector Redmine não foi inicializado.' if redmine_client.nil?

      logger.info 'Conectado ao Redmine com sucesso.'
      redmine_client
    rescue HTTParty::Error => e
      logger.error "Erro HTTP ao conectar ao Redmine: #{e.message}"
      raise
    rescue StandardError => e
      logger.error("Erro durante a execução: #{e.message}")
      raise RedmineConnector::Error, "Falha ao obter o conector do Redmine"
    end
  end

  private

  # Verifica se o conector foi inicializado corretamente
  def self.ensure_connector_initialized(connector, name, logger)
    if connector.nil?
      raise "#{name}Connector não foi inicializado."
    else
      logger.info "Conectado ao #{name} com sucesso."
    end
  end

  # Loga e levanta o erro
  def self.log_error(service_name, error, logger)
    logger.error "Erro ao conectar ao #{service_name}: #{error.message}"
    raise
  end
end
