require 'httparty'
require 'logger'
require 'date'
require_relative '../support/error_handling'

require 'pry'

module ClockifyConnector
  class Client
    include HTTParty
    extend ErrorHandling

    base_uri 'https://api.clockify.me/api/v1'

    def initialize(api_key_clockify, email, workspace_name, logger)
      @logger = logger
      @api_key_clockify = api_key_clockify
      @workspace_id = get_workspace_id(workspace_name)
      @logger.info("Chamada para find_user_id_by_email com o e-mail '#{email}'")
      @user_id_clockify = find_user_id_by_email(email)
    end

    def headers
      {
        'X-Api-Key' => @api_key_clockify,
        'Content-Type' => 'application/json'
      }
    end

    def get_workspace_id(workspace_name)
      @logger.info("Obtendo o ID do workspace '#{workspace_name}'...")
      response = self.class.get('/workspaces', headers: headers)

      if response.success?
        workspaces = response.parsed_response
        workspace = workspaces.find { |ws| ws['name'] == workspace_name }

        if workspace
          @logger.info("Workspace '#{workspace_name}' encontrado com ID '#{workspace['id']}'.")
          workspace['id']
        else
          @logger.error("Workspace '#{workspace_name}' não encontrado.")
          raise "Workspace '#{workspace_name}' não encontrado."
          ErrorHandling.handle_error(response, @logger)
        end
      else
        ErrorHandling.handle_error(response, @logger)
      end
    end

    def find_user_id_by_email(email)
      @logger.info("Procurando usuário pelo e-mail '#{email}'...")

      begin
        users = list_users(@workspace_id)
        user = users.find { |user| user['email'] == email }

        raise "Usuário com o e-mail '#{email}' não encontrado no workspace #{@workspace_id}." unless user

        @logger.info("Usuário encontrado: #{user['id']}")
        user['id']
      rescue StandardError => e
        @logger.error("Erro ao buscar o usuário: #{e.message}")
        raise
      end
    end

    def list_users(workspace_id)
      @logger.info("Listando usuários no workspace '#{workspace_id}'...")

      begin
        response = self.class.get("/workspaces/#{workspace_id}/users", headers: headers)

        return response.parsed_response if response.success?

        ErrorHandling.handle_error(response, @logger)
      rescue StandardError => e
        @logger.error("Erro ao listar usuários: #{e.message}")
        raise
      end
    end

    def get_project_by_name(project_name)
      @logger.info("Procurando projeto no Clockify com o nome '#{project_name}'...")

      response = self.class.get(
        "/workspaces/#{@workspace_id}/projects",
        headers: headers,
        query: { name: project_name }
      )

      if response.success?
        projects = response.parsed_response
        project = projects.find { |proj| proj['name'].casecmp(project_name).zero? }
        if project
          @logger.info("Projeto '#{project_name}' encontrado no Clockify: ID '#{project['id']}'")
          return project
        else
          @logger.info("Projeto '#{project_name}' não encontrado no Clockify.")
          return nil
        end
      else
        ErrorHandling.handle_error(response, @logger)
      end
    rescue StandardError => e
      @logger.error("Erro ao buscar projeto no Clockify: #{e.message}")
      raise
    end

    def create_project(project_name)
      raise ArgumentError, "O nome do projeto não pode ser vazio" if project_name.blank?
      @logger.info("Criando novo projeto no Clockify com o nome '#{project_name}'...")

      with_retry do
        response = self.class.post(
          "/workspaces/#{@workspace_id}/projects",
          headers: headers,
          body: {
            name: project_name,
            isPublic: false,
            billable: true,  # Supondo que o projeto seja faturável
            color: "#000000",  # Cor padrão, você pode modificar
            memberships: []    # Pode adicionar membros aqui, se necessário
          }.to_json
        )

        if response.success?
          project = response.parsed_response
          @logger.info("Projeto '#{project_name}' criado com sucesso no Clockify: ID '#{project['id']}'")
          return project
        else
          @logger.error("Falha ao criar o projeto '#{project_name}' no Clockify: #{response.code} - #{response.message}")
          ErrorHandling.handle_error(response, @logger)
        end
      rescue StandardError => e
        @logger.error("Erro ao criar o projeto '#{project_name}' no Clockify: #{e.message}")
        raise
      end
    end

    def get_task_by_name(project_id, task_name)
      @logger.info("Procurando tarefa no Clockify com o nome '#{task_name}'...")

      response = self.class.get(
        "/workspaces/#{@workspace_id}/projects/#{project_id}/tasks",
        headers: headers,
        query: { name: task_name }
      )
      if response.success?
        tasks = response.parsed_response
        task = tasks.find { |t| t['name'].casecmp(task_name).zero? }
        if task
          @logger.info("Tarefa encontrada no Clockify: ID '#{task['id']}'")
          return task
        else
          @logger.info("Tarefa '#{task_name}' não encontrada no Clockify.")
          return nil
        end
      else
        ErrorHandling.handle_error(response, @logger)
      end
    rescue StandardError => e
      @logger.error("Erro ao buscar tarefa no Clockify: #{e.message}")
      raise
    end

    def create_task(project_id, task_name)
      @logger.info("Criando tarefa no Clockify com o nome '#{task_name}'...")

      with_retry do
        response = self.class.post(
          "/workspaces/#{@workspace_id}/projects/#{project_id}/tasks",
          headers: headers,
          body: {
            name: task_name,
            assigneeIds: [@user_id_clockify],
          }.to_json
        )

        if response.success?
          @logger.info("Tarefa '#{task_name}' criada com sucesso no Clockify.")
        else
          @logger.error("Falha ao criar a tarefa '#{task_name}' no Clockify: #{response.code} - #{response.message}")
          ErrorHandling.handle_error(response, @logger)
        end
      end
    rescue StandardError => e
      @logger.error("Erro ao criar a tarefa '#{task_name}' no Clockify: #{e.message}")
      @logger.info("Continuando a execução após tentativa de criação da tarefa.")
      raise
    end

    def task_exists?(issue)
      response = HTTParty.get("#{base_url}/workspaces/#{workspace_id}/projects/#{project_id}/tasks",
                              headers: { 'X-Api-Key' => api_key })
      tasks = JSON.parse(response.body)
      tasks.any? { |task| task['name'] == issue.subject }
    end

    def get_all_tasks(workspace_id)
      @logger.info("Buscando tarefas do Clockify para o workspace ID: #{workspace_id}...")

      response = HTTParty.get(
        "https://api.clockify.me/api/v1/workspaces/#{workspace_id}/projects/#{project_id}/tasks",
        headers: { 'X-Api-Key' => api_key }
      )

      ErrorHandling.handle_error(response, @logger) unless response.success?

      JSON.parse(response.body)

    rescue ErrorHandling::RequestError => e
      @logger.error("Falha ao buscar tarefas do Clockify: #{e.message}")
      raise
    rescue StandardError => e
      @logger.error("Erro inesperado ao buscar tarefas do Clockify: #{e.message}")
      raise
    end

    def get_clockify_time_entries(days_ago)
      raise ArgumentError, "O número de dias deve ser um inteiro positivo" unless days_ago.is_a?(Integer) && days_ago > 0

      # Calcula as datas de início e fim, considerando apenas os dias
      today = Date.today
      start_date = (today - days_ago).to_s
      end_date = today.to_s

      # Constrói a query para a API do Clockify
      query = { start: start_date, end: end_date }

      # Faz a requisição à API
      response = self.class.get("/workspaces/#{@workspace_id}/time-entries/status/in-progress", headers: headers, query: query)

      # Verifica se a requisição foi bem-sucedida
      if response.success?
        data = JSON.parse(response.body)

        if data.is_a?(Array)
          @logger.info("Entradas de tempo do Clockify obtidas com sucesso")
          return JSON.parse(response.body)
        else
          ErrorHandling.handle_error(response, @logger)
        end
      else
        ErrorHandling.handle_error(response, @logger)
      end
    rescue StandardError => e
      @logger.error("Erro ao buscar entradas de tempo no Clockify: #{e.message}")
      raise
    end

    def update_task_by_id(task_id, new_name, new_description)
      @logger.info("Atualizando tarefa com ID #{task_id} no Clockify...")

      response = self.class.put(
        "/workspaces/#{@workspace_id}/tasks/#{task_id}",
        headers: headers,
        body: {
          name: new_name,
          description: new_description
        }.to_json
      )

      if response.success?
        @logger.info("Tarefa com ID #{task_id} atualizada com sucesso.")
      else
        ErrorHandling.handle_error(response, @logger)
      end
    rescue StandardError => e
      @logger.error("Erro ao atualizar tarefa no Clockify: #{e.message}")
      raise
    end

    def list_time_entries
      @logger.info("Listando entradas de tempo no workspace '#{@workspace_id}'...")
      begin
        response = self.class.get("/workspaces/#{@workspace_id}/time-entries/status/in-progress", headers: headers)

        return response.parsed_response if response.success?

        ErrorHandling.handle_error(response, @logger)
      rescue StandardError => e
        @logger.error("Erro ao listar entradas de tempo: #{e.message}")
        raise
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
