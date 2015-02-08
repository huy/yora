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

      snapshot = @persistence.read_snapshot
      entries = @persistence.read_log_entries

      @log_container = LogContainer.new(
        snapshot[:last_included_index],
        snapshot[:last_included_term],
        entries)

      config = @log_container.config

      @cluster = config.cluster if config

      @role = Follower.new(self)
    end

    attr_reader :node_id, :handler, :timer, :transmitter, :current_term, :persistence
    attr_accessor :role, :leader_id, :voted_for, :cluster, :log_container

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

    def leader_addr
      @cluster[@leader_id]
    end

    def next_term
      @current_term += 1
    end

    def last_commit
      @log_container.last_commit
    end

    def save
      if @log_container.exceed_limit?

        last_included_index = log_container.last_applied
        last_included_term = log_container.last_applied_term

        @persistence.save_snapshot(
          last_included_index: last_included_index,
          last_included_term: last_included_term,
          data: @handler.take_snapshot
        )

        @log_container.drop_util_last_applied
      end

      @persistence.save_log_entries(@log_container.entries)
      @persistence.save_metadata(@current_term, @voted_for, @cluster)
    end
  end
end
