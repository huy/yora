require_relative 'test'

class TestCandidate < Test3Nodes
  def setup
    create_env
    node.role = Candidate.new(node)
  end

  def test_broadcast_vote_request_sends_to_all_peers
    m = transmitter.mock(:send_message)

    node.role.broadcast_vote_request

    assert_equal 2, m.times_called

    assert_equal [peer_addr, :request_vote], m.args_called[0][0, 2]
    assert_equal [other_peer_addr, :request_vote], m.args_called[1][0, 2]
  end

  ## on_request_vote_resp

  def test_on_request_vote_resp_update_election
    vote_resp = { peer: peer, term: node.current_term, vote_granted: false }

    m = node.role.election.mock(:receive_vote)
    node.on_request_vote_resp vote_resp

    assert_equal 1, m.times_called
    assert_equal vote_resp, m.args[1]
  end

  def test_on_request_vote_resp_won_election_become_leader
    node.on_request_vote_resp(peer: peer, term: node.current_term, vote_granted: true)
    node.on_request_vote_resp(peer: other_peer, term: node.current_term, vote_granted: true)

    assert_equal Leader, node.role.class
  end

  ## on_request_vote

  def test_on_request_vote_reset_role_to_follower_on_higher_term
    node.on_request_vote term: 2, candidate_id: 1, last_log_index: 0, last_log_term: 0

    assert_equal Follower, node.role.class
  end

  def test_on_request_vote_doesnt_reset_timer_even_if_log_check_fails
    node.append_log(log_entry(1, :foo))

    m = transmitter.mock(:send_message)

    node.on_request_vote term: 2, candidate_id: 1, last_log_index: 1, last_log_term: 0
    res = m.args[2]

    assert_equal false, res[:vote_granted]
  end

  ## on_tick

  def test_on_tick_timeout_restart_election
    node.role.election_timeout = Time.now - 1

    term = node.current_term

    node.on_tick

    assert_equal term + 1, node.current_term
  end

  # on_append_entries

  def test_on_append_entries_become_follower
    node.on_append_entries term: 1,
                           prev_log_index: 0,
                           prev_log_term: 0,
                           entries: [],
                           commit_index: 1

    assert_equal Follower, node.role.class
  end

  def test_on_append_entries_reject
    node.current_term = 2

    m = transmitter.mock(:send_message)
    node.on_append_entries term: 1,
                           prev_log_index: 0,
                           prev_log_term: 0,
                           entries: [],
                           commit_index: 1

    assert_equal Candidate, node.role.class
    assert_equal({ success: false, term: 2 }, m.args[2])
  end
end
