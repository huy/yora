require_relative 'role'

module Yora
  class Follower
    include AnyRoles
    include FollowerOrCandidate

    attr_reader :node, :election_timeout

    def initialize(node)
      @node = node
      @election_timeout = timer.next
    end

    def on_request_vote(opts)
      reply_to = node.cluster[opts[:peer]]

      if valid_vote_request?(opts)
        node.voted_for = opts[:candidate_id]

        node.save
        transmitter.send_message(reply_to, :request_vote_resp,
                                 term: node.current_term, vote_granted: true)
      else
        transmitter.send_message(reply_to, :request_vote_resp,
                                 term: node.current_term, vote_granted: false)
      end
    end

    def on_append_entries(opts)
      reply_to = node.cluster[opts[:peer]]
      current_term = node.current_term

      @election_timeout = timer.next

      if inconsistent_log?(opts)
        transmitter.send_message(reply_to, :append_entries_resp,
                                 success: false, term: current_term)
        return
      end

      unless opts[:entries].empty?
        node.leader_id = opts[:leader_id]

        node.truncate_log(opts[:prev_log_index])

        node.append_log(*opts[:entries])

        config_location = opts[:entries].rindex(&:config?)

        node.cluster = opts[:entries][config_location].cluster if config_location

        node.last_commit = [opts[:commit_index], node.last_log_index].min

        apply_entries

        node.save
      end

      transmitter.send_message(reply_to, :append_entries_resp,
                               success: true, term: current_term, match_index: node.last_log_index)
    end

    def on_install_snapshot(opts)
      reply_to = node.cluster[opts[:peer]]

      if node.current_term > opts[:term]
        transmitter.send_message(reply_to, :install_snapshot_resp,
                                 success: false, term: node.current_term,
                                 match_index: node.last_log_index)
      else
        if include_log?(opts[:last_included_index], opts[:last_included_term])
          transmitter.send_message(reply_to, :install_snapshot_resp,
                                   success: true, term: node.current_term,
                                   match_index: node.last_log_index)
        else
          install_snapshot(opts)
          transmitter.send_message(reply_to, :install_snapshot_resp,
                                   success: true, term: node.current_term,
                                   match_index: node.last_log_index)
        end
      end
    end

    def on_request_vote_resp(_)
    end

    def on_install_snapshot_resp(_)
    end

    def inconsistent_log?(opts)
      return true if node.current_term > opts[:term]
      return true if opts[:prev_log_index] > node.last_log_index
      return true if node.log_term(opts[:prev_log_index]) != opts[:prev_log_term]
    end

    def include_log?(index, term)
      node.last_log_index >= index &&  node.log_term(index) == term
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

      return if last_commit <= node.last_applied

      (node.last_applied + 1).upto(last_commit).each do |i|
        entry = node.log(i)
        node.handler.on_command(entry.command) unless entry.config?
      end

      node.last_applied = last_commit
    end

    def install_snapshot(snapshot)
      node.handler.data = snapshot[:data]
      node.handler.last_included_index = snapshot[:last_included_index]
      node.handler.last_included_term = snapshot[:last_included_term]

      node.truncate_log(snapshot[:last_included_index])
      node.last_commit = snapshot[:last_included_index]
      node.last_applied = snapshot[:last_included_index]
    end
  end
end
