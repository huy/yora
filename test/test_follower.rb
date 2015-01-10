require_relative 'test'

class TestFollower < Test3Nodes
  def setup
    create_env
  end

  ## on_tick

  def test_on_tick_timeout_become_candidate_and_broadcast_vote
    node.role.election_timeout = Time.now - 1

    t = Time.now + 2
    timer.next = t

    m = transmitter.mock(:send_message)

    term = node.current_term

    node.on_tick

    assert_equal 2, m.times_called

    req = m.args_called[0][2]

    assert_equal term + 1, node.current_term

    assert_equal term + 1, req[:term]
    assert_equal node.node_id, req[:candidate_id]
    assert_equal 0, req[:last_log_index]
    assert_equal 0, req[:last_log_term]
  end

  ## on_append_entries

  def test_on_append_entries_reset_election_timer
    t = Time.now + 0.200
    timer.next = t

    node.on_append_entries term: 0,
                           prev_log_index: 0,
                           prev_log_term: 0,
                           entries: [],
                           commit_index: 1

    assert_equal t, node.role.election_timeout
  end

  def test_on_append_entries_ignores_outdated_term
    node.current_term = 1

    m = transmitter.mock(:send_message)
    node.on_append_entries term: 0

    res = m.args[2]
    assert_equal false, res[:success]
  end

  def test_on_append_entries_updates_current_term_when_greater
    node.on_append_entries term: 1,
                           prev_log_index: 0,
                           prev_log_term: 0,
                           entries: [],
                           commit_index: 1

    assert_equal 1, node.current_term
  end

  def test_on_append_entries_fails_if_prev_term_check_fails
    node.append_log(log_entry(1, :a))

    m = transmitter.mock(:send_message)

    node.on_append_entries term: 1,
                           prev_log_index: 1,
                           prev_log_term: 0

    res = m.args[2]
    assert_equal false, res[:success]
  end

  def test_on_append_entries_discard_conflicting_entries_before_appending
    node.append_log(log_entry(0, :a), log_entry(0, :b))

    node.on_append_entries term: 1,
                           prev_log_index: 0,
                           prev_log_term: 0,
                           entries: [log_entry(1, :c)],
                           commit_index: 1

    assert_equal 1, node.last_log_index
    assert_equal 1, node.last_log_term
    assert_equal :c, node.log(node.last_log_index).command
  end

  def test_on_append_entries_apply_entries
    m = handler.mock(:on_command)

    node.on_append_entries term: 0,
                           prev_log_index: 0,
                           prev_log_term: 0,
                           entries: [log_entry(0, :a), log_entry(0, :b)],
                           commit_index: 2

    assert_equal [:a, :b], m.args_called.map { |a| a[0] }
  end

  def test_on_append_entries_doesnt_reapply_already_applied_entries
    node.append_log(log_entry(0, :a))
    node.last_applied = 1

    m = handler.mock(:on_command)
    node.on_append_entries term: 1,
                           prev_log_index: 1,
                           prev_log_term: 0,
                           entries: [log_entry(0, :b)],
                           commit_index: 2

    assert_equal [:b], m.args[0, 1]
  end

  def test_on_append_config_entry_change_cluster_configuration
    new_cluster = { '0' => '127.0.0.1:2357', '1' => '127.0.0.1:2358' }

    node.on_append_entries term: 0,
                           prev_log_index: 0,
                           prev_log_term: 0,
                           entries: [ConfigLogEntry.new(0, new_cluster)],
                           commit_index: 2

    assert_equal node.cluster, new_cluster
  end

  def test_on_append_entries_take_snapshot_when_exceeding_max_log
    node.append_log(log_entry(0, :a))

    def node.max_log_entries
      2
    end

    m = persistence.mock(:save_snapshot)

    node.on_append_entries term: 1,
                           prev_log_index: 1,
                           prev_log_term: 0,
                           entries: [log_entry(0, :b), log_entry(0, :c), log_entry(1, :d)],
                           commit_index: 3

    assert_equal 3, node.last_commit
    assert_equal 3, node.last_applied
    assert_equal 1, m.times_called
    assert_equal [log_entry(1, :d)], node.log_entries
    assert_equal 4, node.first_log_index

    assert_equal 3, handler.last_included_index
    assert_equal 0, handler.last_included_term
  end

  ## on_request_vote

  def test_on_request_vote_issues_vote
    m = transmitter.mock(:send_message)

    node.on_request_vote term: 1, candidate_id: peer, last_log_index: 0, last_log_term: 0

    res = m.args[2]

    assert_equal 1, res[:term]
    assert_equal true, res[:vote_granted]

    assert_equal peer, node.voted_for
    assert_equal 1, node.current_term
  end

  def test_on_request_vote_from_stale
    node.current_term = 2

    m = transmitter.mock(:send_message)

    node.on_request_vote term: 1, candidate_id: 1, last_log_index: 0, last_log_term: 0

    res = m.args[2]

    assert_equal 2, res[:term]
    assert_equal false, res[:vote_granted]

    assert_equal nil, node.voted_for
    assert_equal 2, node.current_term
  end

  def test_on_request_vote_from_same_term
    node.current_term = 1

    m = transmitter.mock(:send_message)

    node.on_request_vote term: 1, candidate_id: 1, last_log_index: 0, last_log_term: 0

    res = m.args[2]

    assert_equal 1, res[:term]
    assert_equal true, res[:vote_granted]

    assert_equal 1, node.voted_for
    assert_equal 1, node.current_term
  end

  def test_on_request_vote_doesnt_change_voted_for_with_outstanding_vote
    node.voted_for = '2'
    node.current_term = 1

    node.on_request_vote term: 1, candidate_id: '1', last_log_index: 0, last_log_term: 0

    assert_equal '2', node.voted_for
  end

  def test_on_request_vote_fails_if_local_log_last_entry_has_higher_term
    node.append_log(log_entry(1, :a))

    m = transmitter.mock(:send_message)
    node.on_request_vote term: 2, candidate_id: 2, last_log_index: 1, last_log_term: 0
    res = m.args[2]

    assert_equal false, res[:vote_granted]
  end

  def test_on_request_vote_fails_if_local_log_is_longer
    node.append_log(log_entry(0, :a))

    m = transmitter.mock(:send_message)

    node.on_request_vote term: 1, candidate_id: 1, last_log_index: 0, last_log_term: 0

    res = m.args[2]

    assert_equal false, res[:vote_granted]
  end

  ## on_install_snapshot

  def test_on_install_snapshot_reject_if_local_current_term_is_higher
    node.current_term = 2

    m = transmitter.mock(:send_message)

    node.on_install_snapshot term: 1, last_included_index: 129, last_included_term: 1,
                             data: { 'abc' => 1 }

    res = m.args[2]

    assert_equal false, res[:success]
    assert_equal 2, res[:term]
  end

  def test_on_install_snapshot_reset_state_machine_and_discard_log
    m = handler.mock('data='.to_sym)

    node.on_install_snapshot term: 1, last_included_index: 129, last_included_term: 1,
                             data: { 'abc' => 1 }

    assert_equal 1, m.times_called
    assert_equal 1, handler.last_included_term
    assert_equal 129, handler.last_included_index

    assert_equal [], node.log_entries
    assert_equal 129, node.last_applied
    assert_equal 129, node.last_commit
  end
end
