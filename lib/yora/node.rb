module Yora
  class Node
    MAX_LOG_ENTRIES = 128

    def initialize(id, transmitter, handler, timer, persistence)
      @node_id = id

      @handler = handler
      @timer = timer
      @transmitter = transmitter
      @persistence = persistence

      metadata = @persistence.read_metadata
      @current_term = metadata[:current_term]
      @voted_for = metadata[:voted_for]
      @cluster = metadata[:cluster]

      @log_entries = @persistence.read_log_entries

      @log_entries.each do |entry|
        @cluster = entry.cluster if entry.config?
      end

      @last_commit = handler.last_included_index
      @last_applied = handler.last_included_index

      @role = Follower.new(self)
    end

    attr_reader :node_id, :handler, :timer, :transmitter, :current_term, :persistence
    attr_accessor :role, :last_commit, :last_applied, :leader_id
    attr_accessor :voted_for, :cluster

    def dispatch(opts)
      case opts[:message_type].to_sym
      when :tick
        on_tick
      when :append_entries
        on_append_entries(opts)
      when :append_entries_resp
        on_append_entries_resp(opts)
      when :request_vote
        on_request_vote(opts)
      when :request_vote_resp
        on_request_vote_resp(opts)
      when :install_snapshot
        on_install_snapshot(opts)
      when :install_snapshot_resp
        on_install_snapshot_resp(opts)
      when :command
        on_client_command(opts)
      when :query
        on_client_query(opts)
      else
        $stderr.puts "don't known how to dispatch message #{opts[:message_type]}"
      end
    end

    def on_rpc_request_or_response(opts)
      if opts[:term] > current_term
        @current_term = opts[:term]
        @role = Follower.new(self)
      end
    end

    ## handle rpc request

    def on_request_vote(opts)
      on_rpc_request_or_response(opts)
      @role.on_request_vote(opts)
    end

    def on_append_entries(opts)
      on_rpc_request_or_response(opts)
      @role.on_append_entries(opts)
    end

    def on_install_snapshot(opts)
      on_rpc_request_or_response(opts)
      @role.on_install_snapshot(opts)
    end

    ## handle rpc response

    def on_request_vote_resp(opts)
      on_rpc_request_or_response(opts)
      @role.on_request_vote_resp(opts)
    end

    def on_append_entries_resp(opts)
      on_rpc_request_or_response(opts)
      @role.on_append_entries_resp(opts)
    end

    def on_install_snapshot_resp(opts)
      on_rpc_request_or_response(opts)
      @role.on_install_snapshot_resp(opts)
    end

    ## handle client command

    def on_client_command(opts)
      @role.on_client_command(opts)
    end

    def on_client_query(opts)
      @role.on_client_query(opts)
    end

    ## handle timeout event

    def on_tick
      @role.on_tick
    end

    ## utilities methods

    def seconds_until_timeout
      @role.seconds_until_timeout
    end

    def first_log_index
      handler.last_included_index + 1
    end

    def last_log_index
      first_log_index + @log_entries.size - 1
    end

    def log(index)
      @log_entries[index - first_log_index]
    end

    def log_term(index)
      return log(index).term if index >= first_log_index
      return @handler.last_included_term if index == first_log_index - 1

      fail "invalid call log_term of #{index}"
    end

    def last_log_term
      if @log_entries.empty?
        @handler.last_included_term
      else
        @log_entries.last.term
      end
    end

    def truncate_log(index)
      from = (index - first_log_index + 1)
      @log_entries[from..-1] = []
    end

    def append_log(*entry)
      @log_entries.concat(entry)
    end

    def slice_log(range)
      @log_entries.slice((range.first - first_log_index)..(range.last - first_log_index))
    end

    def leader_addr
      @cluster[@leader_id]
    end

    def next_term
      @current_term += 1
    end

    def reconfiguration_pending?
      return true if last_log_index.downto(last_commit + 1).find { |i| log(i).config? }
      false
    end

    def max_log_entries
      MAX_LOG_ENTRIES
    end

    def log_exceed_limit?
      (@last_applied - first_log_index + 1) > max_log_entries
    end

    def save
      if log_exceed_limit?
        last_included_index = @last_applied
        last_included_term = log_term(@last_applied)

        @persistence.save_snapshot(
          last_included_index: last_included_index,
          last_included_term: last_included_term,
          data: @handler.take_snapshot
        )

        @log_entries = @log_entries.drop(@last_applied - first_log_index + 1)

        @handler.last_included_index = last_included_index
        @handler.last_included_term = last_included_term
      end

      @persistence.save_log_entries(@log_entries)
      @persistence.save_metadata(@current_term, @voted_for, @cluster)
    end
  end
end
