defmodule Hyperliquid.Api do
  @moduledoc """
  Root API module providing unified access to all Hyperliquid endpoints.

  This module offers a Redix-style command interface for dynamic endpoint
  invocation, along with direct access to context-specific modules.

  ## Command Interface

  The `command/3` function provides dynamic endpoint invocation:

      # Simple endpoint (no params)
      {:ok, mids} = Hyperliquid.Api.command(:info, :all_mids)

      # With positional arguments
      {:ok, book} = Hyperliquid.Api.command(:info, :l2_book, ["BTC"])
      {:ok, state} = Hyperliquid.Api.command(:info, :clearinghouse_state, ["0xabc..."])

      # With keyword options
      {:ok, mids} = Hyperliquid.Api.command(:info, :all_mids, dex: "hypurr")

  ## Context Modules

  For a more structured API with autocomplete and type safety, use context modules:

      # Info endpoints
      Hyperliquid.Api.Info.all_mids()
      Hyperliquid.Api.Info.l2_book("BTC")
      Hyperliquid.Api.Info.clearinghouse_state("0xabc...")

      # Exchange endpoints
      Hyperliquid.Api.Exchange.Order.market_open(...)
      Hyperliquid.Api.Exchange.top_up_isolated_only_margin(0, 5)

      # Multi-sig wrapping of any exchange action
      Hyperliquid.Api.MultiSig.request_l1(signers, opts)

  ## Direct Endpoint Access

  The original endpoint modules are still available and unchanged:

      Hyperliquid.Api.Info.AllMids.request()
      Hyperliquid.Api.Info.L2Book.request("BTC")

  ## Discovering Endpoints

  Use the Registry to discover available endpoints:

      # List all endpoints
      Hyperliquid.Api.Registry.list_endpoints()

      # List by type (:info, :exchange, :subscription, :explorer, :stats)
      Hyperliquid.Api.Registry.list_by_type(:info)
      Hyperliquid.Api.Registry.list_by_type(:subscription)

      # Get endpoint metadata
      Hyperliquid.Api.Registry.get_endpoint_info("allMids")

      # Full module list for a context, including Exchange action modules that
      # carry no DSL metadata
      Hyperliquid.Api.Registry.list_context_endpoints(:exchange)
  """

  alias Hyperliquid.Api.Registry

  @typedoc """
  Supported API contexts for `command/3`.

  Only contexts whose modules expose `request/N` are supported: `:info`,
  `:explorer`, `:stats`, and the DSL-backed `:exchange` modules. Subscriptions
  are registered in `Hyperliquid.Api.Registry` but are driven through the
  WebSocket manager rather than `command/3`.
  """
  @type context :: :info | :exchange | :explorer | :stats

  @typedoc """
  Endpoint name in snake_case.
  """
  @type endpoint_name :: atom()

  @typedoc """
  Arguments for endpoint invocation.

  Can be either:
  - List of positional arguments: `["BTC"]`, `["0xabc..."]`
  - Keyword list of options: `[dex: "hypurr"]`, `[nSigFigs: 5]`
  - Empty list for parameterless endpoints: `[]`
  """
  @type args :: list()

  @doc """
  Execute an API endpoint command.

  This provides a Redix-style interface for dynamic endpoint invocation.

  ## Parameters

  - `context` - The API context (`:info`, `:exchange`, `:explorer`, `:stats`)
  - `endpoint` - The endpoint name in snake_case (`:all_mids`, `:l2_book`, etc.)
  - `args` - Arguments to pass to the endpoint (default: `[]`)

  ## Argument Handling

  Arguments can be provided in two formats:

  1. **Positional arguments** (list of values):
     - Mapped to the endpoint's required parameters in order
     - Example: `command(:info, :l2_book, ["BTC"])` calls `L2Book.request("BTC")`

  2. **Keyword options** (keyword list):
     - Passed directly to the endpoint's `request/1` function
     - Example: `command(:info, :all_mids, dex: "hypurr")` calls `AllMids.request(dex: "hypurr")`

  3. **No arguments** (empty list or omitted):
     - Calls the endpoint with no parameters
     - Example: `command(:info, :all_mids)` calls `AllMids.request()`

  ## Returns

  - `{:ok, result}` - Successful endpoint call
  - `{:error, reason}` - Error from endpoint or resolution failure

  ## Examples

      # Parameterless endpoints
      {:ok, mids} = Hyperliquid.Api.command(:info, :all_mids)
      {:ok, meta} = Hyperliquid.Api.command(:info, :meta)

      # Endpoints with required parameters
      {:ok, book} = Hyperliquid.Api.command(:info, :l2_book, ["BTC"])
      {:ok, state} = Hyperliquid.Api.command(:info, :clearinghouse_state, ["0xabc..."])

      # Endpoints with optional parameters
      {:ok, mids} = Hyperliquid.Api.command(:info, :all_mids, dex: "hypurr")
      {:ok, book} = Hyperliquid.Api.command(:info, :l2_book, ["BTC"], nSigFigs: 5)

      # Error handling
      case Hyperliquid.Api.command(:info, :nonexistent) do
        {:ok, result} -> IO.inspect(result)
        {:error, :not_found} -> IO.puts("Endpoint not found")
        {:error, reason} -> IO.puts("Error: \#{inspect(reason)}")
      end
  """
  @spec command(context(), endpoint_name(), args()) :: {:ok, term()} | {:error, term()}
  def command(context, endpoint_name, args \\ [])

  def command(context, endpoint_name, args)
      when is_atom(context) and is_atom(endpoint_name) and is_list(args) do
    with {:ok, module} <- Registry.resolve_endpoint(context, endpoint_name) do
      invoke_endpoint(module, args)
    end
  end

  @doc """
  Execute an API endpoint command, raising on error.

  Same as `command/3` but raises on error instead of returning an error tuple.

  ## Examples

      mids = Hyperliquid.Api.command!(:info, :all_mids)
      book = Hyperliquid.Api.command!(:info, :l2_book, ["BTC"])
      state = Hyperliquid.Api.command!(:info, :clearinghouse_state, ["0xabc..."])

  ## Raises

  - `Hyperliquid.Error` - On endpoint errors
  - `RuntimeError` - On resolution errors (invalid context, endpoint not found)
  """
  @spec command!(context(), endpoint_name(), args()) :: term()
  def command!(context, endpoint_name, args \\ [])

  def command!(context, endpoint_name, args)
      when is_atom(context) and is_atom(endpoint_name) and is_list(args) do
    case command(context, endpoint_name, args) do
      {:ok, result} ->
        result

      {:error, :not_found} ->
        raise RuntimeError, "Endpoint not found: #{context}.#{endpoint_name}"

      {:error, {:invalid_context, ctx}} ->
        raise RuntimeError, "Invalid context: #{inspect(ctx)}"

      {:error, %Ecto.Changeset{} = changeset} ->
        raise Hyperliquid.Error, format_changeset_errors(changeset)

      {:error, reason} ->
        raise Hyperliquid.Error, reason
    end
  end

  # Invoke the endpoint module's request function with appropriate arguments
  defp invoke_endpoint(module, args) do
    cond do
      # Empty args - call request/0
      args == [] ->
        module.request()

      # Keyword list - call request/1 with opts
      Keyword.keyword?(args) ->
        module.request(args)

      # Positional args - apply them to request/N
      is_list(args) ->
        apply(module, :request, args)
    end
  rescue
    e in UndefinedFunctionError ->
      {:error, {:undefined_function, e.function, e.arity, "Module: #{inspect(module)}"}}

    e in ArgumentError ->
      {:error, {:argument_error, Exception.message(e)}}

    e ->
      {:error, {:unexpected_error, e}}
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
