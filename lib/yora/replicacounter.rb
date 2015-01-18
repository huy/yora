module Yora
  class ReplicaCounter
    attr_reader :log_container, :match_indices, :current_term

    def initialize(log_container, match_indices, current_term)
      @log_container = log_container
      @match_indices = match_indices
      @current_term = current_term
    end

    def majority_agreed_commit
      current_commit = log_container.last_commit

      current_term_match_indices = match_indices.values.map do |match_index|
        match_index.downto(current_commit).find do |i|
          log_container.term(i) == current_term
        end || current_commit
      end

      current_term_match_indices << log_container.last_index

      sorted = current_term_match_indices.sort

      middle = sorted.size >> 1
      middle -= 1 if sorted.size & 1 == 0

      sorted[middle]
    end
  end
end
