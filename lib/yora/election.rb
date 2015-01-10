module Yora
  class Election
    attr_reader :total, :granted_votes, :majority

    def initialize(total)
      @total = total
      @majority = (total / 2) + 1
      @votes = {}
    end

    def votes
      @votes.size
    end

    def inspect
      @votes.inspect
    end

    def granted_votes
      @votes.values.inject(0) { |a, e| a + (e[:vote_granted] ? 1 : 0) }
    end

    def won?
      granted_votes >= @majority
    end

    def receive_vote(node, opts)
      @votes[node] ||= opts
    end
  end
end
