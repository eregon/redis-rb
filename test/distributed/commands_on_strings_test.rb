# frozen_string_literal: true

require "helper"

class TestDistributedCommandsOnStrings < Minitest::Test
  include Helper::Distributed
  include Lint::Strings

  def test_mget
    r.set("foo", "s1")
    r.set("bar", "s2")

    assert_equal ["s1", "s2"], r.mget("foo", "bar")
    assert_equal ["s1", "s2", nil], r.mget("foo", "bar", "baz")
  end

  def test_mget_mapped
    r.set("foo", "s1")
    r.set("bar", "s2")

    response = r.mapped_mget("foo", "bar")

    assert_equal "s1", response["foo"]
    assert_equal "s2", response["bar"]

    response = r.mapped_mget("foo", "bar", "baz")

    assert_equal "s1", response["foo"]
    assert_equal "s2", response["bar"]
    assert_nil response["baz"]
  end

  def test_mset
    assert_raises Redis::Distributed::CannotDistribute do
      r.mset(:foo, "s1", :bar, "s2")
    end
  end

  def test_mset_mapped
    assert_raises Redis::Distributed::CannotDistribute do
      r.mapped_mset(foo: "s1", bar: "s2")
    end
  end

  def test_msetnx
    assert_raises Redis::Distributed::CannotDistribute do
      r.set("foo", "s1")
      r.msetnx(:foo, "s2", :bar, "s3")
    end
  end

  def test_msetnx_mapped
    assert_raises Redis::Distributed::CannotDistribute do
      r.set("foo", "s1")
      r.mapped_msetnx(foo: "s2", bar: "s3")
    end
  end

  def test_bitop
    assert_raises Redis::Distributed::CannotDistribute do
      r.set("foo", "a")
      r.set("bar", "b")

      r.bitop(:and, "foo&bar", "foo", "bar")
    end
  end

  def test_mapped_mget_in_a_pipeline_returns_hash
    assert_raises Redis::Distributed::CannotDistribute do
      super
    end
  end

  def test_bitfield
    # Not implemented yet
  end
end
