require 'date'
require_relative 'manager'
require_relative '../support/error_handling'
require_relative '../connector/redmine_connector'
require_relative '../connector/clockify_connector'
require 'pry'
require 'set'


class DifferentialUpdater
  def initialize(redmine_connector, clockify_connector, logger)
    @redmine_connector = redmine_connector
    @clockify_connector = clockify_connector
    @logger = logger
    @workspace_name = "Turia"
  end

  def sync_time_entries
    @logger.info('Starting time entry synchronization from Clockify to Redmine...')

    begin
      # Obter todas as entradas de tempo do Clockify
      clockify_entries = @clockify_connector.get_clockify_time_entries(@workspace_name, start_date = nil, end_date = nil)
    # binding.pry
      # Obter todas as entradas de tempo existentes no Redmine de uma só vez
      existing_entries = Set.new(@redmine_connector.get_existing_time_entries.map { |entry| entry['issue_id'] })

      # Filtrar entradas que já existem
      new_entries = clockify_entries.reject { |entry| existing_entries.include?(entry['taskId']) }

      # Criar entradas no Redmine
      new_entries.each do |entry|
        issue_id = entry['taskId']
        hours = entry['timeInterval']['duration']
        comments = entry['description']
        spent_on = entry['timeInterval']['start']

        begin
          @redmine_connector.create_time_entry(issue_id, hours, comments, spent_on)
          @logger.info("Entrada de tempo criada no Redmine para a tarefa #{issue_id}.")
        rescue StandardError => e
          @logger.error("Erro ao criar entrada de tempo para a tarefa #{issue_id}: #{e.message}")
        end
      end

      @logger.info('Sincronização de entradas de tempo concluída.')
    rescue StandardError => e
      @logger.error("Erro durante a sincronização de entradas de tempo: #{e.message}")
      raise
    end
  end

  # def sync_issues
  #   issues_to_sync = filter_issues_to_sync
  #   create_clockify_tasks(issues_to_sync)
  #   update_redmine_with_clockify_entries
  # rescue StandardError => e
  #   @logger.error("Error during issues sync: #{e.message}")
  #   raise
  # end

  # Sincronização das issues do Redmine com o Clockify
  def sync_issues
    redmine_issues = @redmine_connector.get_issues_from_redmine

    redmine_issues.each do |issue|
      project_name = issue.dig('project', 'name')
      task_name = issue['subject']

      clockify_project = find_or_create_clockify_project(project_name)
      find_or_create_clockify_task(clockify_project, task_name)

      sync_time_entries_for_issue(issue['id'], clockify_project['id'], task_name)
    end
  rescue StandardError => e
    @logger.error("#{e.message}")
  end

  def find_or_create_clockify_project(project_name)
    clockify_project = @clockify_connector.get_project_by_name(project_name)
    return clockify_project if clockify_project

    @clockify_connector.create_project(project_name)
  end

  def find_or_create_clockify_task(clockify_project, task_name)
    clockify_task = @clockify_connector.get_task_by_name(clockify_project['id'], task_name)

    if clockify_task
      @logger.info("Task encontrada no Clockify")
    else
      @clockify_connector.create_task(clockify_project['id'], task_name)
    end
  end

  def sync_time_entries_for_issue(issue_id, clockify_project_id, task_name)

    @logger.info("Iniciando sincronização de entradas de tempo...")

    time_entries = @clockify_connector.get_clockify_time_entries(start_date = nil, end_date = nil)

    if time_entries
      time_entries.each do |entry|
        @redmine_connector.create_redmine_time_entry(entry)
      end
    else
      @logger.info("Entradas vieram vazias, nenhuma atualização será feita")
    end
  end


  def filter_issues_to_sync
    issues = @redmine_connector.get_issues_from_redmine
    existing_tasks = @clockify_connector.get_all_tasks
    # binding.pry

    @logger.info("Issues: #{issues.inspect}")
    @logger.info("Existing tasks: #{existing_tasks.inspect}")

    filtered_issues = issues.select { |issue| needs_sync?(issue, existing_tasks) }

    return filtered_issues

  rescue StandardError => e
    @logger.error("Error filtering issues to sync: #{e.message}")
    raise 'An error occurred while filtering issues to sync'
  end

  #     clockify_entries.each do |entry|
  #       next if time_entry_exists?(entry)

  #       issue_id = entry['taskId']
  #       hours = entry['timeInterval']['duration']
  #       comments = entry['description']
  #       spent_on = entry['timeInterval']['start']

  #       @redmine_connector.create_time_entry(issue_id, hours, comments, spent_on)
  #       @logger.info("Time entry created in Redmine for issue #{issue_id}.")
  #     end

  #     @logger.info('Time entry synchronization completed.')
  #   rescue StandardError => e
  #     @logger.error("Error during time entry synchronization: #{e.message}")
  #     raise
  #   end
  # end

  def time_entry_exists?(entry)
    response = HTTParty.get("#{base_url}/time_entries.json",
                            headers: { 'X-Redmine-API-Key' => api_key },
                            query: { issue_id: entry.issue_id, spent_on: entry.spent_on })
    entries = JSON.parse(response.body)['time_entries']
    entries.any? do |existing_entry|
      existing_entry['hours'] == entry.hours && existing_entry['comments'] == entry.description
    end
  end

  def update_redmine_with_clockify_entries
    clockify_entries = @clockify_connector.get_clockify_time_entries(workspace_id, start_date = nil, end_date = nil)
    clockify_entries.each do |entry|
      @redmine_connector.create_time_entry(issue_id, hours, comments, spent_on) unless time_entry_exists?(entry)
    end
  end

  def needs_sync?(issue, existing_tasks)
    task = existing_tasks.find { |task| task['name'] == issue['subject'] }
    task.nil? || issue['updated_on'] > task['timeInterval']['start']
  end

  def create_clockify_tasks(issues)
    issues.each do |issue|
      @clockify_connector.create_task(
        name: issue['subject'],
        description: issue['description']
      )
    end
  end
end
