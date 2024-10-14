require 'httparty'
require 'date'
require 'logger'
require_relative '../support/error_handling'
require_relative '../lib/differential_updater'

module RedmineConnector
  class Client
    extend ErrorHandling
    include HTTParty
    base_uri 'https://sh.autoseg.com'

    def initialize(api_key_redmine, clockify_connector, logger)
      @api_key_redmine = api_key_redmine
      @clockify_connector = clockify_connector
      @logger = logger
      @logger.info("RedmineConnector inicializado no construtor: #{@api_key_redmine.inspect}")
    end

    def get_issues_from_redmine
      @logger.info('Buscando tarefas de todos os projetos do Redmine...')
      issues = []
      invalid_tasks = []  # Armazenar tarefas sem issue_id
      page = 1
      per_page = 10
      data_corte = '2024-09-15'
      retrieved_issues = []

      begin
        @logger.info("Obtendo página #{page}")
        ErrorHandling.with_retry(3, @logger) do
          response = self.class.get('/issues.json',
                                    query: {
                                      key: @api_key_redmine,
                                      created_on: ">=#{data_corte}",
                                      offset: (page - 1) * per_page,
                                      limit: per_page
                                    },
                                    timeout: 300,
                                    open_timeout: 60)

          if response.success?
            retrieved_issues = response.parsed_response['issues'] || []
            break if retrieved_issues.empty?

            retrieved_issues.each do |issue|
              issue_id = issue['id']
              if issue_id.nil?
                invalid_tasks << issue['subject']
              else
                issues << issue
              end
            end

            @logger.info("Obtidas #{retrieved_issues.size} novas tarefas do Redmine para o período escolhido")
            page += 1
          else
            ErrorHandling.handle_error(response, @logger)
          end
        end
      rescue StandardError => e
        ErrorHandling.log_exception(e, @logger)
        raise
      end while retrieved_issues.size == per_page

      @logger.info("Total de tarefas válidas obtidas: #{issues.size}")
      @logger.info("Tarefas sem issue_id: #{invalid_tasks.join(', ')}") unless invalid_tasks.empty?
      @logger.info("Total de tarefas sem issue_id (invalid_tasks): #{invalid_tasks.size}")

      issues
    end

    # Busca entradas de tempo no Redmine a partir da data corte
    def get_existing_time_entries
      @logger.info('Buscando entradas de tempo no Redmine...')

      from_date = '2024-10-14'
      to_date = Date.today.to_s

      response = self.class.get('/time_entries.json', query: {
        key: @api_key_redmine,
        from: from_date,
        to: to_date
      }, timeout: 600, open_timeout: 60)

      if response.success?
        if response['time_entries'].empty?
          @logger.info('Conforme esperado, nenhuma nova entrada de tempo encontrada no Redmine para o período especificado.')
          []
        else
          @logger.info('Entradas de tempo existentes no Redmine obtidas com sucesso.')
          response.parsed_response['time_entries'].map do |entry|
            {
              issue_id: entry['issue']['id'],
              spent_on: entry['spent_on'],
              hours: entry['hours'],
              comments: entry['comments']
            }
          end
        end
      else
        @logger.error("Erro ao buscar entradas de tempo existentes: #{response.code} - #{response.parsed_response}")
        raise "Erro ao buscar entradas de tempo existentes: #{response.code} - #{response.parsed_response}"
      end
    end

    def find_issue_by_task_name(task_name)
      # Remove o issue_id do nome da tarefa, se houver
      task_name_without_issue_id = task_name.gsub(/^\[\d+\]\s*/, '')

      @logger.info("Iniciando busca no Redmine para a tarefa '#{task_name_without_issue_id}'.")

      begin
        response = self.class.get("/issues.json", query: { key: @api_key_redmine, subject: task_name_without_issue_id })

        if response.success?
          issues = response.parsed_response['issues']

          if issues.empty?
            @logger.warn("Nenhuma issue encontrada no Redmine com o nome da tarefa '#{task_name_without_issue_id}'.")
            return nil
          end

          # Tenta encontrar a issue correta pelo nome da tarefa
          issue = issues.find { |issue| issue['subject'] == task_name_without_issue_id }

          if issue
            @logger.info("Issue encontrada no Redmine: ID #{issue['id']}, Nome: '#{issue['subject']}'")
            return issue
          else
            @logger.warn("Nenhuma issue correspondente encontrada no Redmine para a tarefa '#{task_name_without_issue_id}'.")
            return nil
          end
        else
          @logger.error("Erro ao buscar issue no Redmine para a tarefa '#{task_name_without_issue_id}': #{response.code} - #{response.message}")
          return nil
        end

      rescue StandardError => e
        @logger.error("Exceção ao buscar issue no Redmine: #{e.message}")
        @logger.error(e.backtrace.join("\n")) if e.backtrace
        return nil
      end
    end

    def create_redmine_time_entry(entry)
      # Obtenha o nome da tarefa diretamente pelo taskId associado à entrada de tempo
      task_name = @clockify_connector.get_task_name_from_clockify(entry['taskId'], entry['projectId'])

      @logger.info("Nome da tarefa obtida do Clockify: #{task_name}")

      # Extraia o issue_id do nome da tarefa no formato [id] nome_da_tarefa
      issue_id = DifferentialUpdater.extract_issue_id_from_task_name(task_name)
      if issue_id.nil?
        @logger.error("Erro: Nenhum issue_id encontrado para a tarefa '#{task_name}'.")
        invalid_tasks ||= []
        invalid_tasks << task_name
        return
      end

      @logger.info("Issue ID extraído da tarefa: #{issue_id}")

      clean_task_name = task_name.sub(/^\[\d+\]\s*/, '')
      @logger.info("Nome da tarefa sem o issue_id: #{clean_task_name}")

      # Busca a issue no Redmine pelo nome da tarefa sem o issue_id
      issue = find_issue_by_task_name(clean_task_name)
      if issue.nil?
        @logger.error("Erro: Issue não encontrada no Redmine para a tarefa '#{clean_task_name}'.")
        invalid_tasks ||= []
        invalid_tasks << task_name
        return
      end

      # Get project_id
      project_id = issue.dig('project', 'id')
      unless project_id
        @logger.error("Erro: project_id não encontrado na issue.")
        return
      end

      @logger.info("Projeto ID obtido da issue: #{project_id}")

      # Validate project and issue
      unless project_exists?(project_id) && issue_exists?(issue_id)
        @logger.error("Projeto ou Issue não existem no Redmine. Não é possível criar a entrada de tempo.")
        return
      end

      # Calculate hours
      hours = calculate_hours(entry)
      if hours <= 0
        @logger.error("Erro: Horas calculadas são inválidas (<= 0).")
        return
      end

      @logger.info("Horas calculadas: #{hours}")

      # Get spent_on date
      spent_on = Time.parse(entry['timeInterval']['start']).strftime('%Y-%m-%d')
      @logger.info("Data da entrada de tempo (spent_on): #{spent_on}")

      # Prepare redmine_entry
      redmine_entry = {
        "time_entry" => {
          "project_id" => project_id,
          "issue_id" => issue_id,
          "spent_on" => spent_on,
          "hours" => hours,
          "comments" => clean_task_name
        }
      }

      @logger.info("Enviando entrada de tempo para o Redmine: #{redmine_entry.to_json}")

      # Make API call
      response = self.class.post(
        "/time_entries.json",
        query: { key: @api_key_redmine },
        headers: { 'Content-Type' => 'application/json' },
        body: redmine_entry.to_json
      )

      if response.success?
        @logger.info("Entrada de tempo criada com sucesso no Redmine para a tarefa '#{task_name}'.")
      else
        @logger.error("Erro ao inserir entrada de tempo no Redmine: #{response.code}, Detalhes: #{response.body}")
      end
    end

    def validate_issue_id(issue_id)
      issue_data = fetch_issue_data(issue_id)
      !!issue_data
    end

    def get_project_id_by_issue(issue_id)
      issue_data = fetch_issue_data(issue_id)
      issue_data ? issue_data['project']['id'] : nil
    end

    def project_exists?(project_id)
      response = self.class.get("/projects/#{project_id}.json", query: { key: @api_key_redmine })

      if response.success?
        @logger.info("Projeto ID #{project_id} existe no Redmine.")
        true
      else
        @logger.error("Projeto ID #{project_id} não encontrado no Redmine: #{response.code}, #{response.body}")
        false
      end
    end

    def issue_exists?(issue_id)
      response = self.class.get("/issues/#{issue_id}.json", query: { key: @api_key_redmine })

      if response.success?
        @logger.info("Issue ID #{issue_id} existe no Redmine.")
        true
      else
        @logger.error("Issue ID #{issue_id} não encontrado no Redmine: #{response.code}, #{response.body}")
        false
      end
    end

    private

    def fetch_issue_data(issue_id)
      response = self.class.get("/issues/#{issue_id}.json", query: { key: @api_key_redmine })

      if response.success?
        response.parsed_response['issue']
      else
        @logger.error("Erro ao obter detalhes da issue #{issue_id}: #{response.code}, #{response.parsed_response}")
        nil
      end
    end

    def validate_project_in_redmine(issue_id)
      response = self.class.get("/issues/#{issue_id}.json", query: { key: @api_key_redmine })

      if response.success?
        @logger.info("Issue ID #{issue_id} validado com sucesso no Redmine.")
        return true
      else
        @logger.error("Erro ao validar o Issue ID #{issue_id} no Redmine: #{response.code} - #{response.parsed_response}")
        return false
      end
    end

    def validate_project_id(project_id)
      response = self.class.get("/projects/#{project_id}.json", query: { key: @api_key_redmine })

      if response.success?
        @logger.info("Projeto ID #{project_id} validado com sucesso no Redmine.")
        true
      else
        @logger.error("Erro ao validar o Projeto ID #{project_id} no Redmine: #{response.code} - #{response.parsed_response}")
        false
      end
    end

    def calculate_hours(entry)
      duration_str = entry['timeInterval']['duration']
      match_data = /PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?/.match(duration_str)

      if match_data
        hours = match_data[1] ? match_data[1].to_i : 0
        minutes = match_data[2] ? match_data[2].to_i : 0
        seconds = match_data[3] ? match_data[3].to_i : 0

        total_hours = hours + (minutes / 60.0) + (seconds / 3600.0)
        @logger.info("Duração calculada: #{total_hours} horas")
        total_hours
      else
        @logger.error("Formato de duração inválido: #{duration_str}")
        0.0
      end
    end

    def ensure_clockify_connector_initialized
      raise "ClockifyConnector não está inicializado" if @clockify_connector.nil?
    end

    # def ensure_redmine_connector_initialized
    #   if @redmine_connector.nil?
    #     @logger.error("RedmineConnector não está inicializado")
    #     raise "RedmineConnector não inicializado"
    #   else
    #     @logger.info("RedmineConnector inicializado com sucesso")
    #   end
    # end
  end
end
