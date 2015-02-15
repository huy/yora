require 'test/unit'
require_relative 'test'

class TestReplicaCounter < Test::Unit::TestCase
  include Yora

  def log_entry(term, command)
    CommandLogEntry.new(term, command)
  end

  def test_reach_quorum
    log_container = LogContainer.new
    log_container.append(log_entry(0, :foo))
    current_term = 0
    peer = 8
    match_indices = {peer => 1}

    assert_equal 1, log_container.last_index

    new_commit = ReplicaCounter.new(log_container,
                                    match_indices,
                                    current_term).majority_agreed_commit

    assert_equal 1, new_commit

  end

 def test_not_reach_quorum
    log_container = LogContainer.new
    log_container.append(log_entry(0, :foo))
    current_term = 0
    peer = 8
    match_indices = {peer => 0}

    assert_equal 1, log_container.last_index

    new_commit = ReplicaCounter.new(log_container,
                                    match_indices,
                                    current_term).majority_agreed_commit

    assert_equal 0, new_commit

  end
end
