defmodule Semaphore.Resource do
  use GenServer

  @default_sweep_interval 5000

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

  defmodule State do
    @type t :: %__MODULE__{
            name: term(),
            max: integer(),
            current: MapSet.t(GenServer.from()),
            waiting: :queue.queue(GenServer.from()),
            sweep_interval: non_neg_integer()
          }
    @enforce_keys [:name, :max, :current, :waiting, :sweep_interval]
    defstruct [:name, :max, :current, :waiting, :sweep_interval]
  end

  @spec start_link(name :: term(), max :: integer, Keyword.t()) ::
          GenServer.on_start()
  def start_link(name, max, opts \\ []) when is_atom(name) do
    sweep_interval = Keyword.get(opts, :sweep_interval, @default_sweep_interval)
    GenServer.start_link(__MODULE__, {name, max, sweep_interval}, opts)
  end

  @doc """
  Acquires the underlying semaphore. If it is unavailable, it will block until
  the semaphore can be acquired.
  """
  @spec acquire(GenServer.server()) :: :ok
  def acquire(pid) do
    GenServer.call(pid, :acquire, :infinity)
  end

  @doc """
  Acquires the underlying semaphore, and then calls the given function.
  Afterwards it will release the underlying semaphore.
  """
  @spec call(GenServer.server(), (() -> result)) :: result when result: term()
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
  @spec release(GenServer.server()) :: :ok
  def release(pid), do: GenServer.call(pid, :release)

  ## Private

  @impl GenServer
  def init({name, max, sweep_interval}) do
    schedule_sweep(sweep_interval)

    {:ok,
     %State{
       name: name,
       max: max,
       waiting: :queue.new(),
       current: MapSet.new(),
       sweep_interval: sweep_interval
     }}
  end

  @impl GenServer
  def handle_call(
        :acquire,
        from,
        %State{
          name: name,
          max: max,
          waiting: waiting,
          current: current
        } = state
      ) do
    if Semaphore.acquire(name, max) do
      {:reply, :ok, %State{state | current: MapSet.put(current, from)}}
    else
      {:noreply, %State{state | waiting: :queue.in(from, waiting)}}
    end
  end

  def handle_call(:release, from, state) do
    {:reply, :ok, do_release(from, state)}
  end

  @spec do_release(GenServer.from(), State.t()) :: State.t()
  defp do_release(
         from,
         %State{
           name: name,
           waiting: waiting,
           current: current
         } = state
       ) do
    case :queue.out(waiting) do
      {{:value, {pid, _} = next}, waiting} ->
        if Process.alive?(pid) do
          GenServer.reply(next, :ok)

          %State{
            state
            | waiting: waiting,
              current:
                current
                |> MapSet.delete(from)
                |> MapSet.put(next)
          }
        else
          do_release(from, %State{state | waiting: waiting})
        end

      _ ->
        Semaphore.release(name)
        %State{state | current: MapSet.new()}
    end
  end

  @impl GenServer
  def handle_info(:sweep, state) do
    {:noreply, do_sweep(state)}
  end

  defp schedule_sweep(interval) do
    Process.send_after(self(), :sweep, interval)
  end

  defp do_sweep(%State{current: current, sweep_interval: sweep_interval} = state) do
    new_state =
      Enum.reduce(current, state, fn {pid, _} = client, state ->
        if Process.alive?(pid) do
          state
        else
          do_release(client, state)
        end
      end)

    schedule_sweep(sweep_interval)

    new_state
  end
end
