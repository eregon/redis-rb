# frozen_string_literal: true

require "helper"

class TestDistributedPublishSubscribe < Minitest::Test
  include Helper::Distributed

  def test_subscribe_and_unsubscribe
    assert_raises Redis::Distributed::CannotDistribute do
      r.subscribe("foo", "bar") {}
    end

    assert_raises Redis::Distributed::CannotDistribute do
      r.subscribe("{qux}foo", "bar") {}
    end
  end

  def test_subscribe_and_unsubscribe_with_tags
    @subscribed = false
    @unsubscribed = false

    thread = Thread.new do
      r.subscribe("foo") do |on|
        on.subscribe do |_channel, total|
          @subscribed = true
          @t1 = total
        end

        on.message do |_channel, message|
          if message == "s1"
            r.unsubscribe
            @message = message
          end
        end

        on.unsubscribe do |_channel, total|
          @unsubscribed = true
          @t2 = total
        end
      end
    end

    # Wait until the subscription is active before publishing
    Thread.pass until @subscribed

    Redis::Distributed.new(NODES).publish("foo", "s1")

    thread.join

    assert @subscribed
    assert_equal 1, @t1
    assert @unsubscribed
    assert_equal 0, @t2
    assert_equal "s1", @message
  end

  def test_subscribe_within_subscribe
    @channels = []

    thread = Thread.new do
      r.subscribe("foo") do |on|
        on.subscribe do |channel, _total|
          @channels << channel

          r.subscribe("bar") if channel == "foo"
          r.unsubscribe if channel == "bar"
        end
      end
    end

    thread.join

    assert_equal ["foo", "bar"], @channels
  end

  def test_other_commands_within_a_subscribe
    r.subscribe("foo") do |on|
      on.subscribe do |_channel, _total|
        r.set("bar", "s2")
        r.unsubscribe("foo")
      end
    end
  end

  def test_subscribe_without_a_block
    assert_raises LocalJumpError do
      r.subscribe("foo")
    end
  end
end
