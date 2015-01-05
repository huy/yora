require_relative '../lib/yora'

node_id = ARGV.find { |a| a =~ /^--node=/ }.to_s.split('=')[1]

bind = ARGV.find { |a| a =~ /^--bind=/ }.to_s.split('=')[1]
bind ||= "0.0.0.0:#{Yora::DEFAULT_UDP_PORT}"

peer_args = ARGV.select { |a| a =~ /^--peer=/ }.map { |a| a.to_s.split('=')[1] }.compact.uniq

peers = Hash[peer_args.map { |s| s.split(',') }]

join = ARGV.find { |a| a == '--join' }
leave = ARGV.find { |a| a == '--leave' }

unless node_id
  program = File.basename(__FILE__)
  $stderr.puts("Usage:\n\t#{program} --node=888 [--bind=127.0.0.1:2358] [--join] " \
    '[--peer=999,127.0.0.1:2359]')
  $stderr.puts("\t#{program} --node=888 [--leave] --peer=999,127.0.0.1:2359 ")
  exit(1)
end

server = Yora::Server.new(node_id, bind, peers)

if join
  server.join
elsif leave
  server.leave
else
  server.bootstrap
end
