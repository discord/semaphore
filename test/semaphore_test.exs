defmodule SemaphoreTest do
  use ExUnit.Case, async: false
  doctest Semaphore

  setup do
    Semaphore.reset(:foo)
  end

  test "acquire" do
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
    assert Semaphore.acquire(:foo, 1) == true
    assert Semaphore.release(:foo) == :ok
    assert Semaphore.release(:foo) == :ok
    assert Semaphore.release(:foo) == :ok
    assert Semaphore.acquire(:foo, 1) == true
    assert Semaphore.acquire(:foo, 1) == false
    assert Semaphore.count(:foo) == 1
  end

  test "increase max" do
    assert Semaphore.acquire(:foo, 1) == true
    assert Semaphore.acquire(:foo, 3) == true
    assert Semaphore.acquire(:foo, 3) == true
  end

  test "decrease max" do
    assert Semaphore.acquire(:foo, 2) == true
    assert Semaphore.acquire(:foo, 2) == true
    assert Semaphore.acquire(:foo, 2) == false
    assert Semaphore.acquire(:foo, 1) == false
  end

  test "call" do
    assert Semaphore.call(:foo, 1, fn -> :bar end) == :bar
    assert Semaphore.count(:foo) == 0
    assert Semaphore.acquire(:foo, 1) == true
    assert Semaphore.call(:foo, 1, fn -> :bar end) == {:error, :max}
  end

  test "call_linksafe" do
    # Spawn a process that will exit due to a linked process exiting.
    {pid, ref} = spawn_monitor(fn ->
      Semaphore.call_linksafe(:foo, 5, fn ->
        spawn_link(fn -> exit(:ded) end)
        Process.sleep(:infinity)
      end)
    end)
    # Wait for the process to die.
    assert_receive {:DOWN, ^ref, :process, ^pid, :ded}
    # The leak should have occurred.
    assert Semaphore.count(:foo) == 1
    # Force a sweep.
    Semaphore |> send(:timeout)
    # This is just so that we can ensure the sweep was processed.
    Semaphore |> :sys.get_state()
    # The leak should now be fixed.
    assert Semaphore.count(:foo) == 0
  end
end
