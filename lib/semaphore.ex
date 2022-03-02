defmodule Semaphore do
  alias :ets, as: ETS

  @table :semaphore
  @call_safe_table :semaphore_call_safe

  ## Application Callbacks
  use GenServer

  def start(_type, _args) do
    import Supervisor.Spec, warn: false
    Supervisor.start_link([worker(__MODULE__, [])], strategy: :one_for_one)
  end

  def start_link() do
    sweep_interval = Application.get_env(:semaphore, :sweep_interval, 5_000)
    GenServer.start_link(__MODULE__, sweep_interval, name: __MODULE__)
  end
  ## Client API

  @doc """
  Acquire a semaphore, incrementing the internal count by one.
  """
  @spec acquire(term, integer) :: boolean
  def acquire(name, max) do
    case ETS.update_counter(@table, name, [{2, 0}, {2, 1, max, max}], {name, 0}) do
      [^max, _] -> false
      _ -> true
    end
  end

  @doc """
  Release a semaphore, decrementing the internal count by one.
  """
  @spec release(term) :: :ok
  def release(name) do
    ETS.update_counter(@table, name, {2, -1, 0, 0})
    :ok
  end

  @doc """
  Number of acquired semaphores.
  """
  @spec count(term) :: integer
  def count(name) do
    case ETS.lookup(@table, name) do
      [{_, count}] -> count
      _ -> 0
    end
  end

  @doc """
  Reset sempahore to a specific count.
  """
  @spec reset(term, integer) :: :ok
  def reset(name, count \\ 0) do
    ETS.update_element(@table, name, {2, count})
    :ok
  end

  @doc """
  Attempt to acquire a semaphore and call a function and then automatically release.
  """
  @spec call(term, integer, function) :: term | {:error, :max}
  def call(_name, -1, func), do: func.()
  def call(_name, 0, _func), do: {:error, :max}
  def call(name, max, func) do
    if acquire(name, max) do
      try do
        func.()
      after
        release(name)
      end
    else
      {:error, :max}
    end
  end

  @doc """
  Attempt to acquire a semaphore and call a function that might link to another process, and then automatically release.

  If the current process dies in a way that is unable to be caught by the try block (e.g. a linked process dies, while
  `func` is being called. The semaphore will be automatically released by the sweeper in the background.

  This function has higher overhead than `call/3` and should only be used if you know that you might be linking to
  something in the func.
  """
  @spec call_linksafe(term, integer, function) :: term | {:error, :max}
  def call_linksafe(_name, -1, func), do: func.()
  def call_linksafe(_name, 0, _func), do: {:error, :max}
  def call_linksafe(name, max, func) do
    if acquire(name, max) do
      safe_key = {name, self()}
      ETS.insert(@call_safe_table, [safe_key])
      try do
        func.()
      after
        release(name)
        ETS.delete_object(@call_safe_table, safe_key)
      end
    else
      {:error, :max}
    end
  end

  ## Private

  def init(sweep_interval) do
    ETS.new(@table, [:set, :public, :named_table, {:write_concurrency, true}])
    ETS.new(@call_safe_table, [:bag, :public, :named_table, {:write_concurrency, true}])
    {:ok, sweep_interval, sweep_interval}
  end

  def handle_info(:timeout, sweep_interval) do
    do_sweep()
    {:noreply, sweep_interval, sweep_interval}
  end

  defp do_sweep() do
    ETS.foldl(
      fn ({name, pid} = key, :ok) ->
        with false <- Process.alive?(pid),
             1 <- :ets.select_delete(@call_safe_table, [{key, [], [true]}]) do
          release(name)
        else
          _ -> :ok
        end
      end,
      :ok,
      @call_safe_table
    )
  end
end
