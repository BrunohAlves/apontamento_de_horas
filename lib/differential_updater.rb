require 'date'
require_relative 'manager'
require_relative '../support/error_handling'
require_relative '../connector/redmine_connector'
require_relative '../connector/clockify_connector'
require 'pry'
require 'active_support/core_ext/object/blank'
require 'set'

class DifferentialUpdater
  def initialize(redmine_connector, clockify_connector, logger)
    @redmine_connector = redmine_connector
    @clockify_connector = clockify_connector
    @logger = logger
    @workspace_name = "Turia"
  end

  # Update de Projetos e tarefas do Clockify pelo Redmine, não são pegas novas entradas de tempo do Redmine.
  def update_clockify_projects_and_tasks
    redmine_issues = @redmine_connector.get_issues_from_redmine

    redmine_issues.each do |issue|
      project_name = issue.dig('project', 'name')
      task_name = issue['subject']

      clockify_project = find_or_create_clockify_project(project_name)

      # Certifique-se de que clockify_project tem o ID correto
      if clockify_project
        find_or_create_clockify_task(clockify_project, task_name)
      else
        @logger.error("Erro ao buscar o projeto #{project_name} no Clockify")
      end
      # find_or_create_clockify_task(clockify_project, task_name)
      # sync_time_entries_for_issue(issue['id'], clockify_project['id'], task_name)
    end
  rescue StandardError => e
    @logger.error("#{e.message}")
  end

  def update_redmine_time_entries(days_ago)
    @logger.info('Verificando se existem novas entradas de tempo no Clockify...')
    begin
      # Obter todas as entradas de tempo do Clockify
      clockify_entries = @clockify_connector.get_clockify_time_entries(7)

      if clockify_entries.present?
        # Obter todas as entradas de tempo existentes no Redmine de uma só vez
        existing_redmine_entries = @redmine_connector.get_existing_time_entries.map { |entry| entry['issue_id'].to_s.downcase }.to_set

        # Obter entradas novas, filtrando as que já existem
        new_entries = clockify_entries.reject do |entry|
          existing_redmine_entries.include?(entry['taskId'].to_s.downcase)
        end

        # Criar novas entradas no Redmine
        new_entries.each do |entry|
          issue_id = entry['taskId'].to_s.downcase
          hours = entry['timeInterval']['duration']
          comments = entry['description']
          spent_on = Time.parse(entry['timeInterval']['start']).strftime("%Y-%m-%d %H:%M:%S")

          begin
            @redmine_connector.create_redmine_time_entry(issue_id, hours, comments, spent_on)
            @logger.info("Entrada de tempo criada no Redmine para a tarefa #{issue_id}.")
          rescue StandardError => e
            @logger.error("Erro ao criar entrada de tempo para a tarefa #{issue_id}: #{e.message}")
          end
        end
        @logger.info('Atualização de entradas de tempo concluída.')
      else
        @logger.info('Não existem novas entradas no Clockify, encerrando fluxo.')
      end
    rescue StandardError => e
      @logger.error("Erro durante a atualização de entradas de tempo no Redmine: #{e.message}")
      puts "Erro ao acessar um elemento de clockify_entries: #{e.message}"
      puts "clockify_entries: #{clockify_entries.inspect}"
      raise
    end
  end

  # def update_redmine_time_entries(days_ago)
  #   @logger.info('Verificando se existem novas entradas de tempo no Clockify...')

  #   begin
  #     # Obter todas as entradas de tempo do Clockify
  #     clockify_entries = @clockify_connector.get_clockify_time_entries(7)
  #     binding.pry
  #     if clockify_entries.present?
  #       # Obter todas as entradas de tempo existentes no Redmine de uma só vez
  #       existing_redmine_entries = Set.new(@redmine_connector.get_existing_time_entries.map { |entry| entry['issue_id'].to_s.downcase })
  #       # binding.pry

  #       # Obter entradas novas, filtrando as que já existem
  #       new_entries = clockify_entries.reject { |entry| existing_redmine_entries.include?(entry['taskId'].to_s.downcase) }

  #       # Criar novas entradas no Redmine
  #       new_entries.each do |entry|
  #         issue_id = entry['taskId']
  #         hours = entry['timeInterval']['duration']
  #         comments = entry['description']
  #         spent_on = Time.parse(entry['timeInterval']['start']).in_time_zone('America/Sao_Paulo').strftime("%Y-%m-%d %H:%M:%S")

  #         begin
  #           @redmine_connector.create_redmine_time_entry(issue_id, hours, comments, spent_on)
  #           @logger.info("Entrada de tempo criada no Redmine para a tarefa #{issue_id}.")
  #         rescue StandardError => e
  #           @logger.error("Erro ao criar entrada de tempo para a tarefa #{issue_id}: #{e.message}")
  #         end
  #       end

  #       @logger.info('Atualização de entradas de tempo concluída.')
  #     else
  #       @logger.info('Não existem novas entradas no Clockify, encerando fluxo')
  #     end
  #   rescue StandardError => e
  #     @logger.error("Erro durante a atualização de entradas de tempo no Redmine: #{e.message}")
  #     puts "Erro ao acessar um elemento de clockify_entries: #{e.message}"
  #     puts "clockify_entries: #{clockify_entries.inspect}"
  #     raise
  #   end
  # end
  def find_or_create_clockify_project(project_name)
    begin
      clockify_project = @clockify_connector.get_project_by_name(project_name)

      if clockify_project.present?
        @logger.info("Projeto '#{project_name}' encontrado no Clockify.")
        return clockify_project
      else
        @logger.info("Projeto '#{project_name}' não encontrado no Clockify. Criando novo projeto...")
        return @clockify_connector.create_project(project_name)
      end
    rescue ClockifyApiError => e
      @logger.error("Erro ao buscar ou criar projeto no Clockify: #{e.message}")
      raise
    rescue StandardError => e
      @logger.error("Erro inesperado ao buscar ou criar projeto no Clockify: #{e.message}")
      raise
    end
  end
  # def find_or_create_clockify_project(project_name)
  #   begin
  #     clockify_project = @clockify_connector.get_project_by_name(project_name)
  #     # binding.pry

  #     if clockify_project.present?
  #       @logger.info("Não é necessária a criação do projeto.")
  #     else
  #       @clockify_connector.create_project(project_name)
  #     end

  #   rescue ClockifyApiError => e
  #     @logger.error("Erro ao buscar ou criar projeto no Clockify: #{e.message}")
  #     raise
  #   rescue StandardError => e
  #     @logger.error("Erro inesperado ao buscar ou criar projeto no Clockify: #{e.message}")
  #     raise
  #   end
  # end

  def find_or_create_clockify_task(clockify_project, task_name)
    # Busca todas as tarefas e compara localmente
    clockify_task = @clockify_connector.get_tasks_for_project(clockify_project['id']).find do |task|
      task['name'].casecmp(task_name).zero?
    end

    if clockify_task.present?
      @logger.info("Tarefa '#{task_name}' já existe no projeto #{clockify_project['name']}.")
    else
      @logger.info("Tarefa '#{task_name}' não encontrada. Criando nova tarefa no Clockify...")
      @clockify_connector.create_task(clockify_project['id'], task_name)
    end
  end


  def get_tasks_for_project(project_id)
    @logger.info("Buscando todas as tarefas do projeto ID '#{project_id}' no Clockify...")

    response = self.class.get(
      "/workspaces/#{@workspace_id}/projects/#{project_id}/tasks",
      headers: headers
    )

    if response.success?
      tasks = response.parsed_response
      @logger.info("Tarefas obtidas com sucesso para o projeto ID '#{project_id}'.")
      return tasks
    else
      ErrorHandling.handle_error(response, @logger)
    end
  rescue StandardError => e
    @logger.error("Erro ao buscar tarefas no Clockify: #{e.message}")
    raise
  end



  # def find_or_create_clockify_task(clockify_project, task_name)
  #   clockify_task = @clockify_connector.get_task_by_name(clockify_project['id'], task_name)

  #   if clockify_task.present?
  #     @logger.info("Não é necessária a criação da tarefa.")
  #   else
  #     @clockify_connector.create_task(clockify_project['id'], task_name)
  #   end
  # end
