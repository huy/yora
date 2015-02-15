require_relative 'git_util'

module Yora
  module StateMachine
    class Git
      include ::GitUtil

      attr_reader :repo_path, :node_addr
      attr_accessor :node

      def initialize(repo_path, node_addr)
        @repo_path = repo_path
        @node_addr = node_addr

        create_git_repo unless File.directory?(repo_path)

        install_git_hook
      end

      def create_git_repo
        cmd = "git init --bare #{repo_path}"
        git(cmd)
      end

      def install_git_hook
        update_hook = "#{repo_path}/hooks/update"
        yora_root_dir = File.expand_path(File.join(File.dirname(__FILE__), '..'))

        File.open(update_hook, 'w', 0750) do |f|
          f.write(<<EOS
#!/usr/bin/env ruby

require_relative '#{yora_root_dir}/lib/yora/client'
require_relative '#{yora_root_dir}/sample/git_util'

include GitUtil

refname, oldrev, newrev = ARGV
arr = refname.split('/')
arr[2] = 'for_' + arr[2]
for_refname = arr.join('/')

cmd = ['git --git-dir=', ENV['GIT_DIR'], ' update-ref ', for_refname, ' ', newrev].join
git(cmd)

client = Yora::Client.new(['#{node_addr}'])
msg = client.send_request('#{node_addr}', message_type: :command, command: ARGV.join(' '))

if msg && msg[:success]
  # this is workaround because the our git fsm has already updated refname,
  # but the git command line requires refname pointed to oldrev to succeed
  cmd = ['git --git-dir=', ENV['GIT_DIR'], ' update-ref ', refname, ' ', oldrev].join
  git(cmd)
  exit(0)
end

exit(1)
EOS
          )
        end
      end

      def git_fetch(refname)
        leader_host = node.leader_addr.split(':').first
        leader_repo_path = repo_path.sub(node.node_id, node.leader_id)
        leader_git_url = "ssh://#{leader_host}#{leader_repo_path}"

        cmd = "git --git-dir=#{repo_path} fetch #{leader_git_url} +#{refname}:#{refname}"

        git(cmd)
      end

      def git_update_ref(refname, newrev)
        cmd = "git --git-dir=#{repo_path} update-ref #{refname} #{newrev}"
        git(cmd)
      end

      def restore(data)
        @data = data || {}
      end

      def pre_command(update_ref)
        refname, _, _ = update_ref.split
        arr = refname.split('/')
        arr[2] = "for_#{arr[2]}"
        for_refname = arr.join('/')

        git_fetch(for_refname)
      end

      def on_command(update_ref)
        refname, _, newrev = update_ref.split

        @data[refname] = newrev
        git_update_ref(refname, newrev)

        { success: true }
      end

      def post_command(_)
        $stderr.puts "-- save_snapshot last_applied = #{node.last_applied}, data = #{@data}"
        node.save_snapshot
      end

      def on_query(_query_str)
      end

      # rubocop:disable TrivialAccessors
      def take_snapshot
        @data
      end

      def data=(value)
        @data = value || {}
        @data.each do |refname, _newrev|
          git_fetch(refname)
        end
      end
    end
  end
end
