require_relative '../lib/yora'
require_relative 'mini_mock'

module Yora
  class Node
    attr_writer :log, :role
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

class StubStore < Array
  attr_accessor :current_term, :voted_for, :cluster

  def initialize(cluster)
    self << Yora::LogEntry.new(0, nil)
    @current_term = 0
    @voted_for = nil
    @cluster = cluster
  end

  def save
  end

  def truncate(index)
    self[(index + 1)..-1] = []
  end
end
