require 'test/unit'
require_relative 'test'

class TestLogEntry < Test::Unit::TestCase
  include Yora::Message

  def test_serialize_deserialize_log_entry
    opts = { entries: [Yora::LogEntry.new(0, 'hello', '127.0.0.1:7777')] }

    actual = deserialize(serialize(opts))
    entry = actual[:entries].first

    assert_equal 0, entry.term
    assert_equal 'hello', entry.command
    assert_equal '127.0.0.1:7777', entry.client
  end

  def test_serialize_deserialize_config_log_entry
    cluster = { '7' => '127.0.0.1:2357', '8' => '127.0.0.1:2358' }
    opts = { entries: [Yora::ConfigLogEntry.new(1, cluster)] }

    actual = deserialize(serialize(opts))
    entry = actual[:entries].first

    assert_equal 1, entry.term
    assert_equal cluster, entry.cluster
  end
end
