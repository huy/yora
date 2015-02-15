require_relative '../lib/yora'
require_relative 'git_fsm'

node = ARGV.find { |a| a =~ /^--node=/ }.to_s.split('=')[1].to_s
node_id, bind = node.split(',')

bind = "0.0.0.0:#{Yora::DEFAULT_UDP_PORT}" unless bind
bind = "0.0.0.0:#{bind}" if bind[0] == ':'

peer_args = ARGV.select { |a| a =~ /^--peer=/ }.map { |a| a.to_s.split('=')[1] }.compact.uniq

peers = Hash[peer_args.map { |s| s.split(',') }]

join = ARGV.find { |a| a == '--join' }
leave = ARGV.find { |a| a == '--leave' }

debug = ARGV.any? { |a| a =~ /^--debug/ }

unless node_id
  program = File.basename(__FILE__)
  $stderr.puts("Usage:\n\t#{program} --node=888,127.0.0.1:2358 [--join|--leave] " \
    '[--peer=999,127.0.0.1:2359] [--debug]')
  exit(1)
end

puts "starting node #{node_id}, bind #{bind}"

git_repo_path = File.join(File.dirname(__FILE__), "data/#{node_id}/gitit")
git_repo_path = File.expand_path(git_repo_path)

handler = Yora::StateMachine::Git.new(git_repo_path, bind)
server = Yora::Server.new(node_id,
                          bind,
                          handler,
                          peers)

server.debug = debug

if join
  server.join
elsif leave
  server.leave
else
  server.bootstrap
end
