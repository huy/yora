module Yora
  module StateMachine
    class Echo
      attr_accessor :node, :data

      def restore(_)
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
  end
end
