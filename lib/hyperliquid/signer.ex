defmodule Hyperliquid.Signer do
  version = Mix.Project.config()[:version]

  use RustlerPrecompiled,
    otp_app: :hyperliquid,
    crate: "signer_nif",
    # The crate is named signer_nif but lives in native/signer, so the default
    # native/<crate> lookup used by force_build cannot find it.
    path: "native/signer",
    base_url: "https://github.com/skedzior/hyperliquid/releases/download/v#{version}",
    # Build `native/signer` from source when either the env var is set or
    # `config :rustler_precompiled, :force_build, hyperliquid: true` is present
    # (config/dev.exs and config/test.exs both set it, so local Rust edits take
    # effect without a release). Consumers of the Hex package keep using the
    # precompiled artifacts and need no Rust toolchain.
    force_build:
      System.get_env("HYPERLIQUID_BUILD_NIF") in ["1", "true"] or
        Application.compile_env(:rustler_precompiled, [:force_build, :hyperliquid], false),
    version: version,
    targets: ~w(
      aarch64-apple-darwin
      aarch64-unknown-linux-gnu
      x86_64-apple-darwin
      x86_64-unknown-linux-gnu
      aarch64-unknown-linux-musl
      x86_64-unknown-linux-musl
      x86_64-pc-windows-gnu
      x86_64-pc-windows-msvc
    ),
    nif_versions: ["2.15", "2.16", "2.17"]

  # Standard NIF fallback pattern: :erlang.nif_error/1 raises when the NIF
  # binary hasn't been loaded. At runtime, these functions are replaced by
  # the Rust NIF implementations via @on_load.
  def compute_connection_id(_action_json, _nonce, _vault_address),
    do: :erlang.nif_error(:nif_not_loaded)

  def compute_connection_id_ex(_action_json, _nonce, _vault_address, _expires_after),
    do: :erlang.nif_error(:nif_not_loaded)

  def sign_exchange_action(_pk, _action_json, _nonce, _is_mainnet, _vault_addr),
    do: :erlang.nif_error(:nif_not_loaded)

  def sign_exchange_action_ex(
        _pk,
        _action_json,
        _nonce,
        _is_mainnet,
        _vault_addr,
        _expires_after
      ),
      do: :erlang.nif_error(:nif_not_loaded)

  def sign_l1_action(_pk, _connection_id, _is_mainnet),
    do: :erlang.nif_error(:nif_not_loaded)

  def sign_usd_send(_pk, _dest, _amount, _time, _is_mainnet),
    do: :erlang.nif_error(:nif_not_loaded)

  def sign_withdraw3(_pk, _dest, _amount, _time, _is_mainnet),
    do: :erlang.nif_error(:nif_not_loaded)

  def sign_spot_send(_pk, _dest, _token, _amount, _time, _is_mainnet),
    do: :erlang.nif_error(:nif_not_loaded)

  def sign_approve_builder_fee(_pk, _builder, _max_fee_rate, _nonce, _is_mainnet),
    do: :erlang.nif_error(:nif_not_loaded)

  def sign_approve_agent(_pk, _agent_addr, _agent_name, _nonce, _is_mainnet),
    do: :erlang.nif_error(:nif_not_loaded)

  def sign_multi_sig_action_ex(
        _pk,
        _action_json,
        _nonce,
        _is_mainnet,
        _vault_addr,
        _expires_after
      ),
      do: :erlang.nif_error(:nif_not_loaded)

  def sign_typed_data(_pk, _domain_json, _types_json, _message_json, _primary_type),
    do: :erlang.nif_error(:nif_not_loaded)

  def to_checksum_address(_addr),
    do: :erlang.nif_error(:nif_not_loaded)

  def derive_address(_private_key_hex),
    do: :erlang.nif_error(:nif_not_loaded)
end
