# frozen_string_literal: true

require "helper"

class TestTransactions < Minitest::Test
  include Helper::Client

  def test_multi_discard
    assert_raises(LocalJumpError) do
      r.multi
    end
  end

  def test_multi_exec_with_a_block
    r.multi do |multi|
      multi.set "foo", "s1"
    end

    assert_equal "s1", r.get("foo")
  end

  def test_multi_exec_with_a_block_doesn_t_return_replies_for_multi_and_exec
    r1, r2, nothing_else = r.multi do |multi|
      multi.set "foo", "s1"
      multi.get "foo"
    end

    assert_equal "OK", r1
    assert_equal "s1", r2
    assert_nil nothing_else
  end

  def test_multi_in_pipeline
    foo_future = bar_future = nil
    multi_future = nil
    response = r.pipelined do |pipeline|
      multi_future = pipeline.multi do |multi|
        multi.set("foo", "s1")
        foo_future = multi.get("foo")
      end

      pipeline.multi do |multi|
        multi.set("bar", "s2")
        bar_future = multi.get("bar")
      end
    end

    assert_equal(["OK", "QUEUED", "QUEUED", ["OK", "s1"], "OK", "QUEUED", "QUEUED", ["OK", "s2"]], response)

    assert_equal ["OK", "s1"], multi_future.value

    assert_equal "s1", foo_future.value
    assert_equal "s2", bar_future.value
  end

  def test_assignment_inside_multi_exec_block
    r.multi do |m|
      @first = m.sadd("foo", 1)
      @second = m.sadd("foo", 1)
    end

    assert_equal true, @first.value
    assert_equal false, @second.value
  end

  def test_assignment_inside_multi_exec_block_with_delayed_command_errors
    assert_raises(Redis::CommandError) do
      r.multi do |m|
        @first = m.set("foo", "s1")
        @second = m.incr("foo") # not an integer
      end
    end

    assert_equal "OK", @first.value
    assert_raises(Redis::FutureNotReady) { @second.value }
  end

  def test_assignment_inside_multi_exec_block_with_immediate_command_errors
    assert_raises(Redis::CommandError) do
      r.multi do |m|
        m.doesnt_exist
        @first = m.sadd("foo", 1)
        @second = m.sadd("foo", 1)
      end
    end

    assert_raises(Redis::FutureNotReady) { @first.value }
    assert_raises(Redis::FutureNotReady) { @second.value }
  end

  def test_raise_immediate_errors_in_multi_exec
    assert_raises(RuntimeError) do
      r.multi do |multi|
        multi.set "bar", "s2"
        raise "Some error"
      end
    end

    assert_nil r.get("bar")
    assert_nil r.get("baz")
  end

  def test_transformed_replies_as_return_values_for_multi_exec_block
    info, = r.multi do |transaction|
      transaction.info
    end

    assert_instance_of Hash, info
  end

  def test_transformed_replies_inside_multi_exec_block
    r.multi do |transaction|
      @info = transaction.info
    end

    assert @info.value.is_a?(Hash)
  end

  def test_raise_command_errors_when_reply_is_not_transformed
    assert_raises(Redis::CommandError) do
      r.multi do |m|
        m.set("foo", "s1")
        m.incr("foo") # not an integer
        m.lpush("foo", "value") # wrong kind of value
      end
    end

    assert_equal "s1", r.get("foo")
  end

  def test_empty_multi_exec
    result = nil

    redis_mock(exec: ->(*_) { "-ERROR" }) do |redis|
      result = redis.multi {}
    end

    assert_equal [], result
  end

  def test_raise_command_errors_when_reply_is_transformed_from_int_to_boolean
    assert_raises(Redis::CommandError) do
      r.multi do |m|
        m.set("foo", 1)
        m.sadd("foo", 2)
      end
    end
  end

  def test_raise_command_errors_when_reply_is_transformed_from_ok_to_boolean
    assert_raises(Redis::CommandError) do
      r.multi do |m|
        m.set("foo", 1, ex: 0, nx: true)
      end
    end
  end

  def test_raise_command_errors_when_reply_is_transformed_to_float
    assert_raises(Redis::CommandError) do
      r.multi do |m|
        m.set("foo", 1)
        m.zscore("foo", "b")
      end
    end
  end

  def test_raise_command_errors_when_reply_is_transformed_to_floats
    assert_raises(Redis::CommandError) do
      r.multi do |m|
        m.zrange("a", "b", 5, with_scores: true)
      end
    end
  end

  def test_raise_command_errors_when_reply_is_transformed_to_hash
    assert_raises(Redis::CommandError) do
      r.multi do |m|
        m.set("foo", 1)
        m.hgetall("foo")
      end
    end
  end

  def test_raise_command_errors_when_accessing_futures_after_multi_exec
    begin
      r.multi do |m|
        m.set("foo", "s1")
        @counter = m.incr("foo") # not an integer
      end
    rescue Exception
      # Not gonna deal with it
    end

    # We should test for Redis::Error here, but hiredis doesn't yet do
    # custom error classes.
    err = nil
    begin
      @counter.value
    rescue => err
    end

    assert err.is_a?(RuntimeError)
  end

  def test_multi_with_a_block_yielding_the_client
    r.multi do |multi|
      multi.set "foo", "s1"
    end

    assert_equal "s1", r.get("foo")
  end

  def test_multi_with_interrupt_preserves_client
    original = r._client
    Redis::MultiConnection.stubs(:new).raises(Interrupt)
    assert_raises(Interrupt) { r.multi {} }
    assert_equal r._client, original
  end

  def test_raise_command_error_when_exec_fails
    redis_mock(exec: ->(*_) { "-ERROR" }) do |redis|
      assert_raises(Redis::CommandError) do
        redis.multi do |m|
          m.set "foo", "s1"
        end
      end
    end
  end

  def test_watch
    res = r.watch "foo"

    assert_equal "OK", res
  end

  def test_watch_with_an_unmodified_key
    r.watch "foo"
    r.multi do |multi|
      multi.set "foo", "s1"
    end

    assert_equal "s1", r.get("foo")
  end

  def test_watch_with_an_unmodified_key_passed_as_array
    r.watch ["foo", "bar"]
    r.multi do |multi|
      multi.set "foo", "s1"
    end

    assert_equal "s1", r.get("foo")
  end

  def test_watch_with_a_modified_key
    r.watch "foo"
    r.set "foo", "s1"
    res = r.multi do |multi|
      multi.set "foo", "s2"
    end

    assert_nil res
    assert_equal "s1", r.get("foo")
  end

  def test_watch_with_a_modified_key_passed_as_array
    r.watch ["foo", "bar"]
    r.set "foo", "s1"
    res = r.multi do |multi|
      multi.set "foo", "s2"
    end

    assert_nil res
    assert_equal "s1", r.get("foo")
  end

  def test_watch_with_a_block_and_an_unmodified_key
    result = r.watch "foo" do |rd|
      assert_same r, rd

      rd.multi do |multi|
        multi.set "foo", "s1"
      end
    end

    assert_equal ["OK"], result
    assert_equal "s1", r.get("foo")
  end

  def test_watch_with_a_block_and_a_modified_key
    result = r.watch "foo" do |rd|
      assert_same r, rd

      rd.set "foo", "s1"
      rd.multi do |multi|
        multi.set "foo", "s2"
      end
    end

    assert_nil result
    assert_equal "s1", r.get("foo")
  end

  def test_watch_with_a_block_that_raises_an_exception
    r.set("foo", "s1")

    begin
      r.watch "foo" do
        raise "test"
      end
    rescue RuntimeError
    end

    r.set("foo", "s2")

    # If the watch was still set from within the block above, this multi/exec
    # would fail. This proves that raising an exception above unwatches.
    r.multi do |multi|
      multi.set "foo", "s3"
    end

    assert_equal "s3", r.get("foo")
  end

  def test_unwatch_with_a_modified_key
    r.watch "foo"
    r.set "foo", "s1"
    r.unwatch
    r.multi do |multi|
      multi.set "foo", "s2"
    end

    assert_equal "s2", r.get("foo")
  end
end
