defmodule MessagingGateway.RateLimiterTest do
  # async: false because sweep/1 touches the shared table; keys are unique per test.
  use ExUnit.Case, async: false

  alias MessagingGateway.RateLimiter

  # rem(@now, 60_000) == 15_000
  @now 1_800_000_015_000

  test "allows up to the limit then reports retry-after" do
    k = make_ref()
    for _ <- 1..3, do: assert(:ok = RateLimiter.hit(k, 3, 60_000, @now))
    assert {:error, :rate_limited, 45_000} = RateLimiter.hit(k, 3, 60_000, @now)
  end

  test "keys are independent" do
    a = make_ref()
    b = make_ref()
    :ok = RateLimiter.hit(a, 1, 60_000, @now)
    assert {:error, :rate_limited, _} = RateLimiter.hit(a, 1, 60_000, @now)
    assert :ok = RateLimiter.hit(b, 1, 60_000, @now)
  end

  test "a new window resets the count" do
    k = make_ref()
    :ok = RateLimiter.hit(k, 1, 60_000, @now)
    assert {:error, :rate_limited, _} = RateLimiter.hit(k, 1, 60_000, @now)
    assert :ok = RateLimiter.hit(k, 1, 60_000, @now + 45_000)
  end

  test "counting is atomic under contention" do
    k = make_ref()

    results =
      1..100
      |> Task.async_stream(fn _ -> RateLimiter.hit(k, 10, 60_000, @now) end, max_concurrency: 50)
      |> Enum.map(&elem(&1, 1))

    assert Enum.count(results, &(&1 == :ok)) == 10
  end

  test "sweep removes expired buckets and keeps live ones" do
    old = make_ref()
    live = make_ref()
    :ok = RateLimiter.hit(old, 1, 60_000, @now)
    :ok = RateLimiter.hit(live, 1, 60_000, @now + 120_000)
    assert RateLimiter.sweep(@now + 60_000) >= 1
    # the old bucket is gone, so the same window starts counting from zero again
    assert :ok = RateLimiter.hit(old, 1, 60_000, @now)
    assert {:error, :rate_limited, _} = RateLimiter.hit(live, 1, 60_000, @now + 120_000)
  end
end
