module Yora
  module StateMachine
    class Echo
      attr_reader :last_included_index, :last_included_term

      def initialize(persistence)
        snapshot = persistence.read_snapshot

        @last_included_index = snapshot[:last_included_index]
        @last_included_term = snapshot[:last_included_term]
      end

      def on_command(command_str, _applied_index, _applied_term)
        $stderr.puts "handler on_command '#{command_str}'"

        { success: true, data: command_str }
      end

      def on_query(query_str)
        $stderr.puts "handle on_query '#{query_str}'"

        { success: true, data: query_str }
      end

      def take_snapshot
        nil
      end
    end

    class KeyValueStore
      attr_reader :last_included_index, :last_included_term

      def initialize(persistence)
        snapshot = persistence.read_snapshot

        @kv = snapshot[:data] || {}
        @last_included_index = snapshot[:last_included_index]
        @last_included_term = snapshot[:last_included_term]
      end

      def take_snapshot
        Hash[@kv]
      end

      def on_command(command_str, _applied_index, _applied_term)
        $stderr.puts "handle on_command '#{command_str}'"
        if command_str
          cmd, args = command_str.split
          $stderr.puts "-- cmd = #{cmd}, args = #{args}"
          if cmd == 'set'
            k, v = args.split('=')
            $stderr.puts "-- k = #{k}, v = #{v}"
            if k && v
              @kv[k] = v

              return { success: true }
            end
          end
        end
        { success: false }
      end

      def on_query(query_str)
        $stderr.puts "handle on_query '#{query_str}'"

        if query_str
          query, args = query_str.split
          if query == 'get'
            k = args
            return { :success => true, k => @kv[k] }
          end
        end
        { success: false }
      end
    end
  end
end
