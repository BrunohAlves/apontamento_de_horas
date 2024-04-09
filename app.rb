require_relative "conector/RedmineConnector"
require_relative "conector/ClockifyConnector"
require 'logger'
require 'date'

# Define o Logger
logger = Logger.new(STDOUT)
logger.datetime_format = '%Y-%m-%d %H:%M:%S'

#Informações do Clockify
api_key_clockify = 'your_clockify_api_key'
email = 'your_email'

# Instancia o RedmineConnector::Client com o logger
api_key_redmine = 'your_redmine_api_key' 
connector = RedmineConnector::Client.new(api_key_clockify, api_key_redmine, email, logger)

logger.info('Starting Job')
response = connector.input_time_entry
logger.info('Finishing Job')