defmodule Mix.Tasks.Hyperliquid.Gen.Migrations do
  use Mix.Task

  @shortdoc "Copy the Hyperliquid Ecto migrations into your application"

  @moduledoc """
  Copies the migrations shipped with the `hyperliquid` package into your own
  application's migrations directory.

  `hyperliquid` keeps Postgres optional: `ecto_sql`/`postgrex` are optional
  deps and `Hyperliquid.Repo` only exists when the adapter is loaded. Because
  of that, the library cannot run migrations for you — the tables it writes to
  have to be created by *your* repo, in *your* migration history. This task is
  the copy step (the standard Ecto-library pattern; cf. `Oban.Migration`).

  ## Usage

      mix hyperliquid.gen.migrations
      mix hyperliquid.gen.migrations --repo MyApp.Repo
      mix hyperliquid.gen.migrations --path priv/repo/migrations --force

  Then run them the usual way:

      mix ecto.migrate

  ## Options

    * `--repo` - Repo module the migrations should be namespaced under.
      Defaults to the first entry in `config :your_app, :ecto_repos`, else
      `Hyperliquid.Repo`. Only the module prefix is rewritten; the migration
      bodies are copied verbatim.
    * `--path` - Destination directory (default: `priv/repo/migrations`).
    * `--force` - Overwrite destination files that already exist. Without it,
      an existing migration with the same name is skipped and reported.
    * `--quiet` - Suppress per-file output.

  ## Idempotency

  Migrations are matched by name (the part after the timestamp), not by
  timestamp, so re-running the task after upgrading `hyperliquid` copies only
  the migrations you do not already have. Nothing is ever overwritten without
  `--force`.
  """

  @default_path "priv/repo/migrations"

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [repo: :string, path: :string, force: :boolean, quiet: :boolean],
        aliases: [r: :repo, f: :force, q: :quiet]
      )

    dest = Path.expand(opts[:path] || @default_path)
    force = opts[:force] || false
    quiet = opts[:quiet] || false
    repo = repo_prefix(opts[:repo])

    source_dir = source_dir()

    unless File.dir?(source_dir) do
      Mix.raise("""
      Could not find the bundled migrations at:

          #{source_dir}

      This usually means the :hyperliquid application is not compiled, or the
      package was built without priv/. Run `mix deps.compile hyperliquid`.
      """)
    end

    File.mkdir_p!(dest)

    existing = existing_migration_names(dest)

    {copied, skipped} =
      source_dir
      |> File.ls!()
      |> Enum.filter(&migration_file?/1)
      |> Enum.sort()
      |> Enum.reduce({0, 0}, fn file, {copied, skipped} ->
        name = migration_name(file)
        target = Path.join(dest, file)

        cond do
          MapSet.member?(existing, name) and not force ->
            unless quiet, do: Mix.shell().info("* skipping #{file} (already present)")
            {copied, skipped + 1}

          true ->
            contents =
              source_dir
              |> Path.join(file)
              |> File.read!()
              |> String.replace("Hyperliquid.Repo.Migrations.", "#{repo}.Migrations.")

            File.write!(target, contents)
            unless quiet, do: Mix.shell().info("* creating #{Path.relative_to_cwd(target)}")
            {copied + 1, skipped}
        end
      end)

    Mix.shell().info("""

    Copied #{copied} migration(s) into #{Path.relative_to_cwd(dest)} (#{skipped} skipped).
    Run `mix ecto.migrate` to apply them.
    """)
  end

  defp source_dir do
    case :code.priv_dir(:hyperliquid) do
      {:error, :bad_name} -> Path.expand("../../../priv/repo/migrations", __DIR__)
      priv -> Path.join([to_string(priv), "repo", "migrations"])
    end
  end

  defp repo_prefix(nil) do
    Mix.Project.config()
    |> Keyword.get(:app)
    |> case do
      nil -> nil
      app -> Application.get_env(app, :ecto_repos, []) |> List.first()
    end
    |> case do
      nil -> "Hyperliquid.Repo"
      repo -> inspect(repo)
    end
  end

  defp repo_prefix(repo) when is_binary(repo), do: repo

  # Timestamped migrations only — never `.formatter.exs` and friends.
  defp migration_file?(file) do
    String.ends_with?(file, ".exs") and Regex.match?(~r/^\d{14}_/, file)
  end

  # "20251126190000_create_trades.exs" -> "create_trades"
  defp migration_name(file) do
    file
    |> Path.rootname()
    |> String.split("_", parts: 2)
    |> case do
      [_timestamp, name] -> name
      [name] -> name
    end
  end

  defp existing_migration_names(dir) do
    dir
    |> File.ls!()
    |> Enum.filter(&migration_file?/1)
    |> Enum.map(&migration_name/1)
    |> MapSet.new()
  end
end
