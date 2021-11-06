defmodule Semaphore.ResourceTest do
  use ExUnit.Case, async: false

  defmodule FooResource do
    use Semaphore.Resource, max: 1
  end

  setup do
    Semaphore.reset(:foo)
    start_supervised!(FooResource)
    :ok
  end

  test "acquire and release" do
    assert FooResource.acquire() == :ok
    assert Semaphore.count(FooResource) == 1

    task =
      Task.async(fn ->
        Process.sleep(10)
        assert Semaphore.count(FooResource) == 1

        FooResource.release()
      end)

    assert FooResource.acquire() == :ok
    assert Task.await(task) == :ok

    FooResource.release()
    assert Semaphore.count(FooResource) == 0
  end

  test "call" do
    assert FooResource.call(fn -> {:ok, true} end) == {:ok, true}
    assert Semaphore.count(FooResource) == 0

    assert FooResource.acquire() == :ok

    task =
      Task.async(fn ->
        Process.sleep(10)
        FooResource.release()
      end)

    assert FooResource.call(fn -> {:ok, true} end) == {:ok, true}
    assert Task.await(task) == :ok
    assert Semaphore.count(FooResource) == 0
  end

  test "sweep" do
    # Spawn a process that will exit due to a linked process exiting.
    {pid, ref} =
      spawn_monitor(fn ->
        FooResource.call(fn ->
          spawn_link(fn -> exit(:ded) end)
          Process.sleep(:infinity)
        end)
      end)

    # Wait for the process to die.
    assert_receive {:DOWN, ^ref, :process, ^pid, :ded}
    # The leak should have occurred.
    assert Semaphore.count(FooResource) == 1

    FooResource |> send(:sweep)
    Process.sleep(1)

    # The leak should now be fixed.
    assert Semaphore.count(FooResource) == 0
  end
end
