#!/usr/bin/env ruby
# main.rb – Production-ready version

require 'json'
require 'time'
require_relative './jira_service'

$stdout.sync = true
$stderr.sync = true

TOOL_NAME = 'jira_connect'.freeze

def ok(id, res)
  { jsonrpc: '2.0', id: id, result: res }.to_json
end

def err(id, code, message)
  { jsonrpc: '2.0', id: id, error: { code: code, message: message } }.to_json
end

def notify(method, params = {})
  { jsonrpc: '2.0', method: method, params: params }.to_json
end

def handle_initialize(id, req)
  proto = req.dig(:params, :protocolVersion) || '2025-06-18'
  STDOUT.puts ok(id, {
    serverInfo: { name: 'jira_connect', version: '0.4.3' },
    capabilities: {},
    protocolVersion: proto
  })
end

def handle_tools_list(id)
  STDOUT.puts ok(id, {
    'tools' => [
      {
        'name' => TOOL_NAME,
        'description' => 'Get JIRA issue details by key',
        'inputSchema' => {
          'type' => 'object',
          'properties' => {
            'issue_key' => { 'type' => 'string', 'description' => 'Jira issue key' },
          },
          'required' => ['issue_key'],
          'additionalProperties' => false
        }
      }
    ]
  })
end

def handle_call(id, args)
  issue_key = (args[:issue_key] || args['issue_key']).to_s.strip
  result = {}

  begin
    jira = JiraService.new
    issue = jira.get_issue_by_key(issue_key)

  rescue => e
    error_msg = "Jira fetch failed: #{e.message}\n"
    stdout_all << error_msg
  end

  STDOUT.puts(
    {
      jsonrpc: '2.0',
      id: id,
      result: {
        content: issue,
        isError: false
      }
    }.to_json
  )
  STDOUT.flush
end

STDERR.puts 'jira-integration helper 0.4.3 ready'

STDIN.each_line do |line|
  line.strip!
  next if line.empty?

  begin
    req = JSON.parse(line, symbolize_names: true)
    id = req[:id]
    meth = req[:method]
    next if id.nil?

    case meth
    when 'initialize'
      handle_initialize(id, req)
    when 'tools/list'
      handle_tools_list(id)
    when 'call', 'tools/call'
      args = req.dig(:params, :arguments)
      handle_call(id, args)
    end
  rescue => e
    STDOUT.puts err(id, -32000, e.message) if id
  end
end