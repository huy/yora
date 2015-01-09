require 'test/unit'

require_relative 'mini_mock'
require_relative '../lib/yora'

module Yora
  class Node
    attr_writer :log, :role
    attr_reader :log_entries, :start_log_index
  end

  class Follower
    attr_writer :election_timeout
  end

  class Candidate
    attr_writer :election_timeout
  end
end

class StubTimer
  attr_writer :next

  def initialize
    @next = nil
  end

  def next
    v, @next = @next, nil
    v
  end
end

class StubPersistence
  def initialize(cluster)
    @cluster = cluster
  end

  def read_metadata
    { current_term: 0, voted_for: nil, cluster: @cluster }
  end

  def read_log_entries
    []
  end

  def read_snapshot
    {
      last_included_index: 0,
      last_included_term: 0,
      data: nil
    }
  end

  def save_metadata(_current_term, _voted_for, _cluster)
  end

  def save_log_entries(_log_entries)
  end

  def save_snapshot(_snapshot)
  end
end

class StubTransmitter
  def send_message(_send_to, _message_type, _opts)
  end
end

class Test3Nodes < Test::Unit::TestCase
  attr_reader :node, :peer, :peer_addr, :other_peer, :other_peer_addr
  attr_reader :timer, :transmitter, :handler

  include Yora

  def create_env
    @peer = '1'
    @other_peer = '2'
    @peer_addr = '127.0.0.1:2358'
    @other_peer_addr = '127.0.0.1:2359'

    @cluster = {
      '0' => '127.0.0.1:2357',
      @peer => @peer_addr,
      @other_peer => @other_peer_addr
    }

    @persistence = StubPersistence.new(@cluster)
    @handler = StateMachine::Echo.new(@persistence)
    @transmitter = StubTransmitter.new
    @timer = StubTimer.new
    @node = Node.new('0', @transmitter, @handler, @timer, @persistence)
  end

  def log_entry(term, command = nil)
    LogEntry.new(term, command)
  end
end
