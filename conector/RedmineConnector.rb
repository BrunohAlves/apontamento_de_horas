# redmine_connector.rb

require 'httparty'

module RedmineConnector
  class Client
    include HTTParty
    base_uri 'https://redmine-qa.autoseg.com/' # Substitua pela URL do Redmine de Produção

    def initialize(api_key)
      @api_key = api_key
    end

    # Método para apontar horas no Redmine
    def input_time_entry(issue_id, hours, comments, spent_on)
      endpoint = "/time_entries.json"
      options = {
        body: {
          time_entry: {
            project_id: get_project_id_by_issue(issue_id),
            issue_id: issue_id,
            hours: hours_to_decimal(hours),
            comments: comments,
            spent_on: spent_on
          }
        },
        query: { key: @api_key }
      }

      response = self.class.post(endpoint, options)

      if response.success?
        return response.parsed_response
      else
        raise "Erro ao inserir entrada de tempo: #{response.code}, #{response.parsed_response}"
      end
    end

    def hours_to_decimal(hours)
      partes = hours.split(':')
      hours = partes[0].to_i
      minutes = partes[1].to_i
      decimal = hours + (minutes.to_f / 60)
      return decimal
    end

    def decimal_to_hours(decimal)
      hours = decimal.to_i
      minutes = ((decimal - hours) * 60).to_i
      return "#{hours}:#{minutes}"
    end
    
    # Método para buscar o ID do Projeto a partir do ID do Ticket
    def get_project_id_by_issue(issue_id)
      issue_url = "/issues/#{issue_id}.json"
      options = { query: { key: @api_key } }

      response = self.class.get(issue_url, options)

      if response.success?
        issue_data = response.parsed_response['issue']
        project_id = issue_data['project']['id']
        return project_id
      else
        raise "Erro ao buscar a issue: #{response.code}, #{response.parsed_response}"
      end
    end

    # Método para importar as entradas do dia pra um arquivo .csv
    def import_time_entries_by_created_on(created_on)
      api_url = "#{self.class.base_uri}/time_entries.json"
      query_params = {
        key: @api_key,
        created_on: created_on
      }
  
      response = self.class.get(api_url, query: query_params)
  
      if response.code == 200
        time_entries = JSON.parse(response.body)['time_entries']
  
        if time_entries.empty?
          puts "Nenhuma time entry encontrada para a data de criação #{created_on}."
        else
          csv_file_path = "relatorios/time_entries_#{created_on}.csv"
  
          CSV.open(csv_file_path, 'w', headers: true) do |csv|
            csv << ['Issue ID', 'Hours', 'Comments', 'Created_at', 'User']
  
            time_entries.each do |entry|
              next if (Date.parse(entry['created_on']) - Date.today) != 0
              issue_id = entry['issue']['id']
              hours = decimal_to_hours(entry['hours'])
              comments = entry['comments']
              created_on = Date.parse(entry['created_on'])
              user_id = entry['user']['id']
  
              # Obter informações do usuário
              user_info = get_user_info(user_id)
              user_name = "#{user_info['user']['firstname']} #{user_info['user']['lastname']}"
  
              csv << [issue_id, hours, comments, created_on, user_name]
            end
          end
  
          puts "Time entries exportadas para #{csv_file_path}."
        end
      else
        puts "Erro na requisição: #{response.code}, #{response.body}"
      end
    end
  
    private
  
    def get_user_info(user_id)
      user_url = "#{self.class.base_uri}/users/#{user_id}.json"
      query_params = {
        key: @api_key
      }
  
      response = self.class.get(user_url, query: query_params)
      JSON.parse(response.body)
    end
  end
end