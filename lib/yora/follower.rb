require_relative 'role'

module Yora
  class Follower
    include FollowerOrCandidate

    attr_reader :node, :transmitter, :election_timeout

    def initialize(node, transmitter, timer)
      @transmitter = transmitter
      @timer = timer

      @node = node

      @election_timeout = @timer.next
    end

    def on_request_vote_resp(_opts)
    end

    def on_request_vote(opts)
      reply_to = opts[:peer]

      if valid_vote_request?(opts)
        node.voted_for = opts[:candidate_id]
        node.current_term = opts[:term]

        transmitter.send_message(reply_to, :request_vote_resp,
                                 term: node.current_term, vote_granted: true)
      else
        transmitter.send_message(reply_to, :request_vote_resp,
                                 term: node.current_term, vote_granted: false)
      end
    end

    def on_append_entries(opts)
      reply_to = opts[:peer]
      current_term = node.current_term

      @election_timeout = @timer.next

      if inconsistent_log?(opts)
        transmitter.send_message(reply_to, :append_entries_resp,
                                 success: false, term: current_term)
        return
      end

      node.leader_id = opts[:leader_id]

      node.truncate_log(opts[:prev_log_index])

      node.append_log(*opts[:entries])

      config_entry_index = opts[:entries].rindex(&:config?)
      if config_entry_index
        node.cluster = opts[:entries][config_entry_index].cluster
      end

      node.last_commit = [opts[:commit_index], node.last_log_index].min

      node.save
      apply_entries

      transmitter.send_message(reply_to, :append_entries_resp,
                               success: true, term: current_term, match_index: node.last_log_index)
    end

    def inconsistent_log?(opts)
      return true if node.current_term > opts[:term]
      return true unless node.log(opts[:prev_log_index])
      return true if node.log(opts[:prev_log_index]).term != opts[:prev_log_term]

      false
    end

    def valid_vote_request?(opts)
      return false if opts[:term] < node.current_term
      return false if node.voted_for && opts[:candidate_id] != node.voted_for

      return false if node.last_log_term > opts[:last_log_term]
      return false if node.last_log_index > opts[:last_log_index]

      true
    end

    def apply_entries
      last_commit = node.last_commit
      (node.last_applied + 1).upto(last_commit).each do |i|
        entry = node.log(i)
        node.handler.on_command(entry.command) unless entry.config?
      end

      node.last_applied = last_commit
    end
  end
end
