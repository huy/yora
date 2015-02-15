require 'test/unit'
require_relative 'test'

class TestLogContainer < Test::Unit::TestCase
  include Yora

  def log_entry(term, command)
    CommandLogEntry.new(term, command)
  end

  def test_empty
    log_container = LogContainer.new

    assert_equal 0, log_container.last_index
    assert_equal 1, log_container.first_index
    assert_equal 0, log_container.last_term
    assert_equal 0, log_container.last_commit
    assert_equal 0, log_container.last_applied
    assert_equal 0, log_container.last_applied_term

    assert_equal true, log_container.include?(0, 0)
    assert_equal false, log_container.include?(1, 0)

    assert_equal 0, log_container.term(0)
  end

  def test_append_same_term_entry
    log_container = LogContainer.new
    log_container.append(log_entry(0, :foo))

    assert_equal 1, log_container.last_index
    assert_equal 1, log_container.first_index
    assert_equal 0, log_container.last_term
    assert_equal 0, log_container.last_commit
    assert_equal 0, log_container.last_applied
    assert_equal 0, log_container.last_applied_term

    assert_equal true, log_container.include?(1, 0)

    assert_equal 0, log_container.term(0)
    assert_equal 0, log_container.term(1)
  end

  def test_append_new_term_entry
    log_container = LogContainer.new
    log_container.append(log_entry(1, :foo))

    assert_equal 1, log_container.last_index
    assert_equal 1, log_container.first_index
    assert_equal 1, log_container.last_term

    assert_equal true, log_container.include?(1, 1)

    assert_equal 0, log_container.term(0)
    assert_equal 1, log_container.term(1)
  end

  def test_get_from_empty
    log_container = LogContainer.new
    prev_index, prev_term, entries = log_container.get_from(1)

    assert_equal 0, prev_index
    assert_equal 0, prev_term
    assert_equal [], entries
  end

  def test_get_from_non_empty
    log_container = LogContainer.new
    log_container.append(log_entry(1, :foo))

    prev_index, prev_term, entries = log_container.get_from(1)

    assert_equal 0, prev_index
    assert_equal 0, prev_term
    assert_equal 1, entries.size
    assert_equal :foo, entries.first.command
    assert_equal 1, entries.first.term
  end

  def test_replace_from_empty
    log_container = LogContainer.new

    log_container.replace_from(0, [log_entry(1, :foo)])

    assert_equal 0, log_container.term(0)
    assert_equal 1, log_container.first_index
    assert_equal 1, log_container.last_index
    assert_equal 1, log_container.term(1)
  end

  def test_drop_util_last_applied
    log_container = LogContainer.new
    log_container.append(log_entry(1, :foo))

    assert_equal 1, log_container.first_index
    assert_equal 1, log_container.last_index

    assert_equal 0, log_container.last_commit
    assert_equal 0, log_container.last_applied

    log_container.last_commit = log_container.last_index
    log_container.last_applied = log_container.last_index

    assert_equal 1, log_container.last_commit
    assert_equal 1, log_container.last_applied

    log_container.drop_util_last_applied

    assert_equal 2, log_container.first_index
    assert_equal [], log_container.entries
  end
end
