module Yora
  module StateMachine
    class Echo
      attr_accessor :data

      def initialize
      end

      def on_command(command_str)
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
      def initialize(data)
        @data = data || {}
      end

      def take_snapshot
        Hash[@data]
      end

      def on_command(command_str)
        $stderr.puts "handle on_command '#{command_str}'"
        if command_str
          cmd, args = command_str.split
          $stderr.puts "-- cmd = #{cmd}, args = #{args}"
          if cmd == 'set'
            k, v = args.split('=')
            $stderr.puts "-- k = #{k}, v = #{v}"
            if k && v
              @data[k] = v

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
            return { :success => true, k => @data[k] }
          end
        end
        { success: false }
      end
    end
  end
end
