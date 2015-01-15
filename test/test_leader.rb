require 'test/unit'
require_relative 'test'

class TestLeader < Test3Nodes
  def setup
    create_env
    node.role = Yora::Leader.new(node)

    [peer, other_peer].each do |p|
      node.on_append_entries_resp(peer: p,
                                  success: true,
                                  term: node.current_term,
                                  match_index: node.log_container.last_index)
    end
  end

  def test_reset_index
    node.role.next_indices[peer] = 0
    node.role.reset_index

    assert_equal node.log_container.last_index + 1, node.role.next_indices[peer]
  end

  ## broadcast_entries

  def test_broadcast_entries_calls_transmit
    node.log_container.append(log_entry(0, :foo))

    m = transmitter.mock(:send_message)
    node.role.broadcast_entries

    assert_equal [peer_addr, :append_entries], m.args_called[0][0, 2]
    assert_equal [other_peer_addr, :append_entries], m.args_called[1][0, 2]
  end

  def test_broadcast_entries_no_heartbeat_does_nothing_if_peers_up_to_date
    m = transmitter.mock(:send_message)
    node.role.broadcast_entries(false)

    assert_equal 0, m.times_called
  end

  def test_broadcast_entries_heartbeat_send_empty_if_peers_up_to_date
    m = transmitter.mock(:send_message)
    node.role.next_indices[peer] = node.log_container.last_index + 1
    node.role.next_indices[other_peer] = node.log_container.last_index + 1

    node.role.broadcast_entries(true)

    opts = {
      term: node.current_term,
      leader_id: node.node_id,
      prev_log_index: node.log_container.last_index,
      prev_log_term: node.current_term,
      entries: [],
      commit_index: node.log_container.last_commit
    }

    assert_equal [peer_addr, :append_entries, opts], m.args_called[0][0, 3]
    assert_equal [other_peer_addr, :append_entries, opts], m.args_called[1][0, 3]
  end

  def test_broadcast_entries_includes_data_about_previous_log_entry
    entries = [log_entry(0, :foo), log_entry(0, :bar)]

    node.log_container.append(*entries)
    m = transmitter.mock(:send_message)

    node.role.broadcast_entries

    opts = {
      term: node.current_term,
      leader_id: node.node_id,
      prev_log_index: 1,
      prev_log_term: 0,
      entries: entries,
      commit_index: node.log_container.last_commit
    }

    assert_equal [peer_addr, :append_entries, opts], m.args_called[0][0, 3]
    assert_equal [other_peer_addr, :append_entries, opts], m.args_called[1][0, 3]
  end

  def test_broadcast_entries_sends_to_all_peers
    other_peer = '2'
    @cluster[other_peer] = '127.0.0.1:2359'
    node.role.update_peer_index(other_peer, node.log_container.last_index)

    node.log_container.append(log_entry(0, :foo))

    m = transmitter.mock(:send_message)
    node.role.broadcast_entries(false)

    assert_equal 2, m.times_called

    opts = {
      term: node.current_term,
      leader_id: node.node_id,
      prev_log_index: 1,
      prev_log_term: 0,
      entries: [node.log_container[node.log_container.last_index]],
      commit_index: node.log_container.last_commit
    }

    assert_equal [peer_addr, :append_entries, opts], m.args_called[0][0, 3]
    assert_equal [other_peer_addr, :append_entries, opts], m.args_called[1][0, 3]
  end

  ## on_append_entries_resp

  def test_on_append_entries_resp_update_next_index_and_match_index_on_success
    @handler.mock(:on_command)

    node.on_append_entries_resp(peer: peer, term: 0, success: true, match_index: 1)

    assert_equal 2, node.role.next_indices[peer]
    assert_equal 1, node.role.match_indices[peer]
  end

  def test_on_append_entries_resp_decrement_next_index_and_retry_when_fail
    node.log_container.append(log_entry(0, :foo),
                    log_entry(0, :bar))

    node.role.next_indices[peer] = 2
    node.role.match_indices[peer] = 1

    m = transmitter.mock(:send_message)

    node.on_append_entries_resp(peer: peer, term: 0, success: false)

    assert_equal 1, node.role.next_indices[peer]
    assert_equal [peer_addr, :append_entries], m.args[0, 2]
  end

  def test_on_heartbeat_append_entries_resp_do_nothing
    peer_match_index = node.role.match_indices[peer]
    peer_next_index = node.role.next_indices[peer]

    node.on_append_entries_resp(peer: peer, term: 0, success: true,
                                match_index: node.role.match_indices[peer])

    assert_equal peer_match_index, node.role.match_indices[peer]
    assert_equal peer_next_index, node.role.next_indices[peer]
  end

  def test_on_append_entries_resp_advance_commit_and_apply_on_majority_success
    node.log_container.append(log_entry(0, :foo))

    node.on_append_entries_resp(peer: peer, term: 0, success: true,
                                match_index: node.log_container.last_index)

    assert_equal node.log_container.last_index, node.log_container.last_commit
    assert_equal node.log_container.last_index, node.log_container.last_applied
  end

  def test_on_append_entries_resp_become_follower_if_receive_higher_term
    node.on_append_entries_resp(peer: peer, term: 1, success: false,
                                match_index: node.log_container.last_index)

    assert_equal Yora::Follower, node.role.class
  end

  def test_on_append_entries_resp_send_snapshot_when_next_index_pass_first_index
    node.log_container.append(log_entry(0, :foo))

    node.log_container.snapshot_last_included_index = 129
    node.log_container.snapshot_last_included_term = 0

    node.role.next_indices[peer] = 130

    m = node.role.mock(:send_snapshot)

    node.on_append_entries_resp(peer: peer, term: 0, success: false)

    assert_equal 1, m.times_called
  end

  ## on_tick

  def test_on_tick_broadcast_entries_to_all_peers
    m = transmitter.mock(:send_message)
    node.on_tick

    assert_equal [peer_addr, :append_entries], m.args_called[0][0, 2]
    assert_equal [other_peer_addr, :append_entries], m.args_called[1][0, 2]
  end

  ## on_client_command

  def test_on_client_command_append_to_log
    node.on_client_command(command: :foo, client: '127.0.0.1:5555')

    assert_equal :foo, node.log_container[node.log_container.last_index].command
    assert_equal 0, node.log_container[node.log_container.last_index].term
  end

  def test_on_client_command_transmits_command
    m = node.role.mock(:broadcast_entries)

    node.on_client_command(command: :foo, client: '127.0.0.1:5555')

    assert_equal 1, m.times_called
  end

  def test_leave_command_rejected_on_reconfiguration_pending
    node.on_client_command(command: 'join',
                           peer: other_peer,
                           peer_address: '127.0.0.1:2359')

    m = transmitter.mock(:send_message)

    node.on_client_command(command: 'leave',
                           peer: peer)

    resp = m.args[2]
    assert_equal false, resp[:success]
    assert_equal '127.0.0.1:2358', resp[:cluster][peer]
  end

  def test_join_command_change_cluster_configuration
    new_peer = '4'
    node.on_client_command(command: 'join',
                           peer: new_peer,
                           peer_address: '127.0.0.1:2359')

    assert_equal '127.0.0.1:2359', node.cluster[new_peer]
    assert_equal true, node.log_container.reconfiguration_pending?

    node.log_container.last_commit = node.log_container.last_index
    assert_equal false, node.log_container.reconfiguration_pending?
  end

  def test_leave_command_change_cluster_configuration
    node.on_client_command(command: 'leave', peer: peer)

    assert_equal nil, node.cluster[peer]
    assert_equal node.cluster, node.log_container[node.log_container.last_index].cluster
  end

  ## advance_commit_index

  def test_commit_entries_does_nothing_when_no_majority
    node.log_container.append(log_entry(0, :foo),
                    log_entry(0, :bar))

    commit = node.log_container.last_commit

    node.role.commit_entries

    assert_equal commit, node.log_container.last_commit
  end

  def test_commit_entries_advance_to_the_one_before_last_log
    node.log_container.append(log_entry(0, :foo),
                    log_entry(0, :bar))

    node.role.match_indices[peer] = node.log_container.last_index - 1

    node.role.commit_entries

    assert_equal node.log_container.last_index - 1, node.log_container.last_commit
  end

  def test_commit_entries_advance_to_last_log
    node.log_container.append(log_entry(0, :foo),
                    log_entry(0, :bar))

    node.role.match_indices[other_peer] = node.log_container.last_index

    node.role.commit_entries

    assert_equal node.log_container.last_index, node.log_container.last_commit
  end
end
