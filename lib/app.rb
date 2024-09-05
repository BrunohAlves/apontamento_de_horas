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

  begin
    clockify_connector = ConnectorManager.get_clockify_connector(api_key_clockify, email, workspace_name, logger)
    redmine_connector = ConnectorManager.get_redmine_connector(api_key_redmine, logger)
    differential_updater = DifferentialUpdater.new(redmine_connector, clockify_connector, logger)

    logger.info('Starting Job')
    differential_updater.sync_issues
    # differential_updater.sync_time_entries
  rescue StandardError => e
    logger.error("Error during job execution: #{e.message}")
  end
end

main
