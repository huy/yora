require_relative '../lib/yora'

nodes = ARGV.select { |a| a =~ /^--node=/ }.map { |a| a.to_s.split('=')[1] }.compact.uniq

command = ARGV.find { |a| a =~ /^--command=/ }.to_s.split('=')[1]
query = ARGV.find { |a| a =~ /^--query=/ }.to_s.split('=')[1]

if nodes.empty?
  program = File.basename(__FILE__)
  $stderr.puts("Usage:\n\t#{program} --node=127.0.0.1:2358 [--command=hello|--query=world]")
  exit(1)
end

client = Yora::Client.new(nodes)

if command
  response = client.command(command)
  $stdout.puts response
end

if query
  response = client.query(query)
  $stdout.puts response
end
