#!/usr/bin/env ruby
# server-test.rb – Client to test ruby-shell server

require 'json'
require 'open3'

# Config
HELPER_SCRIPT = '/home/akanswal/co/mcp-run-commands/server.rb'
CMD = 'debe rspec spec/lib/wired/live_tools/power_stats/catalyst_spec.rb'

# Start the server
puts "🚀 Launching ruby-shell helper..."
helper = IO.popen(['ruby', HELPER_SCRIPT], 'r+', err: [:child, :out])
sleep 0.2

# Ensure cleanup
at_exit do
  helper.close unless helper.closed?
  Process.wait(helper.pid) rescue nil
end

# JSON-RPC helpers
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

# 2. Call the shell_exec tool
send_json(helper, {
  id: 3,
  jsonrpc: '2.0',
  method: 'tools/call',
  params: {
    name: 'local-shell/shell_exec',
    arguments: { cmd: CMD }
  }
})

# 3. Stream output
puts "\n📤 Live Output:"
puts "────────────────────────────────────────────"

final_result = nil
until final_result
  data = read_json(helper)

  if data[:method] == 'tool/output'
    chunk = data[:params][:chunk]
    print chunk
    $stdout.flush
  elsif data[:id] == 3 && data[:result]
    final_result = data[:result]
  end
end

# 4. Show final result
puts "\n\n📦 Final Result:"
puts "────────────────────────────────────────────"
puts JSON.pretty_generate(final_result)

# Exit with same status
exit(final_result[:status] || 1)
