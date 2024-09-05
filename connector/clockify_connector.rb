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
          @logger.info("Projeto criado com sucesso no Clockify: ID '#{project['id']}'")
          project
        else
          @logger.error("Falha ao criar projeto no Clockify: #{response.code} - #{response.message}")
          ErrorHandling.handle_error(response, @logger)
        end
      end
    rescue StandardError => e
      @logger.error("Erro ao criar projeto no Clockify: #{e.message}")
      raise
    end

    def get_task_by_name(project_id, task_name)
      @logger.info("Procurando task no Clockify com o nome '#{task_name}'...")

      response = self.class.get(
        "/workspaces/#{@workspace_id}/projects/#{project_id}/tasks",
        headers: headers,
        query: { name: task_name }
      )
      if response.success?
        tasks = response.parsed_response
        task = tasks.find { |t| t['name'].casecmp(task_name).zero? }
        if task
          @logger.info("Task encontrada no Clockify: ID '#{task['id']}'")
          return task
        else
          @logger.info("Task '#{task_name}' não encontrada no Clockify.")
          return nil
        end
      else
        ErrorHandling.handle_error(response, @logger)
      end
    rescue StandardError => e
      @logger.error("Erro ao buscar task no Clockify: #{e.message}")
      raise
    end

    def create_task(project_id, task_name)
      @logger.info("Creating task in Clockify with name '#{task_name}'...")

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
          @logger.info("Task '#{task_name}' created successfully in Clockify.")
        else
          @logger.error("Falha ao criar tarefa no Clockify: #{response.code} - #{response.message}")
          ErrorHandling.handle_error(response, @logger)
        end
      end
    rescue StandardError => e
      @logger.error("Error creating task in Clockify: #{e.message}")
      @logger.info("Continuando a execução após tentativa de criação da task.")
      raise
    end

    def task_exists?(issue)
      response = HTTParty.get("#{base_url}/workspaces/#{workspace_id}/projects/#{project_id}/tasks",
                              headers: { 'X-Api-Key' => api_key })
      tasks = JSON.parse(response.body)
      tasks.any? { |task| task['name'] == issue.subject }
    end

    def get_all_tasks(workspace_id)
      @logger.info("Fetching tasks from Clockify for workspace ID: #{workspace_id}...")

      response = HTTParty.get(
        "https://api.clockify.me/api/v1/workspaces/#{workspace_id}/projects/#{project_id}/tasks",
        headers: { 'X-Api-Key' => api_key }
      )

      ErrorHandling.handle_error(response, @logger) unless response.success?

      JSON.parse(response.body)

    rescue ErrorHandling::RequestError => e
      @logger.error("Failed to fetch tasks from Clockify: #{e.message}")
      raise
    rescue StandardError => e
      @logger.error("Unexpected error while fetching tasks from Clockify: #{e.message}")
      raise
    end

    def get_clockify_time_entries(start_date = nil, end_date = nil)
      query = {}
      # Adiciona filtros de data, se fornecidos
      if start_date.is_a?(Time) || start_date.is_a?(DateTime)
        query[:start] = start_date.utc.iso8601
      end

      if end_date.is_a?(Time) || end_date.is_a?(DateTime)
        query[:end] = end_date.utc.iso8601
      end

      response = self.class.get("/workspaces/#{@workspace_id}/time-entries/status/in-progress",headers: headers, query: query)

      if response.success?
        @logger.info("Entredas de tempo do clockify obtidas com sucesso")
        JSON.parse(response.body)
      else
        ErrorHandling.handle_error(response, @logger)
      end
    rescue StandardError => e
      @logger.error("Error getting task in Clockify: #{e.message}")
      raise
    end

    def update_task_by_id(task_id, new_name, new_description)
      @logger.info("Updating task with ID #{task_id} in Clockify...")

      response = self.class.put(
        "/workspaces/#{@workspace_id}/tasks/#{task_id}",
        headers: headers,
        body: {
          name: new_name,
          description: new_description
        }.to_json
      )

      if response.success?
        @logger.info("Task with ID #{task_id} updated successfully.")
      else
        ErrorHandling.handle_error(response, @logger)
      end
    rescue StandardError => e
      @logger.error("Error updating task in Clockify: #{e.message}")
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
