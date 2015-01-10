require_relative 'test'

class TestElection < Test::Unit::TestCase
  def setup
    @e = Yora::Election.new(3)
  end

  attr_reader :e

  def test_receive_vote_when_granted
    e.receive_vote 1, term: 0, vote_granted: true

    assert_equal 1, e.votes
  end

  def test_receive_vote_sets_majority_when_detected
    assert !e.won?

    e.receive_vote 1, term: 0, vote_granted: true
    e.receive_vote 2, term: 0, vote_granted: true

    assert e.won?
  end

  def test_receive_vote_changes_granted_votes
    assert_equal 0, e.granted_votes

    e.receive_vote 1, term: 0, vote_granted: true
    assert_equal 1, e.granted_votes

    e.receive_vote 2, term: 0, vote_granted: true
    assert_equal 2, e.granted_votes
  end

  def test_receive_vote_from_same_node
    e.receive_vote 1, term: 0, vote_granted: true
    e.receive_vote 1, term: 0, vote_granted: true

    assert_equal 1, e.votes
  end

  def test_receive_vote_from_same_node_different_grants
    e.receive_vote 1, term: 0, vote_granted: true
    e.receive_vote 1, term: 0, vote_granted: false

    assert_equal 1, e.votes
  end

  def test_receive_vote_from_same_node_different_grants_doesnt_change_vote
    e.receive_vote 1, term: 0, vote_granted: true
    e.receive_vote 1, term: 0, vote_granted: false

    assert_equal 1, e.granted_votes
  end
end
