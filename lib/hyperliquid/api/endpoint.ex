defmodule Hyperliquid.Api.Endpoint do
  @moduledoc """
  DSL for defining API endpoints with automatic request/response handling.

  This macro reduces boilerplate while preserving explicit Ecto schemas for
  response validation and type safety.

  ## Usage

  ### Simple endpoint (no parameters)

      defmodule Hyperliquid.Api.Info.AllMids do
        use Hyperliquid.Api.Endpoint,
          type: :info,
          request: %{type: "allMids"},
          rate_limit_cost: 2

        @primary_key false
        embedded_schema do
          field :mids, :map
        end

        def changeset(struct \\\\ %__MODULE__{}, attrs) do
          # Your validation logic
        end

        # Optional domain helpers
        def get_mid(%__MODULE__{mids: mids}, coin), do: Map.fetch(mids, coin)
      end

  ### Parametrized endpoint

      defmodule Hyperliquid.Api.Info.L2Book do
        use Hyperliquid.Api.Endpoint,
          type: :info,
          request_type: "l2Book",
          params: [coin: :required],
          optional_params: [:nSigFigs, :mantissa],
          rate_limit_cost: 20

        # Schema and changeset...

        # Optional: preprocess data before validation
        def preprocess(data), do: transform_levels(data)
      end

  ## Generated Functions

  The macro generates:

  - `build_request/0` or `build_request/1,2` - Build the request payload
  - `request/0` or `request/1,2` - Make HTTP request and parse response
  - `request!/0` or `request!/1,2` - Bang variant that raises on error
  - `parse_response/1` - Parse and validate response (uses your changeset)
  - `rate_limit_cost/0` - Get the rate limit cost for this endpoint

  ## Options

  - `:type` - Required. `:info`, `:explorer`, or `:stats`
  - `:request` - Static request map (for no-param endpoints)
  - `:request_type` - The "type" field value (for parametrized endpoints)
  - `:params` - List of required parameters as atoms
  - `:optional_params` - List of optional parameters as atoms
  - `:rate_limit_cost` - Integer cost for rate limiting (default: 0)
  - `:doc` - Short description of the endpoint
  - `:returns` - Description of what the endpoint returns
  - `:raw_response` - Generate `request_raw/N` functions for raw API responses (no key transformation)
  - `:storage` - Storage configuration (see below)

  ## Storage Options

  The `:storage` option enables automatic persistence when using `fetch/N`:

  ### Postgres Storage

      storage: [
        postgres: [
          enabled: true,
          table: "blocks"
        ]
      ]

  ### Postgres with Upsert (for mutable data)

      storage: [
        postgres: [
          enabled: true,
          table: "perp_dexs",
          extract: :dexs,                    # Extract nested records from this field
          conflict_target: :name,            # Unique key for upsert
          on_conflict: {:replace, [          # Fields to update on conflict
            :full_name, :deployer, :asset_to_streaming_oi_cap, :updated_at
          ]}
        ],
        context_params: []                   # Request params to merge (default: [:user])
      ]

  ### Cache Storage

      storage: [
        cache: [
          enabled: true,
          ttl: :timer.minutes(5),
          key_pattern: "block:{{block_number}}"
        ]
      ]

  Both backends can be enabled simultaneously. Use `fetch/N` instead of
  `request/N` to automatically persist results.

  ## Rate Limit Weights (per IP, 1200/min aggregate)

  - Weight 2: l2Book, allMids, clearinghouseState, orderStatus, spotClearinghouseState, exchangeStatus
  - Weight 20: Most info endpoints (default)
  - Weight 60: userRole
  - Exchange actions: 1 + floor(batch_length / 40)

  ## Introspection

  Each endpoint module provides:
  - `__endpoint_info__/0` - Returns metadata about the endpoint
  - `rate_limit_cost/0` - Returns the rate limit weight

  ## Telemetry Events

  The DSL emits telemetry events for observability:

  - `[:hyperliquid, :api, :request, :start]` - When request begins
  - `[:hyperliquid, :api, :request, :stop]` - When request completes successfully
  - `[:hyperliquid, :api, :request, :exception]` - When request fails

  Metadata includes: `endpoint`, `type`, `params`
  """

  defmacro __using__(opts) do
    quote do
      use Ecto.Schema
      import Ecto.Changeset
      @behaviour Hyperliquid.Api.EndpointBehaviour

      @endpoint_opts unquote(opts)

      @before_compile Hyperliquid.Api.Endpoint
    end
  end

  # ===================== Multi-Table Storage Parsing =====================

  @doc false
  defp parse_postgres_tables(postgres_config) when is_list(postgres_config) do
    cond do
      # New format: explicit tables array
      tables = postgres_config[:tables] ->
        Enum.map(tables, &normalize_table_config/1)

      # New format: primary + additional tables
      postgres_config[:additional_tables] ->
        primary = build_primary_table_config(postgres_config)
        additional = Enum.map(postgres_config[:additional_tables], &normalize_table_config/1)
        [primary | additional]

      # Legacy format: single table (backwards compatible)
      postgres_config[:enabled] && postgres_config[:table] ->
        [normalize_table_config(postgres_config)]

      # No postgres config or not enabled
      true ->
        []
    end
  end

  defp parse_postgres_tables(_), do: []

  @doc false
  defp normalize_table_config(config) when is_map(config) do
    %{
      table: config[:table] || config["table"],
      extract: config[:extract] || config["extract"],
      conflict_target: config[:conflict_target] || config["conflict_target"],
      on_conflict: config[:on_conflict] || config["on_conflict"] || :nothing,
      transform: config[:transform] || config["transform"],
      fields: config[:fields] || config["fields"]
    }
  end

  defp normalize_table_config(config) when is_list(config) do
    normalize_table_config(Map.new(config))
  end

  @doc false
  defp build_primary_table_config(postgres_config) do
    %{
      table: postgres_config[:table],
      extract: postgres_config[:extract],
      conflict_target: postgres_config[:conflict_target],
      on_conflict: postgres_config[:on_conflict] || :nothing,
      transform: postgres_config[:transform],
      fields: postgres_config[:fields]
    }
  end

  # Legacy helper functions for backwards compatibility
  @doc false
  defp get_primary_table([%{table: table} | _]), do: table
  defp get_primary_table(_), do: nil

  @doc false
  defp get_primary_extract([%{extract: extract} | _]), do: extract
  defp get_primary_extract(_), do: nil

  @doc false
  defp get_primary_conflict_target([%{conflict_target: target} | _]), do: target
  defp get_primary_conflict_target(_), do: nil

  @doc false
  defp get_primary_on_conflict([%{on_conflict: on_conflict} | _]), do: on_conflict
  defp get_primary_on_conflict(_), do: :nothing

  defmacro __before_compile__(env) do
    opts = Module.get_attribute(env.module, :endpoint_opts)

    type = Keyword.fetch!(opts, :type)
    rate_limit_cost = Keyword.get(opts, :rate_limit_cost, 0)

    # Determine if this is a simple or parametrized endpoint
    static_request = Keyword.get(opts, :request)
    request_type = Keyword.get(opts, :request_type)
    params = Keyword.get(opts, :params, [])
    optional_params = Keyword.get(opts, :optional_params, [])

    # Documentation options
    doc = Keyword.get(opts, :doc, "")
    returns = Keyword.get(opts, :returns, "")

    # Storage options
    storage = Keyword.get(opts, :storage, [])
    postgres_config = Keyword.get(storage, :postgres, [])
    cache_config = Keyword.get(storage, :cache, [])

    # NEW: Parse multi-table configuration
    postgres_tables = parse_postgres_tables(postgres_config)
    postgres_enabled = postgres_tables != []

    # Legacy single-table config (for backwards compatibility with storage functions)
    _postgres_table = get_primary_table(postgres_tables)
    _postgres_extract = get_primary_extract(postgres_tables)
    _postgres_conflict_target = get_primary_conflict_target(postgres_tables)
    _postgres_on_conflict = get_primary_on_conflict(postgres_tables)

    # context_params: which request params to merge into stored records (default [:user])
    context_params = Keyword.get(storage, :context_params, [:user])

    cache_enabled = Keyword.get(cache_config, :enabled, false)
    cache_ttl = Keyword.get(cache_config, :ttl)
    cache_key_pattern = Keyword.get(cache_config, :key_pattern)

    # Check if module defines preprocess/1
    has_preprocess = Module.defines?(env.module, {:preprocess, 1})

    # Check if module defines its own build_request (custom override)
    build_request_arity =
      if Enum.empty?(optional_params), do: length(params), else: length(params) + 1

    has_custom_build_request = Module.defines?(env.module, {:build_request, build_request_arity})

    # Check if module defines its own parse_response (custom override)
    has_custom_parse_response = Module.defines?(env.module, {:parse_response, 1})

    # Check if module defines its own request clauses (e.g. convenience overloads)
    # If so, the module must provide its own function heads with defaults
    request_arity =
      if Enum.empty?(optional_params), do: length(params), else: length(params) + 1

    has_custom_request = Module.defines?(env.module, {:request, request_arity})

    # Raw response option - generates request_raw/N functions
    raw_response = Keyword.get(opts, :raw_response, true)

    endpoint_name = if static_request, do: static_request[:type], else: request_type

    # Generate endpoint info function
    info_ast =
      quote do
        @doc """
        Returns metadata about this endpoint.

        ## Example

            iex> #{inspect(__MODULE__)}.__endpoint_info__()
            %{
              endpoint: "#{unquote(endpoint_name)}",
              type: #{inspect(unquote(type))},
              rate_limit_cost: #{unquote(rate_limit_cost)},
              params: #{inspect(unquote(params))},
              optional_params: #{inspect(unquote(optional_params))},
              doc: "#{unquote(doc)}",
              returns: "#{unquote(returns)}"
            }
        """
        @impl Hyperliquid.Api.EndpointBehaviour
        def __endpoint_info__ do
          %{
            endpoint: unquote(endpoint_name),
            type: unquote(type),
            rate_limit_cost: unquote(rate_limit_cost),
            params: unquote(params),
            optional_params: unquote(optional_params),
            doc: unquote(doc),
            returns: unquote(returns),
            module: __MODULE__
          }
        end
      end

    endpoint_ast =
      cond do
        type == :stats ->
          generate_stats_endpoint(
            request_type,
            rate_limit_cost,
            has_preprocess,
            has_custom_parse_response
          )

        static_request ->
          generate_simple_endpoint(
            type,
            static_request,
            rate_limit_cost,
            has_preprocess,
            has_custom_parse_response
          )

        true ->
          generate_parametrized_endpoint(
            type,
            request_type,
            params,
            optional_params,
            rate_limit_cost,
            has_preprocess,
            has_custom_build_request,
            has_custom_parse_response,
            has_custom_request
          )
      end

    # Generate storage functions
    storage_ast =
      generate_storage_functions(
        context_params,
        postgres_tables,
        cache_enabled,
        cache_ttl,
        cache_key_pattern
      )

    # Generate fetch functions (request + persist)
    fetch_ast =
      cond do
        type == :stats ->
          generate_stats_fetch(postgres_enabled or cache_enabled)

        static_request ->
          generate_simple_fetch(postgres_enabled or cache_enabled)

        true ->
          generate_parametrized_fetch(params, optional_params, postgres_enabled or cache_enabled)
      end

    # Generate raw response functions if enabled
    raw_ast =
      if raw_response do
        generate_raw_functions(type, static_request, request_type, params, optional_params)
      else
        quote do
        end
      end

    # Combine all
    quote do
      unquote(info_ast)
      unquote(endpoint_ast)
      unquote(storage_ast)
      unquote(fetch_ast)
      unquote(raw_ast)
    end
  end

  defp generate_stats_endpoint(
         endpoint_name,
         rate_limit_cost,
         has_preprocess,
         _has_custom_parse_response
       ) do
    request_body =
      if has_preprocess do
        quote do
          metadata = %{
            module: __MODULE__,
            endpoint: unquote(endpoint_name),
            request_type: unquote(endpoint_name),
            type: :stats,
            params: %{}
          }

          start_time = System.monotonic_time()

          :telemetry.execute(
            [:hyperliquid, :api, :request, :start],
            %{system_time: System.system_time()},
            metadata
          )

          result =
            with {:ok, data} <- Hyperliquid.Transport.Http.stats_request(unquote(endpoint_name)) do
              data = preprocess(data)
              parse_response(data)
            end

          duration = System.monotonic_time() - start_time

          case result do
            {:ok, _} ->
              :telemetry.execute(
                [:hyperliquid, :api, :request, :stop],
                %{duration: duration},
                Map.put(metadata, :result, :ok)
              )

            {:error, reason} ->
              :telemetry.execute(
                [:hyperliquid, :api, :request, :exception],
                %{duration: duration},
                Map.merge(metadata, %{result: :error, reason: reason})
              )
          end

          result
        end
      else
        quote do
          metadata = %{
            module: __MODULE__,
            endpoint: unquote(endpoint_name),
            request_type: unquote(endpoint_name),
            type: :stats,
            params: %{}
          }

          start_time = System.monotonic_time()

          :telemetry.execute(
            [:hyperliquid, :api, :request, :start],
            %{system_time: System.system_time()},
            metadata
          )

          result =
            with {:ok, data} <- Hyperliquid.Transport.Http.stats_request(unquote(endpoint_name)) do
              parse_response(data)
            end

          duration = System.monotonic_time() - start_time

          case result do
            {:ok, _} ->
              :telemetry.execute(
                [:hyperliquid, :api, :request, :stop],
                %{duration: duration},
                Map.put(metadata, :result, :ok)
              )

            {:error, reason} ->
              :telemetry.execute(
                [:hyperliquid, :api, :request, :exception],
                %{duration: duration},
                Map.merge(metadata, %{result: :error, reason: reason})
              )
          end

          result
        end
      end

    quote do
      @doc "Make the API request and parse the response."
      @spec request() :: {:ok, t()} | {:error, term()}
      def request do
        unquote(request_body)
      end

      @doc "Make the API request, raising on error."
      @spec request!() :: t()
      def request! do
        case request() do
          {:ok, result} ->
            result

          {:error, %Ecto.Changeset{} = changeset} ->
            raise Hyperliquid.Error, changeset_errors(changeset)

          {:error, error} ->
            raise Hyperliquid.Error, error
        end
      end

      @doc "Parse and validate the API response."
      @spec parse_response(map()) :: {:ok, t()} | {:error, term()}
      def parse_response(data) when is_map(data) do
        changeset(%__MODULE__{}, data)
        |> apply_action(:validate)
      end

      def parse_response(_), do: {:error, :invalid_response_format}

      @doc "Get the rate limit cost for this endpoint."
      @spec rate_limit_cost() :: non_neg_integer()
      def rate_limit_cost, do: unquote(rate_limit_cost)

      defp changeset_errors(changeset) do
        Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
          Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
            opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
          end)
        end)
      end
    end
  end

  defp generate_simple_endpoint(
         type,
         request,
         rate_limit_cost,
         has_preprocess,
         _has_custom_parse_response
       ) do
    http_function = get_http_function(type)
    endpoint_name = request[:type] || "unknown"

    request_body =
      if has_preprocess do
        quote do
          metadata = %{
            module: __MODULE__,
            endpoint: unquote(endpoint_name),
            request_type: unquote(endpoint_name),
            type: unquote(type),
            params: %{}
          }

          start_time = System.monotonic_time()

          :telemetry.execute(
            [:hyperliquid, :api, :request, :start],
            %{system_time: System.system_time()},
            metadata
          )

          result =
            with {:ok, data} <- Hyperliquid.Transport.Http.unquote(http_function)(build_request()) do
              data = preprocess(data)
              parse_response(data)
            end

          duration = System.monotonic_time() - start_time

          case result do
            {:ok, _} ->
              :telemetry.execute(
                [:hyperliquid, :api, :request, :stop],
                %{duration: duration},
                Map.put(metadata, :result, :ok)
              )

            {:error, reason} ->
              :telemetry.execute(
                [:hyperliquid, :api, :request, :exception],
                %{duration: duration},
                Map.merge(metadata, %{result: :error, reason: reason})
              )
          end

          result
        end
      else
        quote do
          metadata = %{
            module: __MODULE__,
            endpoint: unquote(endpoint_name),
            request_type: unquote(endpoint_name),
            type: unquote(type),
            params: %{}
          }

          start_time = System.monotonic_time()

          :telemetry.execute(
            [:hyperliquid, :api, :request, :start],
            %{system_time: System.system_time()},
            metadata
          )

          result =
            with {:ok, data} <- Hyperliquid.Transport.Http.unquote(http_function)(build_request()) do
              parse_response(data)
            end

          duration = System.monotonic_time() - start_time

          case result do
            {:ok, _} ->
              :telemetry.execute(
                [:hyperliquid, :api, :request, :stop],
                %{duration: duration},
                Map.put(metadata, :result, :ok)
              )

            {:error, reason} ->
              :telemetry.execute(
                [:hyperliquid, :api, :request, :exception],
                %{duration: duration},
                Map.merge(metadata, %{result: :error, reason: reason})
              )
          end

          result
        end
      end

    quote do
      @doc "Build the request payload."
      @spec build_request() :: map()
      def build_request do
        unquote(Macro.escape(request))
      end

      @doc "Make the API request and parse the response."
      @spec request() :: {:ok, t()} | {:error, term()}
      def request do
        unquote(request_body)
      end

      @doc "Make the API request, raising on error."
      @spec request!() :: t()
      def request! do
        case request() do
          {:ok, result} ->
            result

          {:error, %Ecto.Changeset{} = changeset} ->
            raise Hyperliquid.Error, changeset_errors(changeset)

          {:error, error} ->
            raise Hyperliquid.Error, error
        end
      end

      @doc "Parse and validate the API response."
      @spec parse_response(map()) :: {:ok, t()} | {:error, term()}
      def parse_response(data) when is_map(data) do
        changeset(%__MODULE__{}, data)
        |> apply_action(:validate)
      end

      def parse_response(_), do: {:error, :invalid_response_format}

      @doc "Get the rate limit cost for this endpoint."
      @spec rate_limit_cost() :: non_neg_integer()
      def rate_limit_cost, do: unquote(rate_limit_cost)

      defp changeset_errors(changeset) do
        Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
          Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
            opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
          end)
        end)
      end
    end
  end

  defp generate_parametrized_endpoint(
         type,
         request_type,
         params,
         optional_params,
         rate_limit_cost,
         has_preprocess,
         has_custom_build_request,
         has_custom_parse_response,
         has_custom_request
       ) do
    http_function = get_http_function(type)

    # Generate function arguments
    required_args = Enum.map(params, fn param -> Macro.var(param, nil) end)

    # Build the request map construction
    request_map_ast = build_request_map_ast(request_type, params, optional_params)

    # Build params map for telemetry
    params_map_ast =
      Enum.map(params, fn param ->
        {param, Macro.var(param, nil)}
      end)

    if Enum.empty?(optional_params) do
      # No optional params - simpler signature
      request_body =
        if has_preprocess do
          quote do
            metadata = %{
              module: __MODULE__,
              endpoint: unquote(request_type),
              request_type: unquote(request_type),
              type: unquote(type),
              params: Map.new(unquote(params_map_ast))
            }

            start_time = System.monotonic_time()

            :telemetry.execute(
              [:hyperliquid, :api, :request, :start],
              %{system_time: System.system_time()},
              metadata
            )

            result =
              with {:ok, data} <-
                     Hyperliquid.Transport.Http.unquote(http_function)(
                       build_request(unquote_splicing(required_args))
                     ) do
                data = preprocess(data)
                parse_response(data)
              end

            duration = System.monotonic_time() - start_time

            case result do
              {:ok, _} ->
                :telemetry.execute(
                  [:hyperliquid, :api, :request, :stop],
                  %{duration: duration},
                  Map.put(metadata, :result, :ok)
                )

              {:error, reason} ->
                :telemetry.execute(
                  [:hyperliquid, :api, :request, :exception],
                  %{duration: duration},
                  Map.merge(metadata, %{result: :error, reason: reason})
                )
            end

            result
          end
        else
          quote do
            metadata = %{
              module: __MODULE__,
              endpoint: unquote(request_type),
              request_type: unquote(request_type),
              type: unquote(type),
              params: Map.new(unquote(params_map_ast))
            }

            start_time = System.monotonic_time()

            :telemetry.execute(
              [:hyperliquid, :api, :request, :start],
              %{system_time: System.system_time()},
              metadata
            )

            result =
              with {:ok, data} <-
                     Hyperliquid.Transport.Http.unquote(http_function)(
                       build_request(unquote_splicing(required_args))
                     ) do
                parse_response(data)
              end

            duration = System.monotonic_time() - start_time

            case result do
              {:ok, _} ->
                :telemetry.execute(
                  [:hyperliquid, :api, :request, :stop],
                  %{duration: duration},
                  Map.put(metadata, :result, :ok)
                )

              {:error, reason} ->
                :telemetry.execute(
                  [:hyperliquid, :api, :request, :exception],
                  %{duration: duration},
                  Map.merge(metadata, %{result: :error, reason: reason})
                )
            end

            result
          end
        end

      build_request_ast =
        unless has_custom_build_request do
          quote do
            @doc "Build the request payload."
            @spec build_request(unquote_splicing(param_typespecs(params))) :: map()
            def build_request(unquote_splicing(required_args)) do
              unquote(request_map_ast)
            end
          end
        end

      parse_response_ast =
        unless has_custom_parse_response do
          quote do
            @doc "Parse and validate the API response."
            @spec parse_response(map()) :: {:ok, t()} | {:error, term()}
            def parse_response(data) when is_map(data) do
              changeset(%__MODULE__{}, data)
              |> apply_action(:validate)
            end

            def parse_response(_), do: {:error, :invalid_response_format}
          end
        end

      quote do
        unquote(build_request_ast)

        @doc "Make the API request and parse the response."
        @spec request(unquote_splicing(param_typespecs(params))) :: {:ok, t()} | {:error, term()}
        def request(unquote_splicing(required_args)) do
          unquote(request_body)
        end

        @doc "Make the API request, raising on error."
        @spec request!(unquote_splicing(param_typespecs(params))) :: t()
        def request!(unquote_splicing(required_args)) do
          case request(unquote_splicing(required_args)) do
            {:ok, result} ->
              result

            {:error, %Ecto.Changeset{} = changeset} ->
              raise Hyperliquid.Error, changeset_errors(changeset)

            {:error, error} ->
              raise Hyperliquid.Error, error
          end
        end

        unquote(parse_response_ast)

        @doc "Get the rate limit cost for this endpoint."
        @spec rate_limit_cost() :: non_neg_integer()
        def rate_limit_cost, do: unquote(rate_limit_cost)

        defp changeset_errors(changeset) do
          Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
            Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
              opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
            end)
          end)
        end
      end
    else
      # Has optional params - use opts keyword list
      request_map_with_opts_ast =
        build_request_map_with_opts_ast(request_type, params, optional_params)

      request_body_with_opts =
        if has_preprocess do
          quote do
            metadata = %{
              module: __MODULE__,
              endpoint: unquote(request_type),
              request_type: unquote(request_type),
              type: unquote(type),
              params: Map.new(unquote(params_map_ast))
            }

            start_time = System.monotonic_time()

            :telemetry.execute(
              [:hyperliquid, :api, :request, :start],
              %{system_time: System.system_time()},
              metadata
            )

            result =
              with {:ok, data} <-
                     Hyperliquid.Transport.Http.unquote(http_function)(
                       build_request(unquote_splicing(required_args), opts)
                     ) do
                data = preprocess(data)
                parse_response(data)
              end

            duration = System.monotonic_time() - start_time

            case result do
              {:ok, _} ->
                :telemetry.execute(
                  [:hyperliquid, :api, :request, :stop],
                  %{duration: duration},
                  Map.put(metadata, :result, :ok)
                )

              {:error, reason} ->
                :telemetry.execute(
                  [:hyperliquid, :api, :request, :exception],
                  %{duration: duration},
                  Map.merge(metadata, %{result: :error, reason: reason})
                )
            end

            result
          end
        else
          quote do
            metadata = %{
              module: __MODULE__,
              endpoint: unquote(request_type),
              request_type: unquote(request_type),
              type: unquote(type),
              params: Map.new(unquote(params_map_ast))
            }

            start_time = System.monotonic_time()

            :telemetry.execute(
              [:hyperliquid, :api, :request, :start],
              %{system_time: System.system_time()},
              metadata
            )

            result =
              with {:ok, data} <-
                     Hyperliquid.Transport.Http.unquote(http_function)(
                       build_request(unquote_splicing(required_args), opts)
                     ) do
                parse_response(data)
              end

            duration = System.monotonic_time() - start_time

            case result do
              {:ok, _} ->
                :telemetry.execute(
                  [:hyperliquid, :api, :request, :stop],
                  %{duration: duration},
                  Map.put(metadata, :result, :ok)
                )

              {:error, reason} ->
                :telemetry.execute(
                  [:hyperliquid, :api, :request, :exception],
                  %{duration: duration},
                  Map.merge(metadata, %{result: :error, reason: reason})
                )
            end

            result
          end
        end

      build_request_with_opts_ast =
        unless has_custom_build_request do
          quote do
            @doc "Build the request payload."
            @spec build_request(unquote_splicing(param_typespecs(params)), keyword()) :: map()
            def build_request(unquote_splicing(required_args), opts \\ []) do
              unquote(request_map_with_opts_ast)
            end
          end
        end

      parse_response_with_opts_ast =
        unless has_custom_parse_response do
          quote do
            @doc "Parse and validate the API response."
            @spec parse_response(map()) :: {:ok, t()} | {:error, term()}
            def parse_response(data) when is_map(data) do
              changeset(%__MODULE__{}, data)
              |> apply_action(:validate)
            end

            def parse_response(_), do: {:error, :invalid_response_format}
          end
        end

      # When the module defines its own request clauses (e.g. convenience overloads),
      # it must provide function heads with defaults. The DSL only generates body clauses.
      request_head_ast =
        unless has_custom_request do
          quote do
            def request(unquote_splicing(required_args), opts \\ [])
          end
        end

      request_bang_head_ast =
        unless has_custom_request do
          quote do
            def request!(unquote_splicing(required_args), opts \\ [])
          end
        end

      quote do
        unquote(build_request_with_opts_ast)

        @doc "Make the API request and parse the response."
        @spec request(unquote_splicing(param_typespecs(params)), keyword()) ::
                {:ok, t()} | {:error, term()}
        unquote(request_head_ast)

        def request(unquote_splicing(required_args), opts) do
          unquote(request_body_with_opts)
        end

        @doc "Make the API request, raising on error."
        @spec request!(unquote_splicing(param_typespecs(params)), keyword()) :: t()
        unquote(request_bang_head_ast)

        def request!(unquote_splicing(required_args), opts) do
          case request(unquote_splicing(required_args), opts) do
            {:ok, result} ->
              result

            {:error, %Ecto.Changeset{} = changeset} ->
              raise Hyperliquid.Error, changeset_errors(changeset)

            {:error, error} ->
              raise Hyperliquid.Error, error
          end
        end

        unquote(parse_response_with_opts_ast)

        @doc "Get the rate limit cost for this endpoint."
        @spec rate_limit_cost() :: non_neg_integer()
        def rate_limit_cost, do: unquote(rate_limit_cost)

        defp changeset_errors(changeset) do
          Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
            Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
              opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
            end)
          end)
        end
      end
    end
  end

  defp get_http_function(:info), do: :info_request
  defp get_http_function(:explorer), do: :explorer_request
  defp get_http_function(:stats), do: :stats_request

  defp param_typespecs(params) do
    Enum.map(params, fn _param ->
      quote do: term()
    end)
  end

  defp build_request_map_ast(request_type, params, _optional_params) do
    base_map = %{type: request_type}

    param_assignments =
      Enum.map(params, fn param ->
        {param, Macro.var(param, nil)}
      end)

    quote do
      unquote(Macro.escape(base_map))
      |> Map.merge(Map.new(unquote(param_assignments)))
    end
  end

  defp build_request_map_with_opts_ast(request_type, params, optional_params) do
    base_map = %{type: request_type}

    param_assignments =
      Enum.map(params, fn param ->
        {param, Macro.var(param, nil)}
      end)

    quote do
      base =
        unquote(Macro.escape(base_map))
        |> Map.merge(Map.new(unquote(param_assignments)))

      Enum.reduce(unquote(optional_params), base, fn param, acc ->
        case Keyword.get(opts, param) do
          nil -> acc
          value -> Map.put(acc, param, value)
        end
      end)
    end
  end

  # ===================== Storage Functions =====================

  defp generate_storage_functions(
         context_params,
         postgres_tables,
         cache_enabled,
         cache_ttl,
         cache_key_pattern
       ) do
    postgres_enabled = postgres_tables != []
    # Extract primary table info for legacy functions
    primary_table = get_primary_table(postgres_tables)
    primary_extract = get_primary_extract(postgres_tables)
    primary_conflict_target = get_primary_conflict_target(postgres_tables)
    primary_on_conflict = get_primary_on_conflict(postgres_tables)

    quote do
      @doc """
      Returns postgres table configurations (multi-table support).
      """
      def __postgres_tables__, do: unquote(Macro.escape(postgres_tables))

      @doc """
      Returns storage configuration for this endpoint.
      """
      def __storage_config__ do
        %{
          postgres: %{
            enabled: unquote(postgres_enabled),
            tables: __postgres_tables__(),
            # Legacy single-table fields (primary table)
            table: unquote(primary_table),
            extract: unquote(primary_extract),
            conflict_target: unquote(primary_conflict_target),
            on_conflict: unquote(primary_on_conflict)
          },
          cache: %{
            enabled: unquote(cache_enabled),
            ttl: unquote(cache_ttl),
            key_pattern: unquote(cache_key_pattern)
          }
        }
      end

      @doc "Returns true if any storage backend is enabled."
      def storage_enabled?, do: unquote(postgres_enabled) or unquote(cache_enabled)

      @doc "Returns true if postgres storage is enabled."
      def postgres_enabled?, do: unquote(postgres_enabled)

      @doc "Returns true if cache storage is enabled."
      def cache_enabled?, do: unquote(cache_enabled)

      @doc "Returns the postgres table name if configured (primary table for legacy support)."
      def postgres_table, do: unquote(primary_table)

      @doc "Returns the upsert config for postgres (primary table for legacy support)."
      def postgres_upsert_config do
        conflict_target = unquote(primary_conflict_target)
        on_conflict = unquote(primary_on_conflict)

        if conflict_target do
          %{conflict_target: conflict_target, on_conflict: on_conflict}
        else
          nil
        end
      end

      @doc "Returns the cache TTL if configured."
      def cache_ttl, do: unquote(cache_ttl)

      @doc """
      Build a cache key from response data using the configured pattern.
      Returns `nil` if cache is not enabled or no pattern configured.
      """
      def build_cache_key(data) do
        pattern = unquote(cache_key_pattern)

        if unquote(cache_enabled) and pattern do
          Hyperliquid.Api.Endpoint.interpolate_key_pattern(pattern, data)
        else
          nil
        end
      end

      @doc false
      def extract_records(data) do
        extract_field = unquote(primary_extract)
        context_fields = unquote(context_params)

        # Get context values from parent data (request params merged by fetch)
        context =
          Enum.reduce(context_fields, %{}, fn field, acc ->
            value = Map.get(data, field) || Map.get(data, to_string(field))
            if value, do: Map.put(acc, field, value), else: acc
          end)

        if extract_field do
          records =
            case data do
              %{^extract_field => recs} when is_list(recs) -> recs
              map when is_map(map) -> Map.get(map, extract_field, [data])
              _ -> [data]
            end

          # Merge context into each record
          Enum.map(records, fn record ->
            Map.merge(context, record)
          end)
        else
          [data]
        end
      end

      @doc false
      def extract_postgres_fields(data), do: data
      @doc false
      def extract_cache_fields(data), do: data
    end
  end

  # ===================== Fetch Functions (request + persist) =====================

  defp generate_simple_fetch(storage_enabled) do
    if storage_enabled do
      quote do
        @doc """
        Fetch data and persist to configured storage backends.

        This calls `request/0` and then stores the result using Storage.Writer.
        """
        @spec fetch() :: {:ok, t()} | {:error, term()}
        def fetch do
          case request() do
            {:ok, result} ->
              Hyperliquid.Storage.Writer.store_async(__MODULE__, struct_to_map(result))
              {:ok, result}

            error ->
              error
          end
        end

        @doc "Fetch data and persist. Raises on error."
        @spec fetch!() :: t()
        def fetch! do
          result = request!()
          Hyperliquid.Storage.Writer.store_async(__MODULE__, struct_to_map(result))
          result
        end

        defp struct_to_map(%_{} = struct) do
          struct
          |> Map.from_struct()
          |> Map.drop([:__meta__])
        end

        defp struct_to_map(data), do: data
      end
    else
      quote do
        @doc "Fetch is an alias for request when no storage is configured."
        def fetch, do: request()
        def fetch!, do: request!()
      end
    end
  end

  defp generate_stats_fetch(storage_enabled) do
    # Stats endpoints have same signature as simple endpoints
    generate_simple_fetch(storage_enabled)
  end

  defp generate_parametrized_fetch(params, optional_params, storage_enabled) do
    param_vars = Enum.map(params, fn p -> Macro.var(p, nil) end)

    # Build AST to create a map of request params for merging into stored data
    param_map_pairs = Enum.map(params, fn p -> {p, Macro.var(p, nil)} end)

    if storage_enabled do
      if Enum.empty?(optional_params) do
        quote do
          @doc """
          Fetch data and persist to configured storage backends.

          This calls `request/N` and then stores the result using Storage.Writer.
          Request params are merged into stored data for cache key generation.
          """
          def fetch(unquote_splicing(param_vars)) do
            case request(unquote_splicing(param_vars)) do
              {:ok, result} ->
                # Merge request params into stored data for cache key/context
                # Context overwrites struct fields (e.g., id from params replaces nil from struct)
                request_context = Map.new(unquote(param_map_pairs))
                storage_data = Map.merge(struct_to_map(result), request_context)
                Hyperliquid.Storage.Writer.store_async(__MODULE__, storage_data)
                {:ok, result}

              error ->
                error
            end
          end

          @doc "Fetch data and persist. Raises on error."
          def fetch!(unquote_splicing(param_vars)) do
            result = request!(unquote_splicing(param_vars))
            # Context overwrites struct fields (e.g., id from params replaces nil from struct)
            request_context = Map.new(unquote(param_map_pairs))
            storage_data = Map.merge(struct_to_map(result), request_context)
            Hyperliquid.Storage.Writer.store_async(__MODULE__, storage_data)
            result
          end

          defp struct_to_map(%_{} = struct) do
            struct
            |> Map.from_struct()
            |> Map.drop([:__meta__])
          end

          defp struct_to_map(data), do: data
        end
      else
        quote do
          @doc """
          Fetch data and persist to configured storage backends.

          This calls `request/N` and then stores the result using Storage.Writer.
          Request params are merged into stored data for cache key generation.
          """
          def fetch(unquote_splicing(param_vars), opts \\ []) do
            case request(unquote_splicing(param_vars), opts) do
              {:ok, result} ->
                # Merge request params into stored data for cache key/context
                # Context overwrites struct fields (e.g., id from params replaces nil from struct)
                request_context = Map.new(unquote(param_map_pairs))
                storage_data = Map.merge(struct_to_map(result), request_context)
                Hyperliquid.Storage.Writer.store_async(__MODULE__, storage_data)
                {:ok, result}

              error ->
                error
            end
          end

          @doc "Fetch data and persist. Raises on error."
          def fetch!(unquote_splicing(param_vars), opts \\ []) do
            result = request!(unquote_splicing(param_vars), opts)
            # Context overwrites struct fields (e.g., id from params replaces nil from struct)
            request_context = Map.new(unquote(param_map_pairs))
            storage_data = Map.merge(struct_to_map(result), request_context)
            Hyperliquid.Storage.Writer.store_async(__MODULE__, storage_data)
            result
          end

          defp struct_to_map(%_{} = struct) do
            struct
            |> Map.from_struct()
            |> Map.drop([:__meta__])
          end

          defp struct_to_map(data), do: data
        end
      end
    else
      if Enum.empty?(optional_params) do
        quote do
          @doc "Fetch is an alias for request when no storage is configured."
          def fetch(unquote_splicing(param_vars)), do: request(unquote_splicing(param_vars))
          def fetch!(unquote_splicing(param_vars)), do: request!(unquote_splicing(param_vars))
        end
      else
        quote do
          @doc "Fetch is an alias for request when no storage is configured."
          def fetch(unquote_splicing(param_vars), opts \\ []),
            do: request(unquote_splicing(param_vars), opts)

          def fetch!(unquote_splicing(param_vars), opts \\ []),
            do: request!(unquote_splicing(param_vars), opts)
        end
      end
    end
  end

  # ===================== Raw Response Functions =====================

  defp generate_raw_functions(type, static_request, request_type, params, optional_params) do
    http_function = get_http_function(type)

    cond do
      type == :stats ->
        generate_stats_raw(request_type)

      static_request ->
        generate_simple_raw(http_function, static_request)

      true ->
        generate_parametrized_raw(http_function, request_type, params, optional_params)
    end
  end

  defp generate_stats_raw(endpoint_name) do
    quote do
      @doc "Make the API request and return the raw response map (no key transformation)."
      @spec request_raw() :: {:ok, map()} | {:error, term()}
      def request_raw do
        Hyperliquid.Transport.Http.stats_request(unquote(endpoint_name), raw: true)
      end

      @doc "Make the API request returning raw map, raising on error."
      @spec request_raw!() :: map()
      def request_raw! do
        case request_raw() do
          {:ok, result} -> result
          {:error, error} -> raise Hyperliquid.Error, error
        end
      end
    end
  end

  defp generate_simple_raw(http_function, _request) do
    quote do
      @doc "Make the API request and return the raw response map (no key transformation)."
      @spec request_raw() :: {:ok, map()} | {:error, term()}
      def request_raw do
        Hyperliquid.Transport.Http.unquote(http_function)(build_request(), raw: true)
      end

      @doc "Make the API request returning raw map, raising on error."
      @spec request_raw!() :: map()
      def request_raw! do
        case request_raw() do
          {:ok, result} -> result
          {:error, error} -> raise Hyperliquid.Error, error
        end
      end
    end
  end

  defp generate_parametrized_raw(http_function, _request_type, params, optional_params) do
    required_args = Enum.map(params, fn param -> Macro.var(param, nil) end)
    type_specs = param_typespecs(params)

    if Enum.empty?(optional_params) do
      quote do
        @doc "Make the API request and return the raw response map (no key transformation)."
        @spec request_raw(unquote_splicing(type_specs)) :: {:ok, map()} | {:error, term()}
        def request_raw(unquote_splicing(required_args)) do
          Hyperliquid.Transport.Http.unquote(http_function)(
            build_request(unquote_splicing(required_args)),
            raw: true
          )
        end

        @doc "Make the API request returning raw map, raising on error."
        @spec request_raw!(unquote_splicing(type_specs)) :: map()
        def request_raw!(unquote_splicing(required_args)) do
          case request_raw(unquote_splicing(required_args)) do
            {:ok, result} -> result
            {:error, error} -> raise Hyperliquid.Error, error
          end
        end
      end
    else
      quote do
        @doc "Make the API request and return the raw response map (no key transformation)."
        @spec request_raw(unquote_splicing(type_specs), keyword()) ::
                {:ok, map()} | {:error, term()}
        def request_raw(unquote_splicing(required_args), opts \\ []) do
          Hyperliquid.Transport.Http.unquote(http_function)(
            build_request(unquote_splicing(required_args), opts),
            raw: true
          )
        end

        @doc "Make the API request returning raw map, raising on error."
        @spec request_raw!(unquote_splicing(type_specs), keyword()) :: map()
        def request_raw!(unquote_splicing(required_args), opts \\ []) do
          case request_raw(unquote_splicing(required_args), opts) do
            {:ok, result} -> result
            {:error, error} -> raise Hyperliquid.Error, error
          end
        end
      end
    end
  end

  @doc """
  Interpolate a key pattern with data values.

  Replaces `{{field}}` placeholders with actual values.

  ## Examples

      iex> interpolate_key_pattern("block:{{block_number}}", %{block_number: 123})
      "block:123"
  """
  @spec interpolate_key_pattern(String.t(), map()) :: String.t()
  def interpolate_key_pattern(pattern, data) when is_binary(pattern) do
    Regex.replace(~r/\{\{(\w+)\}\}/, pattern, fn _, field ->
      value =
        Map.get(data, field) ||
          get_atom_key(data, field) ||
          "unknown"

      to_string(value)
    end)
  end

  defp get_atom_key(map, field) when is_binary(field) do
    field_atom = String.to_existing_atom(field)
    Map.get(map, field_atom)
  rescue
    ArgumentError -> nil
  end
end
