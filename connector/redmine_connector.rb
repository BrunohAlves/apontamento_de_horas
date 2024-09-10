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
      @logger.info('Buscando tarefas de todos os projetos do Redmine para o período selecionado...')
      issues = []
      page = 1
      per_page = 100 # número de issues por página
      one_months_ago = Date.today.prev_month(1).strftime('%Y-%m-%d')
      retrieved_issues = []

      begin
        @logger.info("Obtendo página #{page}")
        with_retry do
          response = self.class.get('/issues.json',
                                    query: {
                                      key: @api_key_redmine,
                                      created_on: ">=#{one_months_ago}",
                                      offset: (page - 1) * per_page,
                                      limit: per_page
                                    },
                                    timeout: 200,
                                    open_timeout: 10)

          ErrorHandling.handle_error(response, @logger) unless response.success?
          retrieved_issues = response.parsed_response['issues'] || []
          break if retrieved_issues.empty?

          issues.concat(retrieved_issues)
          @logger.info("Obtidas #{retrieved_issues.size} novas tarefas do Redmine para o período escolhido")
          page += 1
        end
      end while retrieved_issues.size == per_page

      @logger.info("Total de tarefas obtidas: #{issues.size}")
      issues
    end

    def get_existing_time_entries
      @logger.info('Buscando entradas de tempo no Redmine...')

      # Definir a data de 3 dias atrás
      from_date = (Date.today - 3).to_s

      # Definir a data de hoje
      to_date = Date.today.to_s

      # Fazer a requisição com as datas
      response = self.class.get('/time_entries.json', query: {
        key: @api_key_redmine,
        from: from_date,
        to: to_date
      })
      # binding.pry

      if response.success?
        @logger.info('Entradas de tempo existentes no Redmine obtidas com sucesso.')
        response.parsed_response['time_entries'].map { |entry| entry['issue']['id'] }
      else
        @logger.error("Erro ao buscar entradas de tempo existentes: #{response.code}, #{response.parsed_response}")
        raise
      end
    end

    # Método para criar uma entrada de tempo em uma issue no Redmine
    def create_redmine_time_entry(issue_id, hours, comments, spent_on)
      @logger.info("Criando entrada de tempo no Redmine para a tarefa #{issue_id}...")
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
            @logger.info('Entrada de tempo criada com sucesso!')
            return response.parsed_response
          else
            @logger.error("Erro ao inserir entrada de tempo: #{response.code}, #{response.parsed_response}")
            raise
          end
        rescue StandardError => e
          @logger.error("Exceção ao criar entrada de tempo: #{e.message}")
          raise
        end
      end
    end

    def get_project_id_by_issue(issue_id)
      # Realizar a requisição à API do Redmine para obter a issue específica
      response = self.class.get("/issues/#{issue_id}.json", query: { key: @api_key_redmine })

      if response.success?
        # Extrair o ID do projeto a partir da issue retornada
        issue = response.parsed_response['issue']
        return issue['project']['id'] if issue.present?
      else
        @logger.error("Erro ao obter detalhes da issue #{issue_id}: #{response.code}, #{response.parsed_response}")
        raise StandardError, "Falha ao recuperar ID do projeto para a issue #{issue_id}"
      end
    end

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
