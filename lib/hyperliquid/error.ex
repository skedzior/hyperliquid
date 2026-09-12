defmodule Hyperliquid.Error do
  @moduledoc """
  Shared exception for REST API, exchange-business and JSON-RPC errors.

  Handles:
  - Exchange business errors (`type: :exchange` / `:partial_rejection`)
  - Rate limiting (`type: :rate_limited`, with `retry_after` in milliseconds)
  - JSON-RPC errors (code/message/data)
  - HTTP errors (status_code/message)
  - Transport errors (reason)

  ## Classification order

  `exception/1` classifies in this order: explicit `:type` → `:status_code` →
  `:code` → `:reason`. This keeps an HTTP error body that happens to carry a
  `"code"` key from being mislabelled as a JSON-RPC error.

  ## Fields

  - `:message` - human readable message (response bodies are truncated)
  - `:type` - `:exchange | :partial_rejection | :rate_limited | :http | :jsonrpc | :transport | :validation | :signing | :internal | :unknown`
  - `:code` - JSON-RPC error code
  - `:status_code` - HTTP status code
  - `:reason` - transport reason term
  - `:data` - JSON-RPC error data
  - `:statuses` - per-item statuses for a partially rejected batch action
  - `:retry_after` - milliseconds to wait before retrying (429 responses)
  - `:response` - the raw response/term the error was built from
  """
  defexception [
    :message,
    :code,
    :data,
    :status_code,
    :reason,
    :response,
    :retry_after,
    :statuses,
    :type
  ]

  @type error_type ::
          :exchange
          | :partial_rejection
          | :rate_limited
          | :http
          | :jsonrpc
          | :transport
          | :validation
          | :signing
          | :internal
          | :unknown

  @type t :: %__MODULE__{
          message: String.t() | nil,
          code: integer() | nil,
          data: term(),
          status_code: non_neg_integer() | nil,
          reason: term(),
          response: term(),
          retry_after: non_neg_integer() | nil,
          statuses: list() | nil,
          type: error_type() | nil
        }

  # Response bodies are interpolated into `message` and every bang function
  # raises this struct, so keep them short enough for a crash report.
  @max_message_bytes 500

  @impl true
  def exception(err) when is_map(err) and not is_struct(err) do
    cond do
      # Explicit type wins - callers that already classified the error.
      is_atom(get(err, :type)) and not is_nil(get(err, :type)) ->
        from_explicit_type(err)

      # HTTP error
      Map.has_key?(err, :status_code) or Map.has_key?(err, "status_code") ->
        status = get(err, :status_code)
        msg = truncate(get(err, :message))

        %__MODULE__{
          message: "HTTP #{status}: #{msg}",
          status_code: status,
          retry_after: get(err, :retry_after),
          type: if(status == 429, do: :rate_limited, else: :http),
          response: err
        }

      # JSON-RPC error (string or atom keys)
      Map.has_key?(err, "code") or Map.has_key?(err, :code) ->
        code = get(err, :code)
        msg = truncate(get(err, :message)) || "JSON-RPC error"

        %__MODULE__{
          message: "JSON-RPC #{code}: #{msg}",
          code: code,
          data: get(err, :data),
          type: :jsonrpc,
          response: err
        }

      # Transport error
      Map.has_key?(err, :reason) or Map.has_key?(err, "reason") ->
        reason = get(err, :reason)

        %__MODULE__{
          message: "Transport error: #{truncate(inspect(reason))}",
          reason: reason,
          type: :transport,
          response: err
        }

      # Unknown
      true ->
        %__MODULE__{
          message: "Unknown error: #{truncate(inspect(err))}",
          type: :unknown,
          response: err
        }
    end
  end

  def exception(%__MODULE__{} = error), do: error

  def exception(other) do
    %__MODULE__{
      message: "Unknown error: #{truncate(inspect(other))}",
      type: :unknown,
      response: other
    }
  end

  defp from_explicit_type(err) do
    type = get(err, :type)
    status = get(err, :status_code)

    %__MODULE__{
      message: truncate(get(err, :message)) || default_message(type),
      type: type,
      code: get(err, :code),
      data: get(err, :data),
      status_code: status,
      reason: get(err, :reason),
      retry_after: get(err, :retry_after),
      statuses: get(err, :statuses),
      response: get(err, :response) || err
    }
  end

  defp default_message(:exchange), do: "Exchange request rejected"
  defp default_message(:partial_rejection), do: "Exchange request partially rejected"
  defp default_message(:rate_limited), do: "Rate limited"
  defp default_message(type), do: "Error: #{inspect(type)}"

  defp get(map, key) when is_atom(key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(key))
    end
  end

  defp truncate(nil), do: nil

  defp truncate(value) when is_binary(value) do
    if byte_size(value) > @max_message_bytes do
      binary_part(value, 0, @max_message_bytes) <> "... (truncated)"
    else
      value
    end
  end

  defp truncate(value), do: truncate(inspect(value))
end
