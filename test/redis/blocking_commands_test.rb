# frozen_string_literal: true

require "helper"

class TestBlockingCommands < Minitest::Test
  include Helper::Client
  include Lint::BlockingCommands

  def assert_takes_longer_than_client_timeout
    timeout = LOW_TIMEOUT
    delay = timeout * 5

    mock(delay: delay) do |r|
      t1 = Time.now
      yield(r)
      t2 = Time.now

      assert_operator delay, :<=, (t2 - t1)
    end
  end

  def test_blmove_disable_client_timeout
    target_version "6.2" do
      assert_takes_longer_than_client_timeout do |r|
        assert_equal '0', r.blmove('foo', 'bar', 'LEFT', 'RIGHT')
      end
    end
  end

  def test_blpop_disable_client_timeout
    assert_takes_longer_than_client_timeout do |r|
      assert_equal %w[foo 0], r.blpop('foo')
    end
  end

  def test_brpop_disable_client_timeout
    assert_takes_longer_than_client_timeout do |r|
      assert_equal %w[foo 0], r.brpop('foo')
    end
  end

  def test_brpoplpush_disable_client_timeout
    assert_takes_longer_than_client_timeout do |r|
      assert_equal '0', r.brpoplpush('foo', 'bar')
    end
  end

  def test_brpoplpush_in_transaction
    # TODO: redis-client transactions don't support blocking calls.
    results = r.multi do |transaction|
      transaction.brpoplpush('foo', 'bar')
      transaction.brpoplpush('foo', 'bar', timeout: 2)
    end
    assert_equal [nil, nil], results
  end

  def test_brpoplpush_in_pipeline
    mock do |r|
      results = r.pipelined do |transaction|
        transaction.brpoplpush('foo', 'bar')
        transaction.brpoplpush('foo', 'bar', timeout: 2)
      end
      assert_equal ['0', '2'], results
    end
  end
end
