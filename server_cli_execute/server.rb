#!/usr/bin/env ruby
# server.rb – Production-ready version

require 'json'
require 'open3'
require 'time'
require 'tempfile'

$stdout.sync = true
$stderr.sync = true

TOOL_NAME = 'shell_exec'.freeze
ROOT_DIR  = '/home/akanswal/co/manage'.freeze

def ok(id, res)
  { jsonrpc: '2.0', id: id, result: res }.to_json
end

def err(id, code, message)
  { jsonrpc: '2.0', id: id, error: { code: code, message: message } }.to_json
end

def notify(method, params = {})
  { jsonrpc: '2.0', method: method, params: params }.to_json
end

STDERR.puts 'ruby-shell helper 0.4.3 ready'

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
      proto = req.dig(:params, :protocolVersion) || '2025-06-18'
      STDOUT.puts ok(id, {
        serverInfo: { name: 'ruby-shell', version: '0.4.3' },
        capabilities: {},
        protocolVersion: proto
      })

    when 'tools/list'
      STDOUT.puts ok(id, {
        'tools' => [
          {
            'name' => TOOL_NAME,
            'description' => 'Run shell commands with live output (TTY-emulated)',
            'inputSchema' => {
              'type' => 'object',
              'properties' => {
                'cmd' => { 'type' => 'string', 'description' => 'Command to run' },
                'cwd' => { 'type' => 'string', 'description' => 'Working directory', 'default' => ROOT_DIR }
              },
              'required' => ['cmd'],
              'additionalProperties' => false
            }
          }
        ]
      })

    when 'call', 'tools/call'
      args = req.dig(:params, :arguments)
      cmd = (args[:cmd] || args['cmd']).to_s.strip
      cwd = (args[:cwd] || args['cwd']).to_s
      cwd = cwd.empty? ? ROOT_DIR : cwd
      stdout_all = +''

      begin
        tmpfile = Tempfile.new('mcp-debug')
        tmp_path = tmpfile.path
        tmpfile.close # we'll reopen for reading

        Dir.chdir(cwd) do
          escaped_cmd = cmd.gsub('"', '\"')
          script_cmd = ['script', '-qfc', "zsh -l -c \"#{escaped_cmd}\"", tmp_path]
          Open3.popen3({ 'TERM' => 'xterm' }, *script_cmd) do |stdin, stdout, stderr, wait_thr|
            stdin.close

            # Extract call_id
            call_id = args[:call_id] || args['call_id'] || 'unknown'

            # We'll track how much we've read to avoid duplication
            last_pos = 0

            reader_thread = Thread.new do
              begin
                # Wait for file to exist and have initial content
                sleep 0.05 until File.exist?(tmp_path) && File.size(tmp_path) > 0
                sleep 0.1 # Small buffer to let I/O settle

                File.open(tmp_path, "r") do |f|
                  # Loop while process is alive OR there's more to read
                  loop do
                    if !f.eof?
                      chunk = f.read(4096)
                      if chunk && !chunk.empty?
                        stdout_all << chunk
                        STDOUT.puts notify('tool/output', {
                          call_id: call_id,
                          chunk: chunk
                        })
                        STDOUT.flush
                      end
                    else
                      # EOF reached
                      break if !wait_thr.alive? # Process done → exit
                      sleep 0.01 # Wait for more output
                    end
                  end
                end
              rescue => e
                # Best effort: log to stderr, don't crash
                STDERR.puts "Reader thread error: #{e.message}"
              end
            end

            # Wait for command to finish
            wait_thr.join

            # Now wait for reader thread to catch final output
            reader_thread.join(2) # Give it 2 seconds to finish

            # Final read in case thread exited too early
            if File.readable?(tmp_path)
              File.open(tmp_path, "r") do |f|
                f.seek(last_pos) # Not perfect, but better than seeking to end
                remainder = f.read
                if remainder && !remainder.empty? && !remainder.byteslice(stdout_all.bytesize..-1) == remainder
                  # Avoid re-sending if already sent
                  unless stdout_all.end_with?(remainder)
                    stdout_all << remainder
                    STDOUT.puts notify('tool/output', {
                      call_id: call_id,
                      chunk: remainder
                    })
                    STDOUT.flush
                  end
                end
              end
            end
          end
        end
      rescue => e
        error_msg = "Command failed: #{e.message}\n"
        stdout_all << error_msg
      end
      STDOUT.puts(
        {
          jsonrpc: '2.0',
          id: id,
          result: {
            content: [
              {
                type: 'text',
                text: stdout_all
              }
            ],
            isError: false
          }
        }.to_json
      )
      STDOUT.flush

    end
  rescue => e
    STDOUT.puts err(id, -32000, e.message) if id
  end
end
