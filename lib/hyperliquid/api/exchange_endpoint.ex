defmodule Hyperliquid.Api.ExchangeEndpoint do
  @moduledoc """
  DSL for defining authenticated exchange endpoints with signing support.

  This macro reduces boilerplate for exchange actions while preserving
  explicit action building and signing logic.

  ## Usage

  ### Simple L1 Action (Noop, SetDisplayName)

      defmodule Hyperliquid.Api.Exchange.Noop do
        use Hyperliquid.Api.ExchangeEndpoint,
          action_type: "noop",
          signing: :l1

        # The DSL generates request/1
      end

  ### Simple L1 Action with params

      defmodule Hyperliquid.Api.Exchange.SetDisplayName do
        use Hyperliquid.Api.ExchangeEndpoint,
          action_type: "setDisplayName",
          signing: :l1

        def build_action(display_name) do
          %{type: "setDisplayName", displayName: display_name}
        end
      end

  ## Signing Strategies

  - `:exchange` - Full exchange action signing (orders, cancels)
  - `:l1` - L1 action signing via connection_id (noop, setDisplayName)

  ## Generated Functions

  For simple endpoints (no custom build_action):
  - `request/1` - Make signed request with private key
  - `request/2` - With opts (vault_address, etc.)

  ## Telemetry Events

  - `[:hyperliquid, :api, :exchange, :start]`
  - `[:hyperliquid, :api, :exchange, :stop]`
  - `[:hyperliquid, :api, :exchange, :exception]`
  """

  defmacro __using__(opts) do
    quote do
      @behaviour Hyperliquid.Api.EndpointBehaviour
      @exchange_opts unquote(opts)

      @before_compile Hyperliquid.Api.ExchangeEndpoint
    end
  end

  defmacro __before_compile__(env) do
    opts = Module.get_attribute(env.module, :exchange_opts)

    action_type = Keyword.fetch!(opts, :action_type)
    signing = Keyword.get(opts, :signing, :exchange)
    doc = Keyword.get(opts, :doc, "")
    returns = Keyword.get(opts, :returns, "")
    params = Keyword.get(opts, :params, [])
    optional_params = Keyword.get(opts, :optional_params, [:vault_address])
    rate_limit_cost = Keyword.get(opts, :rate_limit_cost, 1)

    # Check if module defines build_action
    has_build_action = Module.defines?(env.module, {:build_action, 1})

    # Generate endpoint info function
    info_ast =
      quote do
        @doc "Returns metadata about this endpoint."
        @impl Hyperliquid.Api.EndpointBehaviour
        def __endpoint_info__ do
          %{
            endpoint: unquote(action_type),
            type: :exchange,
            action_type: unquote(action_type),
            signing: unquote(signing),
            rate_limit_cost: unquote(rate_limit_cost),
            params: unquote(params),
            optional_params: unquote(optional_params),
            doc: unquote(doc),
            returns: unquote(returns),
            module: __MODULE__
          }
        end
      end

    endpoint_ast = generate_exchange_endpoint(action_type, signing, has_build_action)

    quote do
      unquote(info_ast)
      unquote(endpoint_ast)
    end
  end

  defp generate_exchange_endpoint(action_type, :l1, has_build_action) do
    if has_build_action do
      # Module provides build_action/1, generate request that uses it
      quote do
        @doc """
        Execute the exchange action.

        ## Parameters
        - `param` - Parameter passed to build_action/1
        - `opts` - Options (private_key, vault_address, etc.)

        ## Options
        - `:private_key` - Private key for signing (falls back to config)
        - `:vault_address` - Vault address for vault operations

        ## Breaking Change (v0.2.0)
        `private_key` was previously the first positional argument. It is now
        an option in the opts keyword list (`:private_key`).
        """
        def request(param, opts \\ []) do
          private_key = Hyperliquid.Api.Exchange.KeyUtils.resolve_private_key!(opts)
          action = build_action(param)
          execute_l1_action(private_key, action, opts)
        end

        @doc """
        Execute the exchange action (bang variant).

        Same as `request/2` but raises on error.
        """
        def request!(param, opts \\ []) do
          case request(param, opts) do
            {:ok, result} -> result
            {:error, reason} -> raise "Exchange request failed: #{inspect(reason)}"
          end
        end

        defp execute_l1_action(private_key, action, opts) do
          vault_address = Keyword.get(opts, :vault_address)
          nonce = System.system_time(:millisecond)
          expires_after = Hyperliquid.Config.expires_after()
          is_mainnet = Hyperliquid.Config.mainnet?()

          metadata = %{
            endpoint: unquote(action_type),
            type: :exchange,
            signing: :l1
          }

          start_time = System.monotonic_time()

          :telemetry.execute(
            [:hyperliquid, :api, :exchange, :start],
            %{system_time: System.system_time()},
            metadata
          )

          # The connection id is the keccak of the action's msgpack encoding, so
          # field order is part of the preimage. Canonicalize once and use the
          # same value for both the signature and the request body, otherwise the
          # bytes we hashed and the bytes we send can disagree.
          canonical_action = Hyperliquid.Api.ActionEncoder.canonicalize(action)

          result =
            with {:ok, action_json} <- Jason.encode(canonical_action),
                 {:ok, signature} <-
                   sign_l1_action(
                     private_key,
                     action_json,
                     nonce,
                     vault_address,
                     expires_after,
                     is_mainnet
                   ) do
              Hyperliquid.Transport.Http.exchange_request(
                canonical_action,
                signature,
                nonce,
                vault_address,
                expires_after
              )
            end

          duration = System.monotonic_time() - start_time

          case result do
            {:ok, _} ->
              :telemetry.execute(
                [:hyperliquid, :api, :exchange, :stop],
                %{duration: duration},
                Map.put(metadata, :result, :ok)
              )

            {:error, reason} ->
              :telemetry.execute(
                [:hyperliquid, :api, :exchange, :exception],
                %{duration: duration},
                Map.merge(metadata, %{result: :error, reason: reason})
              )
          end

          result
        end

        defp sign_l1_action(
               private_key,
               action_json,
               nonce,
               vault_address,
               expires_after,
               is_mainnet
             ) do
          connection_id =
            Hyperliquid.Signer.compute_connection_id_ex(
              action_json,
              nonce,
              vault_address,
              expires_after
            )

          case Hyperliquid.Signer.sign_l1_action(private_key, connection_id, is_mainnet) do
            %{"r" => r, "s" => s, "v" => v} -> {:ok, %{r: r, s: s, v: v}}
            error -> {:error, {:signing_error, error}}
          end
        end

        defp generate_nonce do
          System.system_time(:millisecond)
        end
      end
    else
      # No build_action, generate simple noop-style request
      quote do
        @doc """
        Execute the exchange action.

        ## Parameters
        - `opts` - Options (private_key, vault_address, etc.)

        ## Options
        - `:private_key` - Private key for signing (falls back to config)
        - `:vault_address` - Vault address for vault operations

        ## Breaking Change (v0.2.0)
        `private_key` was previously the first positional argument. It is now
        an option in the opts keyword list (`:private_key`).
        """
        def request(opts \\ []) do
          private_key = Hyperliquid.Api.Exchange.KeyUtils.resolve_private_key!(opts)
          action = %{type: unquote(action_type)}
          execute_l1_action(private_key, action, opts)
        end

        @doc """
        Execute the exchange action (bang variant).

        Same as `request/1` but raises on error.
        """
        def request!(opts \\ []) do
          case request(opts) do
            {:ok, result} -> result
            {:error, reason} -> raise "Exchange request failed: #{inspect(reason)}"
          end
        end

        defp execute_l1_action(private_key, action, opts) do
          vault_address = Keyword.get(opts, :vault_address)
          nonce = System.system_time(:millisecond)
          expires_after = Hyperliquid.Config.expires_after()
          is_mainnet = Hyperliquid.Config.mainnet?()

          metadata = %{
            endpoint: unquote(action_type),
            type: :exchange,
            signing: :l1
          }

          start_time = System.monotonic_time()

          :telemetry.execute(
            [:hyperliquid, :api, :exchange, :start],
            %{system_time: System.system_time()},
            metadata
          )

          # The connection id is the keccak of the action's msgpack encoding, so
          # field order is part of the preimage. Canonicalize once and use the
          # same value for both the signature and the request body, otherwise the
          # bytes we hashed and the bytes we send can disagree.
          canonical_action = Hyperliquid.Api.ActionEncoder.canonicalize(action)

          result =
            with {:ok, action_json} <- Jason.encode(canonical_action),
                 {:ok, signature} <-
                   sign_l1_action(
                     private_key,
                     action_json,
                     nonce,
                     vault_address,
                     expires_after,
                     is_mainnet
                   ) do
              Hyperliquid.Transport.Http.exchange_request(
                canonical_action,
                signature,
                nonce,
                vault_address,
                expires_after
              )
            end

          duration = System.monotonic_time() - start_time

          case result do
            {:ok, _} ->
              :telemetry.execute(
                [:hyperliquid, :api, :exchange, :stop],
                %{duration: duration},
                Map.put(metadata, :result, :ok)
              )

            {:error, reason} ->
              :telemetry.execute(
                [:hyperliquid, :api, :exchange, :exception],
                %{duration: duration},
                Map.merge(metadata, %{result: :error, reason: reason})
              )
          end

          result
        end

        defp sign_l1_action(
               private_key,
               action_json,
               nonce,
               vault_address,
               expires_after,
               is_mainnet
             ) do
          connection_id =
            Hyperliquid.Signer.compute_connection_id_ex(
              action_json,
              nonce,
              vault_address,
              expires_after
            )

          case Hyperliquid.Signer.sign_l1_action(private_key, connection_id, is_mainnet) do
            %{"r" => r, "s" => s, "v" => v} -> {:ok, %{r: r, s: s, v: v}}
            error -> {:error, {:signing_error, error}}
          end
        end

        defp generate_nonce do
          System.system_time(:millisecond)
        end
      end
    end
  end

  defp generate_exchange_endpoint(action_type, :exchange, _has_build_action) do
    # For :exchange signing, we expect the module to define more custom logic
    # This generates helper functions
    quote do
      @doc false
      def action_type, do: unquote(action_type)

      defp sign_exchange_action(private_key, action_json, nonce, vault_address, expires_after) do
        is_mainnet = Hyperliquid.Config.mainnet?()

        case Hyperliquid.Signer.sign_exchange_action_ex(
               private_key,
               action_json,
               nonce,
               is_mainnet,
               vault_address,
               expires_after
             ) do
          %{"r" => r, "s" => s, "v" => v} -> {:ok, %{r: r, s: s, v: v}}
          error -> {:error, {:signing_error, error}}
        end
      end

      defp generate_nonce do
        System.system_time(:millisecond)
      end

      defp emit_telemetry_start(metadata) do
        :telemetry.execute(
          [:hyperliquid, :api, :exchange, :start],
          %{system_time: System.system_time()},
          metadata
        )
      end

      defp emit_telemetry_stop(metadata, duration, result) do
        case result do
          {:ok, _} ->
            :telemetry.execute(
              [:hyperliquid, :api, :exchange, :stop],
              %{duration: duration},
              Map.put(metadata, :result, :ok)
            )

          {:error, reason} ->
            :telemetry.execute(
              [:hyperliquid, :api, :exchange, :exception],
              %{duration: duration},
              Map.merge(metadata, %{result: :error, reason: reason})
            )
        end
      end
    end
  end
end
