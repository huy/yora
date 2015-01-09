require_relative 'role'

module Yora
  class Candidate
    include CandidateOrLeader
    include FollowerOrCandidate

    attr_reader :node, :election, :transmitter, :election_timeout

    def initialize(node, transmitter, timer)
      @transmitter = transmitter
      @timer = timer
      @node = node

      @election = Election.new(node.cluster.size)
      @election_timeout = @timer.next

      node.current_term = node.current_term + 1
      broadcast_vote_request
    end

    def on_request_vote_resp(opts)
      update_election(opts)
    end

    def on_append_entries(opts)
      reply_to = node.cluster[opts[:peer]]
      if node.current_term > opts[:term]
        node.save
        transmitter.send_message(reply_to, :append_entries_resp,
                                 success: false, term: node.current_term)
      else
        node.role = Follower.new(node, node.transmitter, node.timer)
        node.on_append_entries(opts)
      end
    end

    def broadcast_vote_request
      peers.each do |peer|
        last_log_index = node.last_log_index
        last_log_term = node.last_log_term

        opts = {
          term: node.current_term,
          candidate_id: node.node_id,
          last_log_index: last_log_index,
          last_log_term: last_log_term
        }

        transmitter.send_message(node.cluster[peer], :request_vote, opts)
      end
    end

    def update_election(opts)
      election.receive_vote(opts[:peer], opts)
      node.role = Leader.new(node, node.transmitter) if election.won?
    end
  end
end
