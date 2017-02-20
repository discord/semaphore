defmodule Semaphore.Mixfile do
  use Mix.Project

  def project do
    [
      app: :semaphore,
      version: "1.0.0",
      elixir: "~> 1.3",
      build_embedded: Mix.env == :prod,
      start_permanent: Mix.env == :prod,
      deps: deps(),
      package: package(),
    ]
  end

  def application do
    [
      applications: [],
      mod: {Semaphore, []}
    ]
  end

  defp deps do
    []
  end

  def package do
    [
      name: :semaphore,
      description: "Fast semaphore using ETS.",
      maintainers: [],
      licenses: ["MIT"],
      files: ["lib/*", "mix.exs", "README*", "LICENSE*"],
      links: %{
        "GitHub" => "https://github.com/hammerandchisel/semaphore",
      },
    ]
  end
end
