defmodule Semaphore.Resource do
  use GenServer

  defmacro __using__(opts \\ []) do
    max = Keyword.get(opts, :max, 1)

    quote do
      def start_link(opts \\ []) do
        opts = Keyword.put(opts, :name, __MODULE__)
        Semaphore.Resource.start_link(__MODULE__, unquote(max), opts)
      end

      def child_spec(opts) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, opts}
        }
      end

      defoverridable child_spec: 1

      @doc """
      Acquires the underlying semaphore. If it is unavailable, it will block until
      the semaphore can be acquired.
      """
      @spec acquire() :: :ok
      def acquire(), do: Semaphore.Resource.acquire(__MODULE__)

      @doc """
      Acquires the underlying semaphore, and then calls the given function.
      Afterwards it will release the underlying semaphore.
      """
      @spec call((() -> result)) :: result when result: term()
      def call(func), do: Semaphore.Resource.call(__MODULE__, func)

      @doc """
      Releases the underlying semaphore.
      """
      @spec release() :: :ok
      def release(), do: Semaphore.Resource.release(__MODULE__)
    end
  end

  @spec start_link(name :: atom(), max :: integer, Keyword.t()) ::
          GenServer.on_start()
  def start_link(name, max, opts \\ []) when is_atom(name) do
    GenServer.start_link(__MODULE__, {name, max}, opts)
  end

  @doc """
  Acquires the underlying semaphore. If it is unavailable, it will block until
  the semaphore can be acquired.
  """
  @spec acquire(pid()) :: :ok
  def acquire(pid) do
    GenServer.call(pid, :acquire, :infinity)
  end

  @doc """
  Acquires the underlying semaphore, and then calls the given function.
  Afterwards it will release the underlying semaphore.
  """
  @spec call(pid(), (() -> result)) :: result when result: term()
  def call(pid, func) do
    acquire(pid)

    try do
      func.()
    after
      release(pid)
    end
  end

  @doc """
  Releases the underlying semaphore.
  """
  @spec release(pid()) :: :ok
  def release(pid), do: GenServer.call(pid, :release)

  ## Private

  @impl GenServer
  def init({name, max}) do
    {:ok, %{name: name, max: max, waiting: :queue.new()}}
  end

  @impl GenServer
  def handle_call(:acquire, from, %{name: name, max: max, waiting: waiting} = state) do
    if Semaphore.acquire(name, max) do
      {:reply, :ok, state}
    else
      {:noreply, %{state | waiting: :queue.in(from, waiting)}}
    end
  end

  @impl GenServer
  def handle_call(:release, _from, %{name: name, waiting: waiting} = state) do
    case :queue.out(waiting) do
      {{:value, next}, waiting} ->
        GenServer.reply(next, :ok)
        {:reply, :ok, %{state | waiting: waiting}}

      _ ->
        {:reply, Semaphore.release(name), state}
    end
  end
end
