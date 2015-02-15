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
        #$stderr.puts "-- reject vote request #{opts}, "\
        #  "last_log_term = #{log_container.last_term}, last_log_index = #{log_container.last_index}"

        transmitter.send_message(reply_to, :request_vote_resp,
                                 term: current_term, vote_granted: false)
      end
    end

    def on_append_entries(opts)
      reply_to = cluster[opts[:peer]]

      @election_timeout = timer.next

      if (current_term > opts[:term]) || inconsistent_log?(opts)

        #$stderr.puts "-- reject append entries term = #{opts[:term]}, "\
        #  "prev_log_term = #{opts[:prev_log_term]}, prev_log_index = #{opts[:prev_log_index]},"
        transmitter.send_message(reply_to, :append_entries_resp,
                                 success: false, term: current_term)
        return
      end

      if (not opts[:entries].empty?) or (opts[:commit_index] > log_container.last_commit)
        node.leader_id = opts[:leader_id]

        accept_new_config_if_any(opts[:entries])
        accept_new_command(opts[:entries])

        log_container.replace_from(opts[:prev_log_index], opts[:entries])

        log_container.advance_commit_to(opts[:commit_index])

        log_container.apply_entries do |entry, _|
          handler.on_command(entry.command) unless entry.query?
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
        if log_container.include?(opts[:last_included_index], opts[:last_included_term])
          transmitter.send_message(reply_to, :install_snapshot_resp,
                                   success: true, term: current_term,
                                   match_index: log_container.last_index)
        else
          node.leader_id = opts[:leader_id]
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
      not log_container.include?(opts[:prev_log_index], opts[:prev_log_term])
    end

    def valid_vote_request?(opts)
      return false if opts[:term] < current_term
      return false if node.voted_for && opts[:candidate_id] != node.voted_for

      return false if log_container.last_term > opts[:last_log_term]
      return false if log_container.last_index > opts[:last_log_index]

      true
    end

    def install_snapshot(snapshot)
      handler.data = snapshot[:data]

      node.log_container = LogContainer.new(
        snapshot[:last_included_index],
        snapshot[:last_included_term])

      node.save_snapshot
    end

    def accept_new_config_if_any(entries)
      index = entries.rindex(&:config?)
      node.cluster = entries[index].cluster if index
    end

    def accept_new_command(entries)
      entries.each do |entry|
        if entry.command? && handler.respond_to?(:pre_command) && entry.command
          handler.pre_command(entry.command)
        end
      end
    end
  end
end
