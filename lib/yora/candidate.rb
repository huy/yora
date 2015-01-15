require_relative 'role'

module Yora
  class Candidate
    include AnyRoles
    include CandidateOrLeader
    include FollowerOrCandidate

    attr_reader :node, :election, :election_timeout

    def initialize(node)
      @node = node

      @election = Election.new(node.cluster.size)
      @election_timeout = timer.next

      node.next_term

      broadcast_vote_request
    end

    def on_request_vote_resp(opts)
      update_election(opts)
    end

    def on_append_entries(opts)
      reply_to = node.cluster[opts[:peer]]
      if node.current_term > opts[:term]
        transmitter.send_message(reply_to, :append_entries_resp,
                                 success: false, term: node.current_term)
      else
        node.role = Follower.new(node)
        node.on_append_entries(opts)
      end
    end

    def on_install_snapshot(_)
    end

    def on_install_snapshot_resp(_)
    end

    def broadcast_vote_request
      peers.each do |peer|
        opts = {
          term: node.current_term,
          candidate_id: node.node_id,
          last_log_index: node.log_container.last_index,
          last_log_term: node.log_container.last_term
        }

        transmitter.send_message(node.cluster[peer], :request_vote, opts)
      end
    end

    def update_election(opts)
      election.receive_vote(opts[:peer], opts)
      node.role = Leader.new(node) if election.won?
    end
  end
end
