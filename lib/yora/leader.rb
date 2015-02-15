require_relative 'role'

module Yora
  class Leader
    include AnyRoles
    include CandidateOrLeader

    attr_reader :node, :next_indices, :match_indices

    def initialize(node)
      @node = node
      @match_indices = Hash[peers.map { |peer| [peer, 0] }]
      node.leader_id = node_id

      reset_index
      append_noop_entry

      if cluster.size == 1
        commit_entries
      else
        broadcast_entries(true)
      end
    end

    def leader?
      true
    end

    def on_append_entries(_)
    end

    def on_request_vote_resp(_)
    end

    def on_append_entries_resp(opts)
      peer = opts[:peer]
      if opts[:success]

        update_peer_index(peer, opts[:match_index])

        commit_entries

        send_entries(peer) if match_indices[peer] < log_container.last_index

      else
        decrement_next_index(peer)
        if next_indices[peer] >= log_container.first_index
          send_entries(peer)
        else
          send_snapshot(peer)
        end
      end
    end

    def on_install_snapshot(_)
    end

    def on_install_snapshot_resp(opts)
      on_append_entries_resp(opts)
    end

    def on_client_command(opts)
      if opts[:command] == 'join' || opts[:command] == 'leave'
        on_config_command(opts)
      else
        on_non_config_command(opts)
      end

      commit_entries if cluster.size == 1
    end

    def on_client_query(opts)
      client = opts[:client]
      case opts[:query].to_sym
      when :leader
        transmitter.send_message(client, :query_resp,
                                 success: true,
                                 leader_id: node_id,
                                 leader_addr: cluster[node_id])
      else
        entry = QueryLogEntry.new(current_term, opts[:query], opts[:client])
        log_container.append(entry)

        broadcast_entries(false)
      end
    end

    def on_tick
      broadcast_entries(true)
    end

    def on_non_config_command(opts)
      entry = CommandLogEntry.new(current_term, opts[:command], opts[:client])
      log_container.append(entry)

      broadcast_entries(false)
    end

    def on_config_command(opts)
      if log_container.reconfiguration_pending?
        transmitter.send_message(opts[:client], :command_resp,
                                 success: false,
                                 cluster: cluster,
                                 commit_index: log_container.last_commit,
                                 last_index: log_container.last_index)
        return
      end

      case opts[:command]
      when 'join'
        on_node_join(opts)
      when 'leave'
        on_node_leave(opts)
      end
    end

    def on_node_join(opts)
      peer = opts[:peer]
      peer_address = opts[:peer_address]

      node.cluster = cluster.merge(peer => peer_address)
      match_indices[peer] = 0
      next_indices[peer] = 1

      entry = ConfigLogEntry.new(current_term, cluster)

      # $stderr.puts "-- new node #{peer},#{peer_address} join cluster #{cluster}"

      transmitter.send_message(opts[:client], :command_resp,
                               success: true,
                               cluster: cluster)

      log_container.append(entry)

      broadcast_entries(false)
    end

    def on_node_leave(opts)
      peer = opts[:peer]

      cluster.delete(peer)
      next_indices.delete(peer)
      match_indices.delete(peer)

      # $stderr.puts "-- node #{peer},#{peer_address} left cluster #{cluster}"

      entry = ConfigLogEntry.new(current_term, cluster)

      transmitter.send_message(opts[:client], :command_resp,
                               success: true,
                               cluster: cluster)

      log_container.append(entry)
      broadcast_entries(false)
    end

    def append_noop_entry
      entry = CommandLogEntry.new(current_term)
      log_container.append(entry)
    end

    def reset_index
      @next_indices = Hash[peers.map { |peer| [peer, log_container.last_index + 1] }]
    end

    def broadcast_entries(heartbeat = false)
      peers.each do |peer|
        if next_indices[peer] >= log_container.first_index
          send_entries(peer, heartbeat)
        else
          send_snapshot(peer)
        end
      end
    end

    def send_entries(peer, heartbeat = false)
      prev_log_index, prev_log_term, entries = log_container.get_from(next_indices[peer])

      if (!entries.empty?) || heartbeat
        opts = {
          term: current_term,
          leader_id: node_id,
          prev_log_index: prev_log_index,
          prev_log_term: prev_log_term,
          entries: entries,
          commit_index: log_container.last_commit
        }
        transmitter.send_message(cluster[peer], :append_entries, opts)
      end
    end

    def send_snapshot(peer)
      snapshot = persistence.read_snapshot

      transmitter.send_message(cluster[peer], :install_snapshot,
                               term: current_term,
                               leader_id: node_id,
                               last_included_index: snapshot[:last_included_index],
                               last_included_term: snapshot[:last_included_term],
                               data: snapshot[:data]
      )
    end

    def update_peer_index(peer, match_index)
      match_indices[peer] = match_index if match_indices[peer] < match_index
      next_indices[peer] = match_index + 1
    end

    def decrement_next_index(peer)
      next_indices[peer] -= 1 unless next_indices[peer] == 1
    end

    def commit_entries
      new_commit = ReplicaCounter.new(log_container,
                                      match_indices, current_term).majority_agreed_commit

      if new_commit > log_container.last_commit
        log_container.last_commit = new_commit

        apply_entries

        node.save
      end
    end

    def apply_entries
      log_container.apply_entries do |entry, index|
        if entry.query?
          response = handler.on_query(entry.query)
        else
          response = handler.on_command(entry.command)
        end
        response[:applied_index] = index

        handler.post_command(entry.command) if handler.respond_to?(:post_command)

        transmitter.send_message(entry.client, :command_resp, response)
      end
    end

    def seconds_until_timeout
      0
    end
  end
end
