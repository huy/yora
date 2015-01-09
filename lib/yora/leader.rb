require_relative 'role'

module Yora
  class Leader
    include CandidateOrLeader

    attr_reader :node, :transmitter, :next_indices, :match_indices

    def initialize(node, transmitter)
      @transmitter = transmitter
      @node = node
      @match_indices = Hash[peers.map { |peer| [peer, 0] }]
      node.leader_id = node.node_id

      reset_index
      append_noop_entry

      if node.cluster.size == 1
        commit_entries
      else
        broadcast_entries(true)
      end
    end

    def on_append_entries(_opts)
    end

    def on_request_vote_resp(_opts)
    end

    def on_append_entries_resp(opts)
      peer = opts[:peer]
      if opts[:success]

        update_peer_index(peer, opts[:match_index])

        commit_entries

        send_entries(peer) if match_indices[peer] < node.last_log_index

      else
        decrement_next_index(peer)
        send_entries(peer)
      end
    end

    def on_client_command(opts)
      if opts[:command] == 'join' || opts[:command] == 'leave'
        on_config_command(opts)
      else
        on_non_config_command(opts)
      end

      commit_entries if node.cluster.size == 1
    end

    def on_client_query(opts)
      client = opts[:client]
      case opts[:query].to_sym
      when :leader
        transmitter.send_message(client, :query_resp,
                                 success: true,
                                 leader_id: node.node_id,
                                 leader_addr: node.cluster[node.node_id])
      else
        response = node.handler.on_query(opts[:query])
        transmitter.send_message(client, :query_resp, response)
      end
    end

    def on_tick
      broadcast_entries(true)
    end

    def on_non_config_command(opts)
      entry = LogEntry.new(node.current_term, opts[:command], opts[:client])
      node.append_log(entry)

      broadcast_entries(false)
    end

    def on_config_command(opts)
      if node.reconfiguration_pending?
        transmitter.send_message(opts[:client], :command_resp,
                                 success: false,
                                 cluster: node.cluster,
                                 commit_index: node.last_commit,
                                 last_index: node.last_log_index)
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

      node.cluster = node.cluster.merge(peer => peer_address)
      match_indices[peer] = 0
      next_indices[peer] = 1

      entry = ConfigLogEntry.new(node.current_term, node.cluster)

      # $stderr.puts "-- new node #{peer},#{peer_address} join cluster #{node.cluster}"

      transmitter.send_message(opts[:client], :command_resp,
                               success: true,
                               cluster: node.cluster)

      node.append_log(entry)
      broadcast_entries(false)
    end

    def on_node_leave(opts)
      peer = opts[:peer]

      node.cluster.delete(peer)
      next_indices.delete(peer)
      match_indices.delete(peer)

      # $stderr.puts "-- node #{peer},#{peer_address} left cluster #{node.cluster}"

      entry = ConfigLogEntry.new(node.current_term, node.cluster)

      transmitter.send_message(opts[:client], :command_resp,
                               success: true,
                               cluster: node.cluster)

      node.append_log(entry)
      broadcast_entries(false)
    end

    def append_noop_entry
      entry = LogEntry.new(node.current_term)
      node.append_log(entry)
    end

    def reset_index
      @next_indices = Hash[peers.map { |peer| [peer, node.last_log_index + 1] }]
    end

    def broadcast_entries(heartbeat = false)
      peers.each do |peer|
        send_entries(peer, heartbeat)
      end
    end

    def send_entries(peer, heartbeat = false)
      last_log_index = node.last_log_index

      if last_log_index >= next_indices[peer]
        prev_log_index = next_indices[peer] - 1
        prev_log_term = node.log_term(prev_log_index)

        if last_log_index - next_indices[peer] > (MAX_LOG_ENTRIES_SENT - 1)
          send_up_to = next_indices[peer] + MAX_LOG_ENTRIES_SENT - 1
        else
          send_up_to = last_log_index
        end

        opts = {
          term: node.current_term,
          leader_id: node.node_id,
          prev_log_index: prev_log_index,
          prev_log_term: prev_log_term,
          entries: node.slice_log(next_indices[peer]..send_up_to),
          commit_index: node.last_commit
        }
        transmitter.send_message(node.cluster[peer], :append_entries, opts)

      elsif heartbeat
        last_log_index = node.last_log_index
        last_log_term = node.last_log_term
        opts = {
          term: node.current_term,
          leader_id: node.node_id,
          prev_log_index: last_log_index,
          prev_log_term: last_log_term,
          entries: [],
          commit_index: node.last_commit
        }
        transmitter.send_message(node.cluster[peer], :append_entries, opts)
      end
    end

    def update_peer_index(peer, match_index)
      match_indices[peer] = match_index if match_indices[peer] < match_index
      next_indices[peer] = match_index + 1
    end

    def decrement_next_index(peer)
      next_indices[peer] -= 1 unless next_indices[peer] == 1
    end

    def commit_entries
      current_commit = node.last_commit
      current_term = node.current_term

      current_term_match_indices = match_indices.values.map do |match_index|
        match_index.downto(current_commit).find do
          |i| node.log_term(i) == current_term
        end || current_commit
      end

      current_term_match_indices << node.last_log_index

      sorted = current_term_match_indices.sort

      middle = sorted.size >> 1
      middle -= 1 if sorted.size & 1 == 0

      majority_agreed_index = sorted[middle]

      if majority_agreed_index > current_commit
        node.last_commit = majority_agreed_index

        node.save
        apply_entries
      end
    end

    def apply_entries
      last_commit = node.last_commit
      (node.last_applied + 1).upto(last_commit).each do |i|
        entry = node.log(i)
        next if entry.config? || entry.noop?
        # $stderr.puts "-- apply #{i} #{entry.to_json}"

        response = node.handler.on_command(entry.command, i, entry.term)

        response[:commit_index] = last_commit
        response[:applied_index] = i

        transmitter.send_message(entry.client, :command_resp, response)
      end

      node.last_applied = last_commit
    end

    def seconds_until_timeout
      0
    end
  end
end
