defmodule Hyperliquid.Api.RegistryCoverageTest do
  @moduledoc """
  Guards `Hyperliquid.Api.Registry` against drift.

  Every module defined under `lib/hyperliquid/api/<context>/` must be registered
  in `@endpoints_by_context`, and every registered module must exist on disk.
  If you add an endpoint module and this test fails, add it to the registry.
  """

  use ExUnit.Case, async: true

  alias Hyperliquid.Api.Registry

  @api_dir Path.expand("../../lib/hyperliquid/api", __DIR__)

  # Modules that live in an endpoint directory but are deliberately not
  # endpoints. Keep this list as short as possible.
  @not_endpoints [
    Hyperliquid.Api.Exchange.Action,
    Hyperliquid.Api.Exchange.KeyUtils,
    Hyperliquid.Api.Exchange.UserSigned
  ]

  @contexts [:info, :exchange, :subscription, :explorer, :stats]

  defp modules_on_disk(context) do
    @api_dir
    |> Path.join("#{context}/*.ex")
    |> Path.wildcard()
    |> Enum.flat_map(fn path ->
      case Regex.run(~r/^defmodule\s+([\w\.]+)\s+do/m, File.read!(path)) do
        [_, name] -> [Module.concat([name])]
        _ -> []
      end
    end)
    |> Enum.reject(&(&1 in @not_endpoints))
    |> Enum.sort()
  end

  describe "registry coverage" do
    for context <- @contexts do
      test "#{context}: every module on disk is registered" do
        context = unquote(context)
        on_disk = modules_on_disk(context)
        registered = Registry.list_context_endpoints(context) |> Enum.sort()

        missing = on_disk -- registered

        assert missing == [],
               "#{context} modules missing from Hyperliquid.Api.Registry: #{inspect(missing)}"
      end

      test "#{context}: every registered module exists on disk" do
        context = unquote(context)
        on_disk = modules_on_disk(context)
        registered = Registry.list_context_endpoints(context) |> Enum.sort()

        stale = registered -- on_disk

        assert stale == [],
               "#{context} modules registered but not found on disk: #{inspect(stale)}"
      end
    end

    test "the on-disk sweep actually found files" do
      # Guards against the wildcard silently resolving to nothing, which would
      # make every assertion above vacuously true.
      for context <- @contexts do
        assert modules_on_disk(context) != [],
               "no modules found under #{@api_dir}/#{context}"
      end
    end

    test "MultiSig is intentionally not registered" do
      refute Hyperliquid.Api.MultiSig in List.flatten(
               Enum.map(@contexts, &Registry.list_context_endpoints/1)
             )
    end
  end

  describe "list_endpoints/0" do
    test "surfaces subscription modules via __subscription_info__/0" do
      subs = Registry.list_by_type(:subscription)

      assert length(subs) == length(modules_on_disk(:subscription))
      assert Enum.all?(subs, &(&1.type == :subscription))
      assert "fastAssetCtxs" in Enum.map(subs, & &1.endpoint)
    end

    test "surfaces every info module" do
      assert length(Registry.list_by_type(:info)) == length(modules_on_disk(:info))
    end

    test "skips exchange modules that carry no endpoint metadata" do
      # Only the ExchangeEndpoint DSL modules expose metadata; the rest are
      # registered for resolution but have nothing to list.
      listed = Registry.list_by_type(:exchange)
      assert Enum.all?(listed, &(&1.type == :exchange))
      assert length(listed) < length(Registry.list_context_endpoints(:exchange))
    end
  end
end
