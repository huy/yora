require_relative 'filestore'

module Yora
  class Node
    def initialize(id, transmitter, handler, timer, store)
      @node_id = id
      @handler = handler
      @timer = timer
      @transmitter = transmitter

      @store = store
      @last_commit = 0
      @last_applied = 0
      @role = Follower.new(self, transmitter, timer)
    end

    attr_reader :node_id, :handler, :timer, :transmitter
    attr_accessor :role, :last_commit, :last_applied, :leader_id

    def dispatch(opts)
      case opts[:message_type].to_sym
      when :tick
        on_tick
      when :request_vote
        on_request_vote(opts)
      when :append_entries
        on_append_entries(opts)
      when :request_vote_resp
        on_request_vote_resp(opts)
      when :append_entries_resp
        on_append_entries_resp(opts)
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
        self.current_term = opts[:term]
        @role = Follower.new(self, transmitter, timer)
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

    ## handle rpc response

    def on_request_vote_resp(opts)
      on_rpc_request_or_response(opts)

      @role.on_request_vote_resp(opts)
    end

    def on_append_entries_resp(opts)
      on_rpc_request_or_response(opts)

      @role.on_append_entries_resp(opts)
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

    def log(index)
      @store[index]
    end

    def prev_log(index)
      prev_log_index = index - 1
      if prev_log_index >= 0 && prev_log_index <= last_log_index
        prev_log_term = log(prev_log_index).term
        return [prev_log_index, prev_log_term]
      end
      fail "invalid call prev_log of #{index}"
    end

    def last_log_term
      @store.last.term
    end

    def last_log_index
      @store.size - 1
    end

    def truncate_log(index)
      @store.truncate(index)
    end

    def append_log(*entry)
      @store.concat(entry)
    end

    def slice_log(range)
      @store.slice(range)
    end

    def current_term
      @store.current_term
    end

    def current_term=(term)
      @store.current_term = term
    end

    def voted_for
      @store.voted_for
    end

    def voted_for=(candidate_id)
      @store.voted_for = candidate_id
    end

    def cluster
      @store.cluster
    end

    def cluster=(value)
      @store.cluster = value
    end

    def leader_addr
      @store.cluster[@leader_id]
    end

    def reconfiguration_pending?
      if @store.slice(@last_commit + 1..-1).rindex(&:config?)
        true
      else
        false
      end
    end

    def save
      @store.save
    end
  end
end
