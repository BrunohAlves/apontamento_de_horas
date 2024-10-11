# encoding: UTF-8
require 'httparty'
require 'logger'
require 'date'
require_relative '../support/error_handling'

module ClockifyConnector
  class Client
    include HTTParty
    extend ErrorHandling
    attr_reader :workspace_id

    base_uri 'https://api.clockify.me/api/v1'

    def initialize(api_key_clockify, email, workspace_name, logger)
      @logger = logger
      @api_key_clockify = api_key_clockify
      @workspace_name = workspace_name
      @workspace_id = '63fe21bea094e40fbee3b92e'
      # binding.pry
      # @workspace_id = get_workspace_id_by_name(workspace_name)
      @user_id_clockify = find_user_id_by_email(email)
      @projects_cache = {}
      # @headers = RequestHeaders.clockify_headers(api_key_clockify)
    end

    def find_user_id_by_email(email)
      @logger.info("Procurando usuário pelo e-mail '#{email}'...")
      users = list_users(@workspace_id)
      user = users.find { |u| u['email'] == email }

      raise "Usuário com o e-mail '#{email}' não encontrado no workspace #{@workspace_id}." unless user

      @logger.info("Usuário encontrado: #{user['id']}")
      user['id']
    end

    def list_users(workspace_id)
      @logger.info("Listando usuários no workspace '#{workspace_id}'...")
      response = self.class.get("/workspaces/#{workspace_id}/users", headers: {
        'X-Api-Key' => @api_key_clockify,
        'Content-Type' => 'application/json'
      })

      response.success? ? response.parsed_response : ErrorHandling.handle_error(response, @logger)
    rescue StandardError => e
      @logger.error("Erro ao listar usuários: #{e.message}")
      raise
    end

    def get_all_projects(workspace_id)
      @logger.info("Buscando todos os projetos no Clockify para o workspace #{@workspace_name}...")

      response = self.class.get("/workspaces/#{workspace_id}/projects",
                                query: { 'page-size' => 1000 },
                                headers: { 'X-Api-Key' => @api_key_clockify, 'Content-Type' => 'application/json' })


      if response.success?
        @logger.info("Projetos obtidos com sucesso.")
        return response.parsed_response
      else
        @logger.error("Erro ao buscar projetos no Clockify: #{response.code} - #{response.body}")
        ErrorHandling.handle_error(response, @logger)
      end
    rescue StandardError => e
      @logger.error("Erro ao buscar projetos: #{e.message}")
      raise
    end

    def create_project(project_name)
      @logger.info("Criando projeto '#{project_name}' no Clockify...")

      response = self.class.post(
        "/workspaces/#{@workspace_id}/projects",
        headers: { 'X-Api-Key' => @api_key_clockify, 'Content-Type' => 'application/json' },
        body: { name: project_name, isPublic: false }.to_json # Adicione outras propriedades necessárias, se for o caso
      )

      if response.success?
        @logger.info("Projeto '#{project_name}' criado com sucesso no Clockify.")
        response.parsed_response # Retorna a resposta da API com os dados do projeto criado
      else
        ErrorHandling.handle_error(response, @logger)
      end
    rescue StandardError => e
      @logger.error("Erro ao criar projeto '#{project_name}' no Clockify: #{e.message}")
      raise
    end


    def get_project_by_name(project_name)
      @logger.info("Procurando projeto no Clockify com o nome '#{project_name}'...")

      projects = get_all_projects(@workspace_id)
      project = projects.find { |proj| proj['name'].casecmp(project_name).zero? }

      if project
        @projects_cache[project['id']] ||= project['name']
        project
      else
        @logger.error("Projeto '#{project_name}' não encontrado.")
        nil
      end
    end

    def project_name(project_id)
      return 'N/A' unless project_id

      @projects_cache[project_id] ||= get_project_by_id(project_id)['name']
    end

    def get_task_name_from_clockify(task_id, project_id)
      @logger.info("Buscando nome da tarefa #{task_id} no projeto #{project_id}...")
      tasks = get_tasks_for_project(project_id)
      task = tasks.find { |t| t['id'] == task_id }
      task ? task['name'] : 'Tarefa não encontrada'
    end

    # Função para obter o nome da tarefa no Clockify
    def get_tasks_for_project(project_id)
      @logger.info("   Buscando todas as tarefas do projeto no Clockify...")

      response = self.class.get(
        "/workspaces/#{@workspace_id}/projects/#{project_id}/tasks",
        headers: { 'X-Api-Key': @api_key_clockify, 'Content-Type': 'application/json' })

      if response.success?
        tasks = response.parsed_response.map do |task|
          task['name'] = task['name'].force_encoding('UTF-8') # Aplicar codificação UTF-8
          task
        end

        if tasks.empty?
          @logger.error("Nenhuma tarefa encontrada para o projeto #{project_id}")
          return []
        end

        @logger.info("    Tarefas obtidas com sucesso para o projeto.")
        tasks
      else
        ErrorHandling.handle_error(response, @logger)
      end
    rescue StandardError => e
      @logger.error("Erro ao buscar tarefas no Clockify: #{e.message}")
      raise
    end

    def create_task(project_id, task_name, redmine_issue)
      @logger.info("Criando nova tarefa no projeto #{project_id} com o nome '#{task_name}'")

      issue_id = redmine_issue['id']

      # Verifica se o issue_id já está presente no nome da tarefa
      unless task_name.match(/^\[#{issue_id}\]/)
        task_name = "[#{issue_id}] #{task_name}"  # Adiciona o issue_id ao nome da tarefa
      end

      # Mapeia o status do Redmine para o Clockify
      redmine_status = redmine_issue.dig('status', 'name') || 'Em Andamento'
      status_mapping = {
        'Novo' => 'ACTIVE',
        'Aguardando resposta' => 'ACTIVE',
        'Em Andamento' => 'ACTIVE',
        'Resolvendo' => 'ACTIVE',
        'Concluído' => 'DONE',
        'Permanente' => 'ACTIVE',  # Mapeia "Permanente" para "ACTIVE"
        # Adicione outros mapeamentos conforme necessário
      }
      status = status_mapping[redmine_status] || 'ACTIVE'

      # Força a codificação das strings para UTF-8
      task_name = task_name.force_encoding('UTF-8')
      description = redmine_issue['description'] ? redmine_issue['description'].force_encoding('UTF-8') : nil

      # Loga as codificações para diagnóstico
      @logger.debug("Encoding do nome da tarefa: #{task_name.encoding}")
      @logger.debug("Encoding da descrição: #{description.encoding}") if description

      # Monta os dados da tarefa para a API do Clockify
      task_data = {
        name: task_name,
        assigneeIds: [@user_id_clockify],
        status: status
      }

      task_data[:description] = description if description.present?

      @logger.debug("Dados da tarefa a serem enviados: #{task_data}")

      # Faz a requisição para criar a tarefa no Clockify
      response = self.class.post(
        "/workspaces/#{@workspace_id}/projects/#{project_id}/tasks",
        headers: { 'X-Api-Key' => @api_key_clockify, 'Content-Type' => 'application/json' },
        body: task_data.to_json
      )

      if response.success?
        @logger.info("Tarefa '#{task_name}' criada com sucesso no Clockify.")
      else
        @logger.error("Erro ao criar a tarefa '#{task_name}' no Clockify: Código #{response.code}, Resposta: #{response.body}")
        ErrorHandling.handle_error(response, @logger)
      end
    end

    def get_task(project_id, task_id)
      response = self.class.get(
        "/workspaces/#{@workspace_id}/projects/#{project_id}/tasks/#{task_id}",
        headers: { 'X-Api-Key' => @api_key_clockify }
      )

      if response.success?
        response.parsed_response
      else
        @logger.error("Erro ao obter a tarefa com ID #{task_id}: Código #{response.code}, Resposta: #{response.body}")
        nil
      end
    end

    def update_task(project_id, task_id, task_data)
      @logger.info("Atualizando tarefa no projeto #{project_id} com os novos dados: #{task_data}")

      # Construir o corpo da requisição com os dados atualizados
      body = task_data.to_json

      response = self.class.put(
        "/workspaces/#{@workspace_id}/projects/#{project_id}/tasks/#{task_id}",
        headers: { 'X-Api-Key' => @api_key_clockify, 'Content-Type' => 'application/json' },
        body: body
      )

      if response.success?
        @logger.info("Tarefa '#{task_data['name']}' atualizada com sucesso no Clockify.")
      else
        ErrorHandling.handle_error(response, @logger)
      end
    end

    # Método para verificar se qualquer campo relevante da issue mudou
    def task_needs_update?(existing_task, redmine_issue)
      issue_id = redmine_issue['id']
      redmine_task_name = "[#{issue_id}] #{redmine_issue['subject']}" # Nome no formato [issue_id] Nome da tarefa
      redmine_description = redmine_issue['description']
      redmine_assigned_to = redmine_issue.dig('assigned_to', 'name')
      redmine_status = redmine_issue.dig('status', 'name')

      # Verifica se o nome da tarefa ou outros campos importantes mudaram
      existing_task_name = existing_task['name']
      existing_description = existing_task['description'] # Supondo que você guarde a descrição no Clockify
      existing_assigned_to = existing_task.dig('assignee', 'name')
      existing_status = existing_task['status']

      return true if existing_task_name != redmine_task_name
      return true if existing_description != redmine_description
      return true if existing_assigned_to != redmine_assigned_to
      return true if existing_status != redmine_status

      false
    end


    def find_task_in_clockify(task_name, project_id)
      @logger.info("Buscando tarefa '#{task_name}' no Clockify para o projeto '#{project_id}'")

      tasks = self.get_tasks_for_project(project_id)

      tasks.find { |task| task['name'] == task_name }
    end

    def get_clockify_time_entries_for_user(user_id)
      start_date = Time.new(2024, 10, 11).utc.iso8601
      end_date = Time.now.utc.iso8601  # Data final será a data e hora atual
      query = {
        start: start_date,
        end: end_date,
        page: 1,
        page_size: 1000
      }

      response = self.class.get("/workspaces/#{@workspace_id}/user/#{user_id}/time-entries",  headers: {
        'X-Api-Key' => @api_key_clockify,
        'Content-Type' => 'application/json'
      }, query: query)

      if response.success?
        data = JSON.parse(response.body)

        # Filtrando as entradas que possuem projectId
        filtered_data = data.select { |entry| entry['projectId'].present? }

        if filtered_data.empty?
          @logger.warn("Nenhuma entrada de tempo com projectId foi encontrada para o usuário #{user_id}.")
          return []
        end

        @logger.info("Entradas de tempo com projectId do usuário #{user_id} obtidas com sucesso")
        filtered_data
      else
        ErrorHandling.handle_error(response, @logger)
      end
    rescue StandardError => e
      @logger.error("Erro ao buscar entradas de tempo no Clockify para o usuário #{user_id}: #{e.message}")
      raise
    end
  end
end
