defmodule SemaphoreTest do
  use ExUnit.Case, async: false

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

  test "call" do
    assert Semaphore.call(:foo, 1, fn -> :bar end) == :bar
    assert Semaphore.count(:foo) == 0
    assert Semaphore.acquire(:foo, 1) == true
    assert Semaphore.call(:foo, 1, fn -> :bar end) == {:error, :max}
  end

  test "call_linksafe" do
    # Spawn a process that will exit due to a linked process exiting.
    {pid, ref} =
      spawn_monitor(fn ->
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

  test "call_linksafe with full semaphore" do
    # Assert similar behavior from call/3
    assert Semaphore.call_linksafe(:foo, 5, fn -> :bar end) == :bar
    assert Semaphore.count(:foo) == 0

    # The call-safe table should be empty after a typical call to call_linksafe/3
    assert :ets.lookup(:semaphore_call_safe, :foo) == []

    assert Semaphore.acquire(:foo, 1) == true
    assert Semaphore.call_linksafe(:foo, 1, fn -> :bar end) == {:error, :max}

    # Reset for the following additional tests
    Semaphore.reset(:foo)

    # Spawn a couple processes that will exit due to a linked process exiting.
    {pid1, ref1} =
      spawn_monitor(fn ->
        Semaphore.call_linksafe(:foo, 5, fn ->
          spawn_link(fn -> exit(:ded) end)
          Process.sleep(:infinity)
        end)
      end)

    {pid2, ref2} =
      spawn_monitor(fn ->
        Semaphore.call_linksafe(:foo, 5, fn ->
          spawn_link(fn -> exit(:ded) end)
          Process.sleep(:infinity)
        end)
      end)

    # Wait for the process to die.
    assert_receive {:DOWN, ^ref1, :process, ^pid1, :ded}
    assert_receive {:DOWN, ^ref2, :process, ^pid2, :ded}
    # The leak should have occurred.
    assert Semaphore.count(:foo) == 2
    # Force a sweep.
    Semaphore |> send(:timeout)
    # This is just so that we can ensure the sweep was processed.
    Semaphore |> :sys.get_state()
    # The leak should now be fixed.
    assert Semaphore.count(:foo) == 0
  end

  test "acquire_linksafe" do
    # Spawn a process that will exit due to a linked process exiting.
    {pid, ref} =
      spawn_monitor(fn ->
        max = 5
        true = Semaphore.acquire_linksafe(:name, :key, max)
        true = Semaphore.acquire_linksafe(:name, :key2, max)
        exit(:ded)
      end)

    # Wait for the process to die.
    assert_receive {:DOWN, ^ref, :process, ^pid, :ded}
    # The leak should have occurred.
    assert Semaphore.count(:name) == 2
    # Force a sweep.
    send(Semaphore, :timeout)
    # This is just so that we can ensure the sweep was processed.
    :sys.get_state(Semaphore)
    # The leak should now be fixed.
    assert Semaphore.count(:name) == 0
  end

  test "release_linksafe" do
    Semaphore.acquire_linksafe(:name, :key, 5)
    assert Semaphore.count(:name) == 1

    Semaphore.acquire_linksafe(:name, :key2, 5)
    assert Semaphore.count(:name) == 2

    Semaphore.release_linksafe(:name, :key)
    assert Semaphore.count(:name) == 1

    Semaphore.release_linksafe(:name, :key2)
    assert Semaphore.count(:name) == 0
  end
end
