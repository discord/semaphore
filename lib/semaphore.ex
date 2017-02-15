defmodule Semaphore do
  alias :ets, as: ETS

  @table :semaphore

  ## Application Callbacks

  def start(_type, _args) do
    import Supervisor.Spec, warn: false
    Supervisor.start_link([worker(Agent, [&init/0])], strategy: :one_for_one)
  end

  ## Client API

  @doc """
  Acquire a semaphore, incrementing the internal count by one.
  """
  @spec acquire(term, integer) :: boolean
  def acquire(name, max) do
    try do
      case ETS.update_counter(@table, name, [{2, 0}, {2, 1, max, max}]) do
        [^max, ^max] ->
          false
        [_, count] when count <= max ->
          true
        [_, ^max] ->
          true
      end
    rescue
      ArgumentError ->
        if ETS.insert_new(@table, {name, 1}) do
          true
        else
          acquire(name, max)
        end
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
      [{^name, count}] -> count
      [] -> 0
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

  ## Private

  defp init do
    ETS.new(@table, [:set, :public, :named_table, {:write_concurrency, true}])
  end
end
