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
      @spec acquire(timeout()) :: :ok
      def acquire(timeout \\ :infinity),
        do: Semaphore.Resource.acquire(__MODULE__, timeout)

      @doc """
      Acquires the underlying semaphore, and then calls the given function.
      Afterwards it will release the underlying semaphore.
      """
      @spec call((() -> result), timeout()) :: result when result: term()
      def call(func, timeout \\ :infinity),
        do: Semaphore.Resource.call(__MODULE__, func, timeout)

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
  @spec acquire(pid(), timeout()) :: :ok
  def acquire(pid, timeout \\ :infinity) do
    if GenServer.call(pid, :acquire) do
      :ok
    else
      GenServer.call(pid, :wait, timeout)
      acquire(pid)
    end
  end

  @doc """
  Acquires the underlying semaphore, and then calls the given function.
  Afterwards it will release the underlying semaphore.
  """
  @spec call(pid(), (() -> result), timeout()) :: result when result: term()
  def call(pid, func, timeout \\ :infinity) do
    acquire(pid, timeout)

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
    {:ok, %{name: name, max: max, waiting: []}}
  end

  @impl GenServer
  def handle_call(:acquire, _from, %{name: name, max: max} = state) do
    {:reply, Semaphore.acquire(name, max), state}
  end

  @impl GenServer
  def handle_call(:release, _from, %{name: name, waiting: waiting} = state) do
    waiting
    |> Enum.reverse()
    |> Enum.each(&GenServer.reply(&1, :ok))

    {:reply, Semaphore.release(name), %{state | waiting: []}}
  end

  @impl GenServer
  def handle_call(:wait, from, %{waiting: waiting} = state) do
    {:noreply, %{state | waiting: [from | waiting]}}
  end
end
