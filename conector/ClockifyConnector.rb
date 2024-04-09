require 'httparty'
require 'logger'

class ClockifyConnector
  include HTTParty
  base_uri 'https://api.clockify.me/api/v1'

  def initialize(api_key_clockify, email, logger)
    @logger = logger
    @api_key_clockify = api_key_clockify
    @workspace_id = list_workspaces
    @user_id_clockify = find_user_id_by_email(@workspace_id, email)
    @projects_cache = {}
    @tags_cache = {}
  end

  def list_time_entries
    headers = {
      'X-Api-Key' => @api_key_clockify,
      'Content-Type' => 'application/json'
    }
    @logger.info('Listing time entries...')
    response = self.class.get("/workspaces/#{@workspace_id}/user/#{@user_id_clockify}/time-entries", headers: headers)

    if response.success?
      @logger.info('Time entries listed successfully.')
      return response.parsed_response.map do |entry|
        {
          interval: time_interval(entry),
          project_name: project_name(entry['projectId']),
          tag: tag_name(entry['tagIds']&.first),
          tag_description: tag_description(entry['tagIds']&.first),
          created_at: format_date(entry['timeInterval']['start']),
          description: entry['description'] || 'N/A'
        }
      end
    else
      @logger.error("Error listing time entries: #{response.code} - #{response.parsed_response['message']}")
      raise "Erro ao listar as entradas de tempo do usuário no workspace: #{response.code} - #{response.parsed_response['message']}"
    end
  end

  def list_workspaces
    @logger.info('Listing workspaces...')
    response = self.class.get("/workspaces", headers: headers)

    if response.success?
      @logger.info('Workspaces listed successfully.')
      workspaces = response.parsed_response
      workspace = workspaces.find { |workspace| workspace["name"] == 'Turia' }
      if workspace
        return workspace["id"]
      else
        raise "Não foi encontrado nenhum workspace com o nome 'Turia'"
      end
    else
      @logger.error("Error listing workspaces: #{response.code} - #{response.parsed_response['message']}")
      raise "Erro ao listar os workspaces: #{response.code} - #{response.parsed_response['message']}"
    end
  end

  def headers
    {
      'X-Api-Key' => @api_key_clockify,
      'Content-Type' => 'application/json'
    }
  end

  private

  def find_user_id_by_email(workspace_id, email)
    users = list_users(workspace_id)
    user = users.find { |user| user['email'] == email }

    if user
      return user['id']
    else
      @logger.error("Usuário com o e-mail '#{email}' não encontrado no workspace #{workspace_id}.")
      raise "Usuário com o e-mail '#{email}' não encontrado no workspace #{workspace_id}."
    end
  end
  
  def list_users(workspace_id)
    headers = {
      'X-Api-Key' => @api_key_clockify,
      'Content-Type' => 'application/json'
    }
    response = self.class.get("/workspaces/#{workspace_id}/users", headers: headers)

    if response.success?
      return response.parsed_response
    else
      @logger.error("Erro ao listar os usuários: #{response.code} - #{response.parsed_response['message']}")
      raise "Erro ao listar os usuários: #{response.code} - #{response.parsed_response['message']}"
    end
  end

  def time_interval(entry)
    start_time = Time.parse(entry['timeInterval']['start'])
    end_time = Time.parse(entry['timeInterval']['end'])
    duration_seconds = end_time - start_time
    hours = duration_seconds / 3600
    minutes = (duration_seconds % 3600) / 60
    "#{format('%02d', hours)}:#{format('%02d', minutes)}"
  end

  def project_name(project_id)
    return 'N/A' unless project_id

    @projects_cache[project_id] ||= begin
      response = self.class.get("/workspaces/#{@workspace_id}/projects/#{project_id}", headers: headers)
      response.success? ? response.parsed_response['name'] : 'N/A'
    end
  end

  def tag_name(tag_id)
    return 'N/A' unless tag_id

    @tags_cache[tag_id] ||= begin
      response = self.class.get("/workspaces/#{@workspace_id}/tags/#{tag_id}", headers: headers)
      response.success? ? response.parsed_response['name'] : 'N/A'
    end
  end

  def tag_description(tag_id)
    return 'N/A' unless tag_id

    @tags_cache[tag_id] ||= begin
      response = self.class.get("/workspaces/#{@workspace_id}/tags/#{tag_id}", headers: headers)
      response.success? ? response.parsed_response['description'] : 'N/A'
    end
  end

  def format_date(date_str)
    Time.parse(date_str).strftime("%Y-%m-%d")
  rescue
    'N/A'
  end
end
