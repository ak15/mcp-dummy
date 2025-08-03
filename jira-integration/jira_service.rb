# frozen_string_literal: true

require 'faraday'
require 'json'
require 'base64'

class JiraService
  BASE_URL = ENV.fetch("JIRA_BASE_URL", nil)

  def initialize
    raise "JIRA_BASE_URL environment variable not set" unless BASE_URL
    
    @conn = Faraday.new(url: "#{BASE_URL}/rest/api/2") do |faraday|
      faraday.request :authorization, :Basic, encoded_credentials
      faraday.adapter Faraday.default_adapter
    end
  end

  # Fetch a JIRA issue by key
  # @param issue_key [String] JIRA issue key (e.g., 'PROJ-123')
  # @return [Hash] parsed JSON response or error details
  def get_issue_by_key(issue_key)
    response = @conn.get("issue/#{issue_key}") do |req|
      req.params["fields"] = %w[
        summary description
      ].join(',')
    end

    if response.success?
      parse_issue_response(response.body)
    else
      [
        {
          type: 'text',
          error: "Failed to fetch issue"
        },
        {
          type: 'text',
          status: response.status,
        },
        {
          type: 'text',
          body: response.body
        }
      ]
    end
  end

  private

  # Encodes credentials for Basic Auth
  # @return [String] base64 encoded credentials
  def encoded_credentials
    email = ENV.fetch('EMAIL', nil)
    token = ENV.fetch('JIRA_PAT_TOKEN', nil)
    raise "EMAIL or JIRA_PAT_TOKEN_V2 environment variable not set" unless email && token
    
    Base64.strict_encode64("#{email}:#{token}")
  end

  # Parses the issue response body
  # @param body [String] JSON response body
  # @return [Hash] parsed issue data
  def parse_issue_response(body)
    issue_data = JSON.parse(body)
    [
      {
        type: 'text',
        text:  issue_data["fields"]["summary"]

      },
      {
        type: 'text',
        text: issue_data["fields"]["description"]
      }
    ]
  end
end

# # Example usage:
# # j = JiraService.new
# # i = j.get_issue_by_key("MX-39387")