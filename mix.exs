defmodule Hyperliquid.MixProject do
  use Mix.Project

  @source_url "https://github.com/skedzior/hyperliquid"
  @version "0.3.1"

  def project do
    [
      app: :hyperliquid,
      version: @version,
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      package: package(),
      deps: deps(),
      docs: docs(),
      aliases: aliases()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :runtime_tools],
      mod: {Hyperliquid.Application, []}
    ]
  end

  defp package do
    [
      description:
        "Elixir SDK for Hyperliquid DEX with DSL-based API endpoints, WebSocket subscriptions, and optional Postgres/Phoenix integration",
      maintainers: ["Steven Kedzior"],
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(
        lib
        native/signer/src
        native/signer/Cargo.toml
        native/signer/Cargo.lock
        checksum-Elixir.Hyperliquid.Signer.exs
        mix.exs
        README.md
        CHANGELOG.md
        LICENSE.md
      )
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Core dependencies
      {:phoenix_pubsub, "~> 2.1"},
      {:httpoison, "~> 1.7"},
      {:jason, "~> 1.4"},
      {:cachex, "~> 4.1.1"},
      {:telemetry, "~> 1.0"},
      {:gun, "~> 2.0"},
      {:mint_web_socket, "~> 1.0.5"},
      {:ecto, "~> 3.10"},

      # Optional database dependencies (enable with config :hyperliquid, enable_db: true)
      {:phoenix_ecto, "~> 4.5", optional: true},
      {:ecto_sql, "~> 3.10", optional: true},
      {:postgrex, ">= 0.0.0", optional: true},

      # Native extensions
      {:rustler_precompiled, "~> 0.8"},
      {:rustler, "~> 0.38.0", runtime: false, optional: true},

      # Development and testing
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:bypass, "~> 2.1", only: :test},

      # Livebook integration (dev only)
      {:pythonx, "~> 0.4.2", only: :dev},
      {:kino_pythonx, "~> 0.1.0", only: :dev}
    ]
  end

  defp docs do
    [
      extras: [
        "CHANGELOG.md": [title: "Changelog"],
        "LICENSE.md": [title: "License"],
        "README.md": [title: "Overview"]
      ],
      main: "readme",
      source_url: @source_url,
      formatters: ["html"]
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"] ++ if_ecto(["ecto.setup"]),
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: if_ecto(["ecto.create --quiet", "ecto.migrate --quiet"]) ++ ["test"]
    ]
  end

  defp if_ecto(tasks) do
    if Code.ensure_loaded?(Ecto) do
      tasks
    else
      []
    end
  end
end
