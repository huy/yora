require_relative '../lib/yora'

nodes = ARGV.select { |a| a =~ /^--node=/ }.map { |a| a.to_s.split('=')[1] }.compact.uniq

command = ARGV.find { |a| a =~ /^--command=/ }.to_s.sub('--command=', '')
query = ARGV.find { |a| a =~ /^--query=/ }.to_s.sub('--query=', '')

if nodes.empty?
  program = File.basename(__FILE__)
  $stderr.puts("Usage:\n\t#{program} --node=127.0.0.1:2358 " \
    "[--command='set abc=xyz'|--query='get abc']")
  exit(1)
end

client = Yora::Client.new(nodes)

unless command.empty?
  response = client.command(command)
  $stdout.puts response
end

unless query.empty?
  response = client.query(query)
  $stdout.puts response
end
