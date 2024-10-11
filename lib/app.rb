require 'logger'
require_relative 'manager'
require_relative '../support/error_handling'
require_relative 'differential_updater'

def main
  logger = Logger.new(STDOUT)
  logger.level = Logger::INFO

  api_key_clockify = 'your_clockify_api_key'
  api_key_redmine = 'your_redmine_api_key'
  email = 'your_email'
  workspace_name = 'workspace_name'
  workspace_id = 'workspace_id'

  begin
    logger.info('Obtendo conector do Clockify...')
    clockify_connector = ConnectorManager.get_clockify_connector(api_key_clockify, email, workspace_name, logger)

    if clockify_connector.nil?
      logger.error('Falha ao inicializar o conector do Clockify')
      raise 'Falha ao inicializar o conector do Clockify'
    end

    logger.info('Obtendo conector do Redmine...')

    redmine_connector = ConnectorManager.get_redmine_connector(api_key_redmine, clockify_connector, logger)

    if redmine_connector.nil?
      logger.error('Falha ao inicializar o conector do Redmine')
      raise 'Falha ao inicializar o conector do Redmine'
    end

    # logger.info("RedmineConnector: #{redmine_connector.inspect}")

    # Verificação: Teste para garantir que o conector foi corretamente inicializado
    unless redmine_connector.respond_to?(:find_issue_by_task_name)
      logger.error("Erro: Conector do Redmine não está inicializado corretamente ou faltando métodos essenciais.")
      raise 'RedmineConnector não está funcionando corretamente'
    end

    logger.info('Iniciando Execução')

    user_id = clockify_connector.find_user_id_by_email(email)
    if user_id.nil?
      logger.error('Falha ao obter o User ID do Clockify')
      raise 'Falha ao obter o User ID do Clockify'
    end
    logger.info("User ID obtido para #{email}: #{user_id}")

    differential_updater = DifferentialUpdater.new(redmine_connector, clockify_connector, logger)
    differential_updater.update_clockify_projects_and_tasks
    differential_updater.update_redmine_time_entries(user_id)

  rescue StandardError => e
    logger.error("Erro durante a execução: #{e.message}")
    logger.error(e.backtrace.join("\n")) if e.backtrace
  end
end

main
