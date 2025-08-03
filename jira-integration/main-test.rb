#!/usr/bin/env ruby
# jira-test.rb – Client to test jira-integration server

require 'json'
require 'open3'

# Config
HELPER_SCRIPT = '/home/akanswal/co/mcp/jira-integration/main.rb'
ISSUE_KEY = 'TEST-123' # Replace with a real issue key for your Jira

puts "🚀 Launching jira-integration helper..."
helper = IO.popen(['ruby', HELPER_SCRIPT], 'r+', err: [:child, :out])
sleep 0.2

at_exit do
  helper.close unless helper.closed?
  Process.wait(helper.pid) rescue nil
end

def send_json(io, obj)
  io.puts(JSON.dump(obj))
  io.flush
end

def read_json(io)
  loop do
    line = io.readline.strip
    next if line.empty?
    next unless line.start_with?('{')
    return JSON.parse(line, symbolize_names: true)
  rescue JSON::ParserError, IOError
    retry
  end
end

# 1. Initialize
send_json(helper, {
  id: 1,
  jsonrpc: '2.0',
  method: 'initialize',
  params: {}
})

loop do
  data = read_json(helper)
  break if data[:id] == 1
end

# 2. Call the jira_connect tool
send_json(helper, {
  id: 3,
  jsonrpc: '2.0',
  method: 'tools/call',
  params: {
    name: 'jira_connect',
    arguments: { issue_key: ISSUE_KEY }
  }
})

# 3. Stream output (if any)
puts "\n📤 JIRA Output:"
puts "────────────────────────────────────────────"

final_result = nil
until final_result
  data = read_json(helper)

  if data[:id] == 3 && data[:result]
    final_result = data[:result]
  end
end

# 4. Show final result
puts "\n\n📦 Final Result:"
puts "────────────────────────────────────────────"
puts JSON.pretty_generate(final_result)

exit 0