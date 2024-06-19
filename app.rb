require_relative "conector/RedmineConnector"
require_relative "conector/ClockifyConnector"
require 'logger'
require 'date'

# Define o Logger
logger = Logger.new(STDOUT)
logger.datetime_format = '%Y-%m-%d %H:%M:%S'

#Informações do Clockify
api_key_clockify = 'MDM3MzM4NDktYzRlYS00YzFlLWIxM2YtNTY2YWM1NzBhZGU3'
email = 'raphaelcosta1.tech@gmail.com'

# Instancia o RedmineConnector::Client com o logger
api_key_redmine = '790d421e34f6ca3c9a453d19e1abdf3bc725218a'
connector = RedmineConnector::Client.new(api_key_clockify, api_key_redmine, email, logger)

logger.info('Starting Job')
response = connector.input_time_entry
logger.info('Finishing Job')
