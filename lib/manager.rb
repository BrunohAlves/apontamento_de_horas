require 'logger'
require 'httparty'
require_relative '../support/error_handling'
require_relative '../connector/redmine_connector'
require_relative '../connector/clockify_connector'

module ConnectorManager
  def self.get_redmine_connector(api_key_redmine, logger)
    raise ArgumentError, 'API key is required' if api_key_redmine.nil?

    begin
      redmine_client = RedmineConnector::Client.new(api_key_redmine, logger)

      logger.info 'Connected to Redmine successfully.'
      redmine_client
    rescue RedmineConnector::Error => e
      logger.error "Error connecting to Redmine: #{e.message}"
      raise
    end
  end

  def self.get_clockify_connector(api_key_clockify, email, workspace_name, logger)
    raise ArgumentError, 'API key is required' if api_key_clockify.nil?

    begin
      ClockifyConnector::Client.new(api_key_clockify, email, workspace_name, logger)
    rescue HTTParty::Error => e
      logger.error "Error connecting to Clockify: #{e.message}"
      raise
    end
  end
end

# app.rb
api_key_clockify = 'MDM3MzM4NDktYzRlYS00YzFlLWIxM2YtNTY2YWM1NzBhZGU3'
api_key_redmine = 'd3bc111102694a9eeb2c9a874bc6edb602de44ed'
email = 'raphael.costa@luizalabs.com'
workspace_name = 'Turia'
logger = Logger.new('application.log')

clockify_connector = ConnectorManager.get_clockify_connector(api_key_clockify, email, workspace_name, logger)
redmine_connector = ConnectorManager.get_redmine_connector(api_key_redmine, logger)
