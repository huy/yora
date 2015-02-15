module Yora
  class LogContainer
    MAX_ENTRIES = 128
    MAX_PER_RPC = 16

    attr_reader :entries
    attr_accessor :last_commit, :last_applied
    attr_accessor :snapshot_last_included_index, :snapshot_last_included_term

    def initialize(snapshot_last_included_index = 0, snapshot_last_included_term = 0, entries = [])
      @snapshot_last_included_index = snapshot_last_included_index
      @snapshot_last_included_term = snapshot_last_included_term
      @last_commit =  snapshot_last_included_index
      @last_applied = snapshot_last_included_index

      @entries = entries
    end

    def first_index
      @snapshot_last_included_index + 1
    end

    def last_index
      first_index + @entries.size - 1
    end

    def [](index)
      @entries[index - first_index]
    end

    def term(index)
      return self[index].term if index >= first_index
      return @snapshot_last_included_term if index == first_index - 1

      fail "invalid call term of #{index}"
    end

    def last_term
      if @entries.empty?
        @snapshot_last_included_term
      else
        @entries.last.term
      end
    end

    def last_applied_term
      term(last_applied)
    end

    def truncate(index)
      from = (index - first_index + 1)
      @entries[from..-1] = []
    end

    def append(*entry)
      @entries.concat(entry)
    end

    def drop_util_last_applied
      @snapshot_last_included_term = term(last_applied)

      @entries = @entries.drop(last_applied - first_index + 1)

      @snapshot_last_included_index = last_applied
    end

    def slice(range)
      @entries.slice((range.first - first_index)..(range.last - first_index))
    end

    def reconfiguration_pending?
      return true if last_index.downto(last_commit + 1).find { |i| self[i].config? }
      false
    end

    def config
      last_index.downto(first_index).each do |i|
        return self[i] if self[i].config?
      end
      nil
    end

    def max_entries
      MAX_ENTRIES
    end

    def exceed_limit?
      (last_applied - first_index + 1) > max_entries
    end

    def apply_entries
      return if last_commit <= last_applied

      (last_applied + 1).upto(last_commit).each do |i|
        entry = self[i]
        next if entry.config? || entry.noop?

        @last_applied = i

        yield entry, i if block_given?
      end
    end

    def include?(index, term)
      index <= last_index && term(index) == term
    end

    def replace_from(index, entries)
      truncate(index)
      append(*entries)
    end

    def advance_commit_to(commit_index)
      @last_commit = [commit_index, last_index].min

      @last_commit == commit_index
    end

    def get_from(index)
      if last_index >= index
        prev_log_index = index - 1
        prev_log_term = term(prev_log_index)

        if last_index - index > (MAX_PER_RPC - 1)
          send_up_to = index + MAX_PER_RPC - 1
        else
          send_up_to = last_index
        end
        [prev_log_index, prev_log_term, slice(index..send_up_to)]
      else
        [last_index, last_term, []]
      end
    end
  end
end
