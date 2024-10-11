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
    @workspace_name = 'Turia'
    @workspace_id = '63fe21bea094e40fbee3b92e'
    @verified_tasks = {} # Cache para armazenar tarefas verificadas

    # @logger.info("RedmineConnector inicializado no DifferentialUpdater: #{@redmine_connector.inspect}")
  end

  def create_or_update_clockify_task(redmine_issue, clockify_project)
    issue_id = redmine_issue['id']
    task_name = "[#{issue_id}] #{redmine_issue['subject']}" # Certifica que o issue_id está no nome

    return if task_already_verified?(task_name) # Verifica o cache antes de continuar

    existing_task = find_task_in_clockify(task_name, clockify_project['id'])

    if redmine_issue['subject'].casecmp('Bloqueio').zero?
      @logger.info("Task 'Bloqueio' encontrada, nenhuma verificação adicional será realizada.")
      existing_task = find_task_in_clockify(task_name, clockify_project['id'])

      if existing_task.nil?
        @logger.info("Criando task 'Bloqueio' no Clockify para o projeto #{clockify_project['name']}")
        @clockify_connector.create_task(clockify_project['id'], task_name)
      end
      return
    end

    @logger.info("Verificando tarefa no Clockify: #{task_name} para o projeto #{clockify_project['name']}")
    existing_task = find_task_in_clockify(task_name, clockify_project['id'])

    if existing_task
      if task_needs_update?(existing_task, redmine_issue)
        @logger.info("Atualizando tarefa no Clockify: #{task_name}")
        task_data = { "name" => task_name, "status" => redmine_issue['status'], "billable" => true }
        @clockify_connector.update_task(clockify_project['id'], existing_task['id'], task_data)
      else
        @logger.info("Nenhuma atualização necessária para a tarefa #{task_name}")
      end
    else
      @logger.info("Criando nova tarefa no Clockify: #{task_name}")
      @clockify_connector.create_task(clockify_project['id'], task_name)
    end
  end

  def self.extract_issue_id_from_task_name(task_name)
    # Remove o nome do projeto seguido de dois pontos, se houver
    task_name = task_name.sub(/^.*?:\s*/, '')

    # Garante que busque o issue_id no formato [id] no início da string
    match = task_name.match(/^\[(\d+)\]\s+/)

    if match
      issue_id = match[1]
      # Adiciona o log para verificar se o issue_id foi corretamente extraído
      puts "Extraindo issue_id da tarefa '#{task_name}': #{issue_id}"
      issue_id
    else
      # Adiciona um log para casos onde o issue_id não foi encontrado
      puts "Nenhum issue_id encontrado na tarefa '#{task_name}'"
      nil
    end
  end

  def update_clockify_projects_and_tasks
    # @logger.info("RedmineConnector dentro de update_clockify_projects_and_tasks: #{@redmine_connector.inspect}")
    redmine_issues = @redmine_connector.get_issues_from_redmine

    redmine_issues.each do |issue|
      project_name = issue.dig('project', 'name')
      task_name = issue['subject']
      issue_id = issue['id']

      clockify_project = find_or_create_clockify_project(project_name)

      if clockify_project
        process_task(clockify_project, task_name, issue_id, issue)
      else
        @logger.error("Erro ao buscar o projeto #{project_name} no Clockify")
      end
    end
  rescue StandardError => e
    log_error(e)
  end

  def update_clockify_task_names_with_issue_id
    projects = @clockify_connector.get_all_projects(@workspace_id)

    projects.each do |project|
      project_id = project['id']
      tasks = @clockify_connector.get_tasks_for_project(project_id)

      tasks.each do |task|
        task_name = task['name']

        # Verifica se o issue_id já está no nome da tarefa
        if task_name.match(/^\[\d+\]/)
          @logger.info("Issue ID já presente no nome da tarefa '#{task_name}', nenhuma atualização necessária.")
          next
        end

        issue_id = get_issue_id_from_redmine(task_name)

        if issue_id
          updated_task_name = "[#{issue_id}] #{task_name}"

          unless task_name.match(/^\[#{issue_id}\]/)
            task_data = { "name" => updated_task_name }
            @clockify_connector.update_task(project_id, task['id'], task_data)
            @logger.info("Tarefa '#{task_name}' atualizada para '#{updated_task_name}' no projeto '#{project['name']}'")
          else
            @logger.info("Tarefa '#{task_name}' já contém o issue_id, nenhuma atualização necessária.")
          end
        else
          @logger.warn("Issue ID não encontrado para a tarefa '#{task_name}' no projeto '#{project['name']}'")
        end
      end
    end
  end

  # Método auxiliar para buscar issue_id no Redmine
  def get_issue_id_from_redmine(task_name)
    issue = @redmine_connector.find_issue_by_task_name(task_name)
    issue ? issue['id'] : nil
  end

  def update_redmine_time_entries(user_id)
    @logger.info("Verificando se existem novas entradas de tempo no Clockify...")

    invalid_tasks = []

    ensure_clockify_connector_initialized

    # Obter entradas de tempo do Clockify
    clockify_entries = @clockify_connector.get_clockify_time_entries_for_user(user_id)

    unless clockify_entries.empty?
      process_time_entries(clockify_entries, invalid_tasks)
    else
      @logger.info("Nenhuma nova entrada de tempo encontrada no Clockify.")
    end

    # Verificar e logar tarefas inválidas no final do processamento
    if invalid_tasks && invalid_tasks.any?
      @logger.warn("As seguintes tarefas não têm issue_id no nome e foram ignoradas:")
      invalid_tasks.each do |task|
        @logger.warn("Tarefa: #{task}")
      end
    end
  end

  def process_task(clockify_project, task_name, issue_id, redmine_issue)
    ensure_clockify_connector_initialized

    # Adiciona o issue_id ao nome da tarefa, verificando se ele já está presente
    unless task_name.match(/^\[#{issue_id}\]/)
      task_name = "[#{issue_id}] #{task_name}"
    end

    clockify_task = find_task_in_project(clockify_project, task_name)

    if clockify_task
      @logger.info("    Tarefa '#{task_name}' já existe no projeto #{clockify_project['name']}.")
    else
      @clockify_connector.create_task(clockify_project['id'], task_name, redmine_issue)
    end
  end

  def find_or_create_clockify_project(project_name)
    ensure_clockify_connector_initialized

    clockify_project = @clockify_connector.get_project_by_name(project_name)

    if clockify_project
      log_and_return_project(clockify_project, project_name)
    else
      @logger.info("Projeto '#{project_name}' não encontrado no Clockify. Criando novo projeto.")
      clockify_project = @clockify_connector.create_project(project_name) # Aqui chamamos o método novo
      log_and_return_project(clockify_project, project_name)
    end
  end

  def find_task_in_project(clockify_project, formatted_task_name)
    @clockify_connector.get_tasks_for_project(clockify_project['id']).find do |task|
      task_name_without_issue_id = task['name'].gsub(/^\[\d+\]/, '').strip
      formatted_task_name_without_issue_id = formatted_task_name.gsub(/^\[\d+\]/, '').strip
      task_name_without_issue_id.casecmp(formatted_task_name_without_issue_id).zero?
    end
  end

  def task_already_verified?(task_name)
    # Limpeza de tarefas cacheadas com mais de 1 hora (TTL)
    @verified_tasks.reject! { |_, timestamp| Time.now - timestamp > 3600 }

    return true if @verified_tasks[task_name]
    @verified_tasks[task_name] = Time.now
    false
  end

  def format_task_name_with_issue_id(task_name, issue_id)
    "[#{issue_id}] #{task_name}"
  end

  def process_time_entries(clockify_entries, invalid_tasks)
    existing_redmine_entries = @redmine_connector.get_existing_time_entries.each_with_object(Set.new) do |entry, set|
      set.add(entry['issue_id'].to_s.downcase)
    end

    clockify_entries.each do |entry|
      if entry['taskId']
        # Pega o nome da task associada ao taskId
        task = @clockify_connector.get_task(entry['projectId'], entry['taskId'])
        task_name = task ? task['name'] : 'Tarefa não encontrada'

        @logger.info("Entrada de tempo nova para a tarefa: #{task_name} no projeto #{entry['projectId']}")

        # Extrai o issue_id da task_name, se presente
        issue_id = DifferentialUpdater.extract_issue_id_from_task_name(task_name)

        # Remove o issue_id do nome da tarefa antes de buscar no Redmine
        task_name_without_issue_id = task_name.gsub(/^\[\d+\]\s*/, '') # Remove o prefixo do issue_id

        # Corrige buscando o issue_id no Redmine
        issue = @redmine_connector.find_issue_by_task_name(task_name_without_issue_id)

        if issue.nil?
          @logger.warn("Issue não encontrada no Redmine para a tarefa '#{task_name_without_issue_id}'.")
          invalid_tasks << task_name
          next
        else
          issue_id = issue['id']
        end

        if issue_id.nil?
          @logger.warn("Issue ID não encontrado para a tarefa '#{task_name}' no Redmine.")
          invalid_tasks << task_name
          next
        end

        # Verifica se a entrada de tempo já existe no Redmine
        if !existing_redmine_entries.include?(issue_id.to_s.downcase)
          @logger.info("Criando nova entrada de tempo para a tarefa: #{task_name} no Redmine.")

          # @logger.info("Chamando create_redmine_time_entry com RedmineConnector: #{@redmine_connector.inspect}")

          @redmine_connector.create_redmine_time_entry(entry)
        else
          @logger.info("Entrada de tempo já existente no Redmine para a tarefa #{task_name}.")
        end
      else
        @logger.warn("Entrada de tempo sem 'taskId' encontrada. Descrição: #{entry['description']}")
        invalid_tasks << entry['description']
      end
    end
  end

  def sync_redmine_issues_to_clockify
    @logger.info('Sincronizando tarefas do Redmine para o Clockify...')

    # Buscar todas as issues do Redmine
    redmine_issues = @redmine_connector.get_issues_from_redmine(self)

    redmine_issues.each do |issue|
      project_name = issue['project']['name']

      clockify_project = @clockify_connector.find_project_by_name(project_name)

      if clockify_project.nil?
        @logger.info("Projeto '#{project_name}' não encontrado no Clockify, criando projeto.")
        clockify_project = @clockify_connector.create_project(project_name)

        if clockify_project
          @logger.info("Projeto '#{project_name}' criado com sucesso no Clockify.")
        else
          @logger.error("Erro ao criar o projeto '#{project_name}' no Clockify. A tarefa '#{issue['subject']}' não será criada.")
          next
        end
      end

      create_or_update_clockify_task(issue, clockify_project) # Passando o projeto corretamente
    end

    @logger.info('Sincronização de tarefas do Redmine para o Clockify concluída.')
  end

  def log_and_return_project(clockify_project, project_name)
    project_id = clockify_project['id']
    @logger.info("  Projeto '#{project_name}' encontrado no Clockify: ID '#{project_id}'")
    clockify_project
  end

  def create_project_in_clockify(project_name)
    clockify_project = @clockify_connector.create_project(project_name)
    @logger.info("Projeto '#{project_name}' criado com sucesso no Clockify.")
    clockify_project
  end

  def log_error(e)
    @logger.error("#{e.message}")
    @logger.error(e.backtrace.join("\n")) if e.backtrace
  end

  private

  def ensure_clockify_connector_initialized
    return unless @clockify_connector.nil?

    @logger.error("ClockifyConnector não inicializado corretamente")
    raise "ClockifyConnector não está inicializado"
  end
end
