defmodule SemaphoreTest do
  use ExUnit.Case, async: false

  test "acquire" do
    Semaphore.reset(:foo)
    assert Semaphore.count(:foo) == 0
    assert Semaphore.acquire(:foo, 1) == true
    assert Semaphore.count(:foo) == 1
    assert Semaphore.acquire(:foo, 1) == false
    assert Semaphore.count(:foo) == 1
    assert Semaphore.release(:foo) == :ok
    assert Semaphore.count(:foo) == 0
    assert Semaphore.acquire(:foo, 1) == true
    assert Semaphore.count(:foo) == 1
  end

  test "release" do
    Semaphore.reset(:foo)
    assert Semaphore.acquire(:foo, 1) == true
    assert Semaphore.release(:foo) == :ok
    assert Semaphore.release(:foo) == :ok
    assert Semaphore.release(:foo) == :ok
    assert Semaphore.acquire(:foo, 1) == true
    assert Semaphore.acquire(:foo, 1) == false
    assert Semaphore.count(:foo) == 1
  end

  test "increase max" do
    Semaphore.reset(:foo)
    assert Semaphore.acquire(:foo, 1) == true
    assert Semaphore.acquire(:foo, 3) == true
    assert Semaphore.acquire(:foo, 3) == true
  end

  test "call" do
    Semaphore.reset(:foo)
    assert Semaphore.call(:foo, 1, fn -> :bar end) == :bar
    assert Semaphore.count(:foo) == 0
    assert Semaphore.acquire(:foo, 1) == true
    assert Semaphore.call(:foo, 1, fn -> :bar end) == {:error, :max}
  end
end
