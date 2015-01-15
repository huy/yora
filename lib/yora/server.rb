require 'thread'
require 'socket'
require 'json'

require_relative 'message'

module Yora
  DEFAULT_UDP_PORT = 2358

  class Transmitter
    attr_reader :server

    def initialize(server)
      @server = server
    end

    def send_message(send_to, message_type, opts)
      opts[:send_to] = send_to
      opts[:peer] = @server.node.node_id
      opts[:message_type] = message_type

      if opts[:send_to] == @server.node.node_id

        $stderr.puts "send #{opts[:message_type]} to local"

        @server.in_queue << opts
      else
        $stderr.puts "send #{opts[:message_type]} to #{opts[:send_to]}"

        @server.out_queue << opts
      end
    end
  end

  class Timer
    def initialize(min, max)
      @min, @max = min, max
    end

    def next
      Time.now + @min + Random.rand(@max - @min)
    end
  end

  class Server
    include Message

    attr_reader :node, :in_queue, :out_queue

    def initialize(node_id, node_address, peers, second_per_tick = 2)
      @host, @port = node_address.split(':')
      @port = @port.to_i

      @peers = peers

      @second_per_tick = second_per_tick.to_f
      @in_queue = Queue.new
      @out_queue = Queue.new

      @transmitter = Transmitter.new(self)

      @persistence = Persistence::SimpleFile.new(node_id, node_address)

      snapshot = @persistence.read_snapshot

      @handler = StateMachine::KeyValueStore.new(snapshot[:data])

      @timer = Timer.new(2 * @second_per_tick, 5 * @second_per_tick)

      @node = Node.new(node_id, @transmitter, @handler, @timer, @persistence)
    end

    def join
      client = Client.new(@peers.values)
      response = client.command(:join, peer: @node.node_id, peer_address: "#{@host}:#{@port}")
      $stderr.puts "got #{response}"

      node.cluster = response[:cluster]
      bootstrap
    end

    def leave
      client = Client.new(@peers.values)
      response = client.command(:leave, peer: @node.node_id, peer_address: "#{@host}:#{@port}")
      $stderr.puts "got #{response}"
    end

    def bootstrap
      timer = Thread.new do
        timer_loop
      end

      receiver = Thread.new do
        receiver_loop
      end

      sender = Thread.new do
        sender_loop
      end

      processor = Thread.new do
        processor_loop
      end

      [timer, receiver, sender, processor].each(&:join)
    end

    def timer_loop
      loop do
        sleep @second_per_tick

        @in_queue << { message_type: :tick }
      end
    end

    def receiver_loop
      Socket.udp_server_loop(@host, @port) do |raw, socket|
        msg = deserialize(raw)

        if msg[:message_type] == 'command' || msg[:message_type] == 'query'
          addr = socket.remote_address
          msg[:client] = "#{addr.ip_address}:#{addr.ip_port}"
        end

        @in_queue << msg
      end
    rescue => ex
      $stderr.puts "error #{ex} in receiver thread"
      $stderr.puts ex.backtrace.join("\n")
      exit(2)
    end

    def sender_loop
      socket = UDPSocket.new
      loop do
        msg = @out_queue.pop

        raw = serialize(msg)

        addr = msg[:send_to]
        if addr
          host, port = addr.split(':')
          $stderr.puts "sending #{msg[:message_type]} to #{addr}"
          _ = socket.send(raw, 0, host, port.to_i)
        else
          $stderr.puts "quietly drop #{msg[:message_type]} unknown destination"
        end
      end
    rescue => ex
      $stderr.puts "error #{ex} in sender thread"
      $stderr.puts ex.backtrace.join("\n")
      exit(2)
    end

    def processor_loop
      loop do
        msg = @in_queue.pop

        $stderr.puts "processing #{msg[:message_type]} term #{msg[:term]} " \
          "from #{msg[:client] || msg[:peer]}"

        @node.dispatch(msg)

        expiry = (@node.seconds_until_timeout / @second_per_tick).to_i
        $stderr.puts "#{node.role.class}, current term #{node.current_term}, " \
          "last commit = #{node.last_commit}, expires in #{expiry} ticks"
      end
    rescue => ex
      $stderr.puts "error #{ex} in processor thread"
      $stderr.puts ex.backtrace.join("\n")
      exit(2)
    end
  end
end
