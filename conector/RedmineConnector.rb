require 'httparty'
require_relative 'ClockifyConnector'
require 'date'
require 'logger'

module RedmineConnector
  class Client
    include HTTParty
    base_uri 'https://sh.autoseg.com/' # Substitua pela URL do seu Redmine

    def initialize(api_key_clockify, api_key_redmine, email, logger)
      @api_key_clockify = api_key_clockify
      @api_key_redmine = api_key_redmine
      @email = email
      @logger = logger
    end

    def list_projects
      @logger.info('Listing projects...')
      response = self.class.get('/projects.json', query: { key: @api_key_redmine })

      if response.success?
        @logger.info('Projects listed successfully.')
        return response.parsed_response['projects']
      else
        @logger.error("Error listing projects: #{response.code}")
        raise "Erro na solicitação: #{response.code}"
      end
    end

    def input_time_entry
      clockify_connector = ClockifyConnector.new(@api_key_clockify, @email, @logger)
      time_entries = clockify_connector.list_time_entries
      @logger.info('Starting input time entries...')
      time_entries.each do |entry|
        created_at_datetime = DateTime.parse(entry[:created_at])
        today_datetime = DateTime.now
        next if created_at_datetime.to_date < today_datetime.to_date

        issue_id = entry[:tag]
        hours = entry[:interval]
        comments = entry[:description]
        spent_on = entry[:created_at]

        create_time_entry(issue_id, hours, comments, spent_on)
      end

      @logger.info('Time entries input complete.')
    end

    def create_time_entry(issue_id, hours, comments, spent_on)
      @logger.info('Creating time entry...')
      endpoint = "/time_entries.json"
      options = {
        body: {
          time_entry: {
            project_id: get_project_id_by_issue(issue_id),
            issue_id: issue_id,
            hours: hours,
            comments: comments,
            spent_on: spent_on
          }
        },
        query: { key: @api_key_redmine }
      }

      response = self.class.post(endpoint, options)

      if response.success?
        @logger.info('Time entry created successfully.')
        return response.parsed_response
      else
        @logger.error("Erro ao inserir entrada de tempo: #{response.code}, #{response.parsed_response}")
        raise "Erro ao inserir entrada de tempo: #{response.code}, #{response.parsed_response}"
      end
    end

    def get_project_id_by_issue(issue_id)
      @logger.info('Getting project ID by issue...')
      issue_url = "/issues/#{issue_id}.json"
      options = { query: { key: @api_key_redmine } }

      response = self.class.get(issue_url, options)

      if response.success?
        @logger.info('Project ID retrieved successfully.')
        issue_data = response.parsed_response['issue']
        project_id = issue_data['project']['id']
        return project_id
      else
        @logger.error("Erro ao buscar a issue: #{response.code}, #{response.parsed_response}")
        raise "Erro ao buscar a issue: #{response.code}, #{response.parsed_response}"
      end
    end

    def find_project_id_by_name(project_name)
      @logger.info('Finding project ID by name...')
      endpoint = "/projects.json"
      options = { query: { key: @api_key_redmine } }

      response = self.class.get(endpoint, options)

      if response.success?
        @logger.info('Project ID found successfully.')
        projects = response.parsed_response['projects']
        project = projects.find { |p| p['name'] == project_name }

        if project
          return project['id']
        else
          @logger.error("Projeto não encontrado com o nome: #{project_name}")
          raise "Projeto não encontrado com o nome: #{project_name}"
        end
      else
        @logger.error("Erro ao buscar projetos: #{response.code}, #{response.parsed_response}")
        raise "Erro ao buscar projetos: #{response.code}, #{response.parsed_response}"
      end
    end

    def import_time_entries_by_created_on(created_on)
      @logger.info('Importing time entries by created on...')
      api_url = "#{self.class.base_uri}/time_entries.json"
      query_params = {
        key: @api_key_redmine,
        created_on: created_on
      }

      response = self.class.get(api_url, query: query_params)

      if response.code == 200
        @logger.info('Time entries imported successfully.')
        time_entries = JSON.parse(response.body)['time_entries']

        if time_entries.empty?
          puts "Nenhuma time entry encontrada para a data de criação #{created_on}."
        else
          csv_file_path = "relatorios/time_entries_#{created_on}.csv"

          CSV.open(csv_file_path, 'w', headers: true) do |csv|
            csv << ['Issue ID', 'Horas', 'Comentários', 'Data de Criação']

            time_entries.each do |entry|
              issue_id = entry['issue']['id']
              hours = entry['hours']
              comments = entry['comments']
              created_on = entry['created_on']

              csv << [issue_id, hours, comments, created_on]
            end
          end

          puts "Time entries exportadas para #{csv_file_path}."
        end
      else
        @logger.error("Erro na requisição: #{response.code}, #{response.body}")
        puts "Erro na requisição: #{response.code}, #{response.body}"
      end
    end
  end
end
