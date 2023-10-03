# frozen_string_literal: true
require_relative "conector/RedmineConnector"
require "csv"

begin
  api_key = 'your_token_api' # Substitua pela sua chave de API do Redmine
  connector = RedmineConnector::Client.new(api_key)

  relatorio_de_horas = CSV.table('csv/apontamento_de_horas.csv') # Retorna um Array de Arrays

  relatorio_de_horas.each do |horas|
    issue_id = horas[:issue_id]
    hours = horas[:hours]
    comments = horas[:comments]
    spent_on = horas[:spent_on]

    response = connector.input_time_entry(issue_id, hours, comments, spent_on)
    puts response
  end

  %x[cp csv/apontamento_de_horas_model.csv csv/apontamento_de_horas.csv]

  created_on = "#{Date.today}"
  connector.import_time_entries_by_created_on(created_on)
rescue StandardError => e
  puts "Erro ao importar time_entries: #{e.message}"
end