require 'logger'
require_relative 'manager'
require_relative '../support/error_handling'
require_relative 'differential_updater'

def main
  logger = Logger.new(STDOUT)
  logger.level = Logger::DEBUG

  api_key_clockify = 'MDM3MzM4NDktYzRlYS00YzFlLWIxM2YtNTY2YWM1NzBhZGU3'
  api_key_redmine = 'd3bc111102694a9eeb2c9a874bc6edb602de44ed'
  email = 'raphael.costa@luizalabs.com'
  workspace_name = 'Turia'
  days_ago = '7'

  begin
    clockify_connector = ConnectorManager.get_clockify_connector(api_key_clockify, email, workspace_name, logger)
    redmine_connector = ConnectorManager.get_redmine_connector(api_key_redmine, logger)
    differential_updater = DifferentialUpdater.new(redmine_connector, clockify_connector, logger)

    logger.info('Iniciando Execução')
    differential_updater.update_clockify_projects_and_tasks
    differential_updater.update_redmine_time_entries(days_ago)
  rescue StandardError => e
    logger.error("Erro durante a execução: #{e.message}")
  end
end

main
