module Yora
  MAX_LOG_ENTRIES_SENT = 16

  module AnyRoles
    def timer
      node.timer
    end

    def transmitter
      node.transmitter
    end

    def persistence
      node.persistence
    end
  end

  module CandidateOrLeader
    def peers
      node.cluster.keys.select { |peer| peer != node.node_id }
    end

    def on_request_vote(_)
    end
  end

  module FollowerOrCandidate
    def on_append_entries_resp(_)
    end

    def on_tick
      if election_timeout && Time.now > election_timeout
        node.role = Candidate.new(node)
        node.role.update_election(peer: node.node_id, term: node.current_term, vote_granted: true)
      end
    end

    def on_client_command(opts)
      redirect_to_leader(opts[:client])
    end

    def on_client_query(opts)
      client = opts[:client]
      case opts[:query].to_sym
      when :leader
        transmitter.send_message(client, :query_resp,
                                 success: true,
                                 leader_id: node.leader_id,
                                 leader_addr: node.leader_addr)
      else
        redirect_to_leader(client)
      end
    end

    def redirect_to_leader(client)
      transmitter.send_message(client, :command, redirect_to: node.leader_addr)
    end

    def seconds_until_timeout
      (election_timeout - Time.now).to_i
    end
  end
end
