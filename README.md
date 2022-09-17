# Semaphore

[![Master](https://travis-ci.org/discordapp/semaphore.svg?branch=master)](https://travis-ci.org/discordapp/semaphore)
[![Hex.pm Version](http://img.shields.io/hexpm/v/semaphore.svg?style=flat)](https://hex.pm/packages/semaphore)

Programming in Erlang and Elixir usually allows for no locking since the VM essentially handles it for you when
communicating between processes. However, what about the situation when you have thousands of processes attempting
to interact with a single resource such as a process? Usually they will overload the process and explode the
message queue. ETS is the Swiss Army knife of the Erlang VM and can be applied to this problem. By using `:ets.update_counter`
and `:write_concurrency` we can achieve a **fast** low contention semaphore on ETS.

## Usage

Add it to `mix.exs`

```elixir
defp deps do
  [{:semaphore, "~> 1.3"}]
end
```

Then just use it like a semaphore in any other language.

```elixir
if Semaphore.acquire(:test, 1) do
  IO.puts "acquired"
  Semaphore.release(:test)
end

case Semaphore.call(:test, 1, fn -> :ok end) do
  :ok ->
    IO.puts "success"
  {:error, :max} ->
    IO.puts "too many callers"
end
```

## License

Semaphore is released under [the MIT License](LICENSE).
Check [LICENSE](LICENSE) file for more information.
