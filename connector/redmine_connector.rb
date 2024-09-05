require 'httparty'
require 'date'
require 'logger'
# require_relative '../lib/app'
require_relative '../support/error_handling'
require_relative '../lib/differential_updater'
require 'pry'

module RedmineConnector
  class Client
    extend ErrorHandling
    include HTTParty
    base_uri 'https://redmine-qa.autoseg.com'

    def initialize(api_key_redmine, logger)
      @api_key_redmine = api_key_redmine
      @logger = logger
    end

    def get_issues_from_redmine
      @logger.info('Getting issues for all projects from Redmine...')
      issues = []
      page = 1
      per_page = 100 # número de issues por página, conforme necessário
      twenty_months_ago = Date.today.prev_month(20).strftime('%Y-%m-%d')
      retrieved_issues = []

      loop do
        @logger.info("Fetching page #{page}")

        with_retry do
          response = self.class.get('/issues.json',
                                    query: {
                                      key: @api_key_redmine,
                                      created_on: ">=#{twenty_months_ago}",
                                      offset: (page - 1) * per_page,
                                      limit: per_page
                                    },
                                    timeout: 200,
                                    open_timeout: 10)

          ErrorHandling.handle_error(response, @logger) unless response.success?
          parsed_response = response.parsed_response

          retrieved_issues = parsed_response['issues'] || []

          break if retrieved_issues.empty?

          issues.concat(retrieved_issues)
          @logger.info("Retrieved #{retrieved_issues.size} issues")
          page += 1
        end

        break if retrieved_issues.size < per_page
      end

      @logger.info("Total issues retrieved: #{issues.size}")
      issues
    end


    def get_existing_time_entries
      @logger.info('Buscando entradas de tempo existentes no Redmine...')
      response = self.class.get('/time_entries.json', query: { key: @api_key_redmine })

      if response.success?
        @logger.info('Entradas de tempo existentes obtidas com sucesso.')
        response.parsed_response.map { |entry| entry['issue_id'] } # ou o que for apropriado
      else
        @logger.error("Erro ao buscar entradas de tempo existentes: #{response.code}, #{response.parsed_response}")
        raise "Erro ao buscar entradas de tempo existentes: #{response.code}, #{response.parsed_response}"
      end
    end



    # Método para criar uma entrada de tempo em uma issue no Redmine
        # def create_time_entry(issue_id, hours, comments, spent_on)

    def create_time_entry(issue_id, hours, comments, spent_on)
      @logger.info("Creating time entry in Redmine for issue #{issue_id}...")
      endpoint = "/time_entries.json"
      request_options = {
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

      with_retry do
        begin
          response = self.class.post(endpoint, request_options)
          if response.success?
            @logger.info('Time entry created successfully.')
            return response.parsed_response
          else
            @logger.error("Erro ao inserir entrada de tempo: #{response.code}, #{response.parsed_response}")
            raise "Erro ao inserir entrada de tempo: #{response.code}, #{response.parsed_response}"
          end
        rescue StandardError => e
          @logger.error("Exceção ao criar entrada de tempo: #{e.message}")
          raise
        end
      end
    end

    # def create_redmine_time_entry(entry)
    #   response = HTTParty.post("#{base_url}/time_entries.json",
    #                            headers: { 'X-Redmine-API-Key' => api_key },
    #                            body: {
    #                              time_entry: {
    #                                issue_id: entry.issue_id,
    #                                hours: entry.hours,
    #                                spent_on: entry.spent_on,
    #                                comments: entry.description
    #                              }
    #                            }.to_json)
    #   ErrorHandling.handle_error(response, @logger) unless response.success?
    # end

    # Método para tentativas de repetição de requisições
    def with_retry(max_attempts = 3)
      attempts = 0
      begin
        attempts += 1
        yield
      rescue StandardError => e
        raise e unless attempts < max_attempts

        puts "Tentativa #{attempts} falhou, tentando novamente..."
        retry
      end
    end
  end
end
