require 'test/unit'
require_relative 'test'

class TestCandidate < Test::Unit::TestCase
  def setup
    @peer = '1'
    @cluster = { '0' => '127.0.0.1:2357', @peer => '127.0.0.1:2358' }

    @handler = Object.new
    @transmitter = Object.new
    @transmitter.mock(:send_message)
    @timer = StubTimer.new
    @store = StubStore.new(@cluster)
    @node = Yora::Node.new('0', @transmitter, @handler, @timer, @store)
    @node.role = Yora::Candidate.new(@node, @transmitter, @timer)
  end

  attr_reader :node, :cluster, :transmitter, :peer, :timer

  def test_broadcast_vote_request_calls_transmit
    m = transmitter.mock(:send_message)

    node.role.broadcast_vote_request

    assert_equal [peer, :request_vote], m.args[0, 2]
  end

  def test_broadcast_vote_request_sends_to_all_peers
    other_peer = 2
    cluster[other_peer] = '127.0.0.1:2359'

    m = transmitter.mock(:send_message)

    node.role.broadcast_vote_request

    assert_equal 2, m.times_called

    assert_equal [@peer, :request_vote], m.args_called[0][0, 2]
    assert_equal [other_peer, :request_vote], m.args_called[1][0, 2]
  end

  def test_on_request_vote_resp_update_election
    vote_resp = { peer: peer, term: node.current_term, vote_granted: false }

    m = node.role.election.mock(:receive_vote)
    node.on_request_vote_resp vote_resp

    assert_equal 1, m.times_called
    assert_equal vote_resp, m.args[1]
  end

  def test_on_request_vote_reset_role_to_follower_on_higher_term
    node.on_request_vote term: 2, candidate_id: 1, last_log_index: 0, last_log_term: 0

    assert_equal Yora::Follower, node.role.class
  end

  def test_on_request_vote_doesnt_reset_timer_even_if_log_check_fails
    node.append_log(Yora::LogEntry.new(1, :foo))

    n = transmitter.mock(:send_message)

    node.on_request_vote term: 2, candidate_id: 1, last_log_index: 1, last_log_term: 0
    res = n.args[2]

    assert_equal false, res[:vote_granted]
  end

  def test_on_tick_timeout_restart_election
    node.role.election_timeout = Time.now - 1

    node.on_tick

    assert_equal 2, node.current_term
  end

  def test_election_update_when_won_changes_to_leader
    other_peer = 2
    cluster[other_peer] = '127.0.0.1:2359'

    transmitter.mock(:send_message)

    node.role.update_election peer: 0, term: node.current_term, vote_granted: true
    node.role.update_election peer: peer, term: node.current_term, vote_granted: true

    assert_equal Yora::Leader, node.role.class
  end

  def test_on_append_entries_become_follower
    node.on_append_entries term: 1,
                           prev_log_index: 0,
                           prev_log_term: 0,
                           entries: [],
                           commit_index: 1

    assert_equal Yora::Follower, node.role.class
  end

  def test_on_append_entries_reject
    node.current_term = 2

    m = transmitter.mock(:send_message)
    node.on_append_entries term: 1,
                           prev_log_index: 0,
                           prev_log_term: 0,
                           entries: [],
                           commit_index: 1

    assert_equal Yora::Candidate, node.role.class
    assert_equal({ success: false, term: 2 }, m.args[2])
  end
end