end
  # def filter_issues_to_sync
  #   issues = @redmine_connector.get_issues_from_redmine
  #   existing_tasks = @clockify_connector.get_all_tasks
  #   # binding.pry

  #   @logger.info("Issues: #{issues.inspect}")
  #   @logger.info("Existing tasks: #{existing_tasks.inspect}")

  #   filtered_issues = issues.select { |issue| needs_sync?(issue, existing_tasks) }

  #   return filtered_issues

  # rescue StandardError => e
  #   @logger.error("Error filtering issues to sync: #{e.message}")
  #   raise 'An error occurred while filtering issues to sync'
  # end

  # def time_entry_exists?(entry)
  #   response = HTTParty.get("#{base_url}/time_entries.json",
  #                           headers: { 'X-Redmine-API-Key' => api_key },
  #                           query: { issue_id: entry.issue_id, spent_on: entry.spent_on })
  #   entries = JSON.parse(response.body)['time_entries']
  #   entries.any? do |existing_entry|
  #     existing_entry['hours'] == entry.hours && existing_entry['comments'] == entry.description
  #   end
  # end

  # def update_redmine_with_clockify_entries
  #   clockify_entries = @clockify_connector.get_clockify_time_entries(workspace_id, start_date = nil, end_date = nil)
  #   clockify_entries.each do |entry|
  #     @redmine_connector.create_time_entry(issue_id, hours, comments, spent_on) unless time_entry_exists?(entry)
  #   end
  # end

  # def needs_sync?(issue, existing_tasks)
  #   task = existing_tasks.find { |task| task['name'] == issue['subject'] }
  #   task.nil? || issue['updated_on'] > task['timeInterval']['start']
  # end

  # def create_clockify_tasks(issues)
  #   issues.each do |issue|
  #     @clockify_connector.create_task(
  #       name: issue['subject'],
  #       description: issue['description']
  #     )
  #   end
  # end
# end
