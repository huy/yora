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
      reply_to = cluster[opts[:peer]]

      if valid_vote_request?(opts)
        node.voted_for = opts[:candidate_id]

        node.save
        transmitter.send_message(reply_to, :request_vote_resp,
                                 term: current_term, vote_granted: true)
      else
        transmitter.send_message(reply_to, :request_vote_resp,
                                 term: current_term, vote_granted: false)
      end
    end

    def on_append_entries(opts)
      reply_to = cluster[opts[:peer]]

      @election_timeout = timer.next

      if (current_term > opts[:term]) || inconsistent_log?(opts)
        transmitter.send_message(reply_to, :append_entries_resp,
                                 success: false, term: current_term)
        return
      end

      unless opts[:entries].empty?
        node.leader_id = opts[:leader_id]

        accept_new_config_if_any(opts[:entries])

        log_container.replace_from(opts[:prev_log_index], opts[:entries])

        log_container.advance_commit_to(opts[:commit_index])

        log_container.apply_entries do |entry, _|
          node.handler.on_command(entry.command) unless entry.query?
        end

        node.save
      end

      transmitter.send_message(reply_to, :append_entries_resp,
                               success: true, term: current_term,
                               match_index: log_container.last_index)
    end

    def on_install_snapshot(opts)
      reply_to = cluster[opts[:peer]]

      if current_term > opts[:term]
        transmitter.send_message(reply_to, :install_snapshot_resp,
                                 success: false, term: current_term,
                                 match_index: log_container.last_index)
      else
        if include_log?(opts[:last_included_index], opts[:last_included_term])
          transmitter.send_message(reply_to, :install_snapshot_resp,
                                   success: true, term: current_term,
                                   match_index: log_container.last_index)
        else
          install_snapshot(opts)
          transmitter.send_message(reply_to, :install_snapshot_resp,
                                   success: true, term: current_term,
                                   match_index: log_container.last_index)
        end
      end
    end

    def on_request_vote_resp(_)
    end

    def on_install_snapshot_resp(_)
    end

    def inconsistent_log?(opts)
      !include_log?(opts[:prev_log_index], opts[:prev_log_term])
    end

    def include_log?(index, term)
      log_container.include?(index, term)
    end

    def valid_vote_request?(opts)
      return false if opts[:term] < current_term
      return false if node.voted_for && opts[:candidate_id] != node.voted_for

      return false if log_container.last_term > opts[:last_log_term]
      return false if log_container.last_index > opts[:last_log_index]

      true
    end

    def install_snapshot(snapshot)
      node.handler.data = snapshot[:data]
      node.log_container = LogContainer.new(
        snapshot[:last_included_index],
        snapshot[:last_included_term])
    end

    def accept_new_config_if_any(entries)
      index = entries.rindex(&:config?)
      node.cluster = entries[index].cluster if index
    end
  end
end
