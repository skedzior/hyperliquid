defmodule Hyperliquid.Api.Exchange.UserSignedVectorsTest do
  @moduledoc """
  Cross-SDK vectors for the shared user-signed EIP-712 path.

  These assert the *module-level* path — `Hyperliquid.Api.Exchange.UserSigned`
  with the field lists the exchange modules declare — reproduces the signatures
  the official Python SDK produces, at **both** supported `signatureChainId`s
  (`0x66eee` / 421614, the default and the value nktkas and the Python SDK use,
  and `0xa4b1` / 42161, which the Hyperliquid frontend emits).

  Vectors come from the same generator as `test/signing_vectors_test.exs`
  (`scripts/gen_signing_vectors.py`); `signing_vectors_test.exs` drives
  `Signer.sign_typed_data/5` with hand-built JSON, whereas this file drives the
  helper the modules actually call, so a regression in the helper's domain,
  type-list or `hyperliquidChain` assembly turns these red.
  """

  use ExUnit.Case, async: false

  alias Hyperliquid.Api.Exchange.{
    CDeposit,
    ConvertToMultiSigUser,
    CWithdraw,
    LinkStakingUser,
    SendAsset,
    SendToEvmWithData,
    StakingLinkDisableTradingUser,
    TokenDelegate,
    UsdClassTransfer,
    UserDexAbstraction,
    UserPortfolioMargin,
    UserSetAbstraction,
    UserSigned
  }

  alias Hyperliquid.Config

  @priv_key "0x0123456789012345678901234567890123456789012345678901234567890123"
  @nonce 1_687_816_341_423
  @dest "0x5e9ee1089755c3435139848e47e6635505d5a13a"
  @validator "0x1d9470d4b963f552e6f671a81619d395877bf409"
  @user "0x1d9470d4b963f552e6f671a81619d395877bf409"
  @token "USDC:0xeb62eee3685fc4c43992febcd9e75443"
  @signers ~s({"authorizedUsers":["0x1d9470d4b963f552e6f671a81619d395877bf409"],"threshold":1})
  @wei 100_000_000
  @data "0xdeadbeef"

  setup do
    previous = Application.fetch_env(:hyperliquid, :signature_chain_id)

    on_exit(fn ->
      case previous do
        {:ok, v} -> Application.put_env(:hyperliquid, :signature_chain_id, v)
        :error -> Application.delete_env(:hyperliquid, :signature_chain_id)
      end
    end)

    :ok
  end

  defp with_chain_id(id, fun) do
    Application.put_env(:hyperliquid, :signature_chain_id, id)
    fun.()
  end

  # {name, primary_type, fields, message, sig_at_421614, sig_at_42161}
  @vectors [
    {"usdSend", "HyperliquidTransaction:UsdSend",
     [{"destination", "string"}, {"amount", "string"}, {"time", "uint64"}],
     [{"destination", @dest}, {"amount", "1"}, {"time", @nonce}],
     {"0x9adbd066e8ae671f06b5d18e51fd2ec11b5443d64b13718028c7ff06905c71fb",
      "0x1eba4172075f8a8037481400ae86ed56c5e5f672e3db084528a8e3b2daeff976", 28},
     {"0xff67e331a1466b4afaf343f251e3bc9cdef48cc88c6ff60c41559905f9b8896a",
      "0x032928340520808eedb79faa05a67664e8f8393e9c54e5a7277d13212a209f07", 28}},
    {"spotSend", "HyperliquidTransaction:SpotSend",
     [
       {"destination", "string"},
       {"token", "string"},
       {"amount", "string"},
       {"time", "uint64"}
     ], [{"destination", @dest}, {"token", @token}, {"amount", "1"}, {"time", @nonce}],
     {"0x60fdd21a858c4a8b3278d047a7ba85bb8ce933e8a28f9dc89989e2e2bc325f45",
      "0x1823ce35e5b1f0aae05be776f1a3eb243c2dbc77f8f41cc3edf5c72825f04287", 27},
     {"0x4e37108b707e9ff9aecdf1326a66e7f9cdf116fcdc50bcaab168880a79e240cd",
      "0x23452d87d6f901574bbe9c76eb16f85e533082df4f4522541f7582c6b48c0e13", 27}},
    {"withdraw3", "HyperliquidTransaction:Withdraw",
     [{"destination", "string"}, {"amount", "string"}, {"time", "uint64"}],
     [{"destination", @dest}, {"amount", "1"}, {"time", @nonce}],
     {"0xa155eccb6deecc343d5ce1d69ca20a6b8959cc3f21ffff6b82790e2e9f7fe888",
      "0x6e78708de0806beceab552e1a97378fa80090d902bfffa8b6ee6b35d713f58c4", 28},
     {"0x4929562d7f5ba20a15d883c6b7fbbabbdf423ce529595a59e913e2b4092105ff",
      "0x0d8988041184c87a11ddfdaa7dfd810b099f8ef2d0e82beaa0cb136c3e5e99ab", 27}},
    {"usdClassTransfer", "HyperliquidTransaction:UsdClassTransfer",
     [{"amount", "string"}, {"toPerp", "bool"}, {"nonce", "uint64"}],
     [{"amount", "100"}, {"toPerp", true}, {"nonce", @nonce}],
     {"0xeeb88f23eace172797fc664ff89e1acbde05651d6e43c45432b90a05544e6c28",
      "0x0dd83b4737c7ea3b5cddd20b6f3cec84dafaeae1546c20460e397fea44233170", 27},
     {"0xcac32ff4b39b5ba68b3f593690a062e6281f8d31f67d2f032418d58ded998e25",
      "0x67c218d47c94a58705e11f65c6c55bb63a8b7e3d84e049661694c44cd3de85a6", 28}},
    {"tokenDelegate", "HyperliquidTransaction:TokenDelegate",
     [
       {"validator", "address"},
       {"wei", "uint64"},
       {"isUndelegate", "bool"},
       {"nonce", "uint64"}
     ],
     [
       {"validator", @validator},
       {"wei", 100_000_000},
       {"isUndelegate", false},
       {"nonce", @nonce}
     ],
     {"0x5f9051975bf851d2d8ce8149d770b1aa173334acb0ede45691fcaee013d4bd0c",
      "0x06234355a583df3e18ba107e32f5c0de7eee0e9f04c97542d99877838f479b0b", 27},
     {"0x4c10e4d26a3f71874165ce627e5cb6a541be706d2927c22d14eea619fe0b75f8",
      "0x463b32f6fdc2a9e22a44edb62204e55263b5c40e570143f8de4663e5f7248595", 27}},
    {"approveAgent", "HyperliquidTransaction:ApproveAgent",
     [{"agentAddress", "address"}, {"agentName", "string"}, {"nonce", "uint64"}],
     [{"agentAddress", @validator}, {"agentName", "agent"}, {"nonce", @nonce}],
     {"0xa73999aeae0c688601e37a7b62b92be104d806d560794230df1a5b274b6a5de0",
      "0x121570fc3b914104f6c93c9f0abed3735db285a7579eab24310377f4e5d06184", 28},
     {"0x80faa7bc459ac17d0add234184435784e301cd4c795361d94f905ebbed36e7c7",
      "0x2ee65ec5957781a0521fe6cbdce32ff1eafbb5b6fe55bd7ddcd3d3c668e0194f", 28}},
    {"approveBuilderFee", "HyperliquidTransaction:ApproveBuilderFee",
     [{"maxFeeRate", "string"}, {"builder", "address"}, {"nonce", "uint64"}],
     [{"maxFeeRate", "0.001%"}, {"builder", @validator}, {"nonce", @nonce}],
     {"0xb2b1df833cb6a99f4c2416ee3d8f2be484f3104b949256f6f478a63c2c2eadc8",
      "0x1a9a2925db804f1a8d4dd6abdd4d198ffbf544e6b7c38a9307af47ebc8b8d623", 28},
     {"0xc833e4e98281ea8e1c743455434278182d4b75edb4d3ed2d08e5174083c92c04",
      "0x3cacd0c5de0b738cc440a1a691842ba6bd013cf947ca933430d6ed67e426bdb6", 27}},
    {"userPortfolioMargin", "HyperliquidTransaction:UserPortfolioMargin",
     [{"user", "address"}, {"enabled", "bool"}, {"nonce", "uint64"}],
     [{"user", @user}, {"enabled", true}, {"nonce", @nonce}],
     {"0xcecca6b5a263e2e874c7923bfddd852c0182fd901f49bbb60e7763eed9b3ab27",
      "0x6de12a217b0cf4dba1a9ae9333fbb4a106560a42053d21426c0766a1ab9f3c94", 28},
     {"0x1dc4be4e067460a189a37093b55b3e5fb73f13c4c8762099af7028ed2793dfc4",
      "0x5617005ec24ef9cab46729152cd14e5eb6e2fca25b310927f9e52d0f1568fa93", 28}},
    {"userDexAbstraction", "HyperliquidTransaction:UserDexAbstraction",
     [{"user", "address"}, {"enabled", "bool"}, {"nonce", "uint64"}],
     [{"user", @user}, {"enabled", true}, {"nonce", @nonce}],
     {"0x359abd5ec11d5e630cfea1c208b6857e497d8cd0a1b17961afdc25f2ae796943",
      "0x34ff77b37a3e3a2e1a5dc292cbc31ac78d31cda06e4769ee4328f8cbbdcd23b3", 27},
     {"0xaf03978ca46edae8b83eced042efc6600ced4c88ddbaf0eeba61a37892c43047",
      "0x66321e7294514f4808db051fb5095fd4ed96460d373cfd6fd7be27bac61582ba", 28}},
    {"linkStakingUser", "HyperliquidTransaction:LinkStakingUser",
     [{"user", "address"}, {"isFinalize", "bool"}, {"nonce", "uint64"}],
     [{"user", @user}, {"isFinalize", false}, {"nonce", @nonce}],
     {"0xa679a4a7c4aa6b1ebce4a8546573853f98ca21bab83889978f5c22c9a12aa05b",
      "0x20709c2af5a2e67e4a5021beab7cd534ef1be2324ca0bfd210b93dcf96cf7bbe", 28},
     {"0x40709830ac98dc7871fda5d880bf6d9664cea21102bf3cc83dec44412a63c472",
      "0x58f7f6ec69aac7e28b68b5b276cfac3f932c41cecb3704dcabf8b8ab2d47f3d4", 27}},
    {"convertToMultiSigUser", "HyperliquidTransaction:ConvertToMultiSigUser",
     [{"signers", "string"}, {"nonce", "uint64"}], [{"signers", @signers}, {"nonce", @nonce}],
     {"0xae97304fac9c30bc60b99b928af5efde9054e1e25f1a0e2a6fb5d82ee398c219",
      "0x1361b0d048a8240206dd0fb04f60971370b98071a0dfbbd1f091e3723fa950fb", 27},
     {"0x33a4f19a61d1f8f75ce7d59c0dfa6ba327fe54e75ad8261cd1a96d3f0dd70e0d",
      "0x34e6b896b91facd916fedccd879e579155aba4daf35113a64ff62d982f360756", 28}},
    {"cDeposit", "HyperliquidTransaction:CDeposit", [{"wei", "uint64"}, {"nonce", "uint64"}],
     [{"wei", @wei}, {"nonce", @nonce}],
     {"0x73c3afb27a2f3ab12942daa8633cbf5fa18dc2beece904d52492bd9ab15fe458",
      "0x3a42195a3b648a41fa6cc1fb211cafc62821e83a58b7b3cc51ade1e12196a26e", 27},
     {"0xc02c7ffefab875f90079a211b6f790b8d31c491852545bb2d8bc3f77c53fe9f2",
      "0x34111ce99d31668a4598aa4067734287c82c06f9cb9782937907568f959304ae", 28}},
    {"cWithdraw", "HyperliquidTransaction:CWithdraw", [{"wei", "uint64"}, {"nonce", "uint64"}],
     [{"wei", @wei}, {"nonce", @nonce}],
     {"0x583548c154432a16df2124db0308a0cee59275d98be619e5b7f98a4caf00285f",
      "0x07eab5d73cb964e595f686ad0c4a6b7ba445a3ed0957dcd18b71e73f96bb30aa", 28},
     {"0x6d92ab5ea74865d97d98738c5caf8eab2172eb9f3fdeb59884768c6da4c4d5fa",
      "0x56cad469de655971eafa9a7003b7031ed2f544c4bf690052363f700262d79012", 27}},
    {"sendAsset", "HyperliquidTransaction:SendAsset",
     [
       {"destination", "string"},
       {"sourceDex", "string"},
       {"destinationDex", "string"},
       {"token", "string"},
       {"amount", "string"},
       {"fromSubAccount", "string"},
       {"nonce", "uint64"}
     ],
     [
       {"destination", @dest},
       {"sourceDex", ""},
       {"destinationDex", "spot"},
       {"token", @token},
       {"amount", "100"},
       {"fromSubAccount", ""},
       {"nonce", @nonce}
     ],
     {"0xf47b730b8238c65423efa111b3926f202eac3b069635f4f11682643310e7e158",
      "0x28a28e1bfb322eb44f589197faa2ef5f8a074a93b820dd881346236d7752bf58", 27},
     {"0x83dbb1b5cac122fc7f58b83de1062034f768eb9082b2890b857ebb2705214d75",
      "0x0edf2b5fcb18d31b4af9a6957f981a098f184913825b7e4123240f8ff8646f4e", 27}},
    {"stakingLinkDisableTradingUser", "HyperliquidTransaction:StakingLinkDisableTradingUser",
     [{"tradingUser", "address"}, {"nonce", "uint64"}],
     [{"tradingUser", @user}, {"nonce", @nonce}],
     {"0x7f6ed71d9f05a2130a2520ebf8fd83f68ff81c21ec7af717e93ad4387e5a358f",
      "0x22a0270d678cb77cef41a3bacf73676acb330bef4488a395dce63df470c5e20c", 27},
     {"0x3e6aebba81cb758d02148cc1839c593f7c9cfe913b1c421c60d1993c1b452d26",
      "0x1922325a5872c3815fbc217f092296d5862c13d2476daa6080e923f91b228d93", 28}},
    {"userSetAbstraction", "HyperliquidTransaction:UserSetAbstraction",
     [{"user", "address"}, {"abstraction", "string"}, {"nonce", "uint64"}],
     [{"user", @user}, {"abstraction", "unifiedAccount"}, {"nonce", @nonce}],
     {"0xa6a943968fb2acd8ca7a447e36299d858696174b0e0dbd7cc7fba6bb0f214880",
      "0x5d5195868fd4ea945f14c4a0b55025e05dea2a6d7e1a02addea5a55e0047c5dc", 27},
     {"0x87229a076a931999eae368bb3e8ae8ba0f272f794c55c006934841d6b5723af8",
      "0x788a178107f344312fc29ead4ab17adc628e50f1bbe0ef0fd3d6525be24e04f6", 28}},
    {"sendToEvmWithData", "HyperliquidTransaction:SendToEvmWithData",
     [
       {"token", "string"},
       {"amount", "string"},
       {"sourceDex", "string"},
       {"destinationRecipient", "string"},
       {"addressEncoding", "string"},
       {"destinationChainId", "uint32"},
       {"gasLimit", "uint64"},
       {"data", "bytes"},
       {"nonce", "uint64"}
     ],
     [
       {"token", @token},
       {"amount", "100"},
       {"sourceDex", ""},
       {"destinationRecipient", @user},
       {"addressEncoding", "hex"},
       {"destinationChainId", 999},
       {"gasLimit", 200_000},
       {"data", @data},
       {"nonce", @nonce}
     ],
     {"0xd1fb9a254d774105c911432f80a3ec99547bad1c967c3b90ab728edafe48652b",
      "0x0431d5917055464918dbff7ab4999a6996d40ce15a25641dd892bd9c4323c35a", 28},
     {"0xe39cc869ed7d17b2afb41f35efe3e2463ca512cfe29f8064565b707560d6ced5",
      "0x244849f8326f1fe8d87719d77629ac8110efbbc1060ee8a75ea3353789283ec5", 27}}
  ]

  # {label, module, sign/N args after the private key, sig_at_421614, sig_at_42161}
  @module_vectors [
    {"userPortfolioMargin", UserPortfolioMargin, [@user, true, @nonce, true],
     %{
       r: "0xcecca6b5a263e2e874c7923bfddd852c0182fd901f49bbb60e7763eed9b3ab27",
       s: "0x6de12a217b0cf4dba1a9ae9333fbb4a106560a42053d21426c0766a1ab9f3c94",
       v: 28
     },
     %{
       r: "0x1dc4be4e067460a189a37093b55b3e5fb73f13c4c8762099af7028ed2793dfc4",
       s: "0x5617005ec24ef9cab46729152cd14e5eb6e2fca25b310927f9e52d0f1568fa93",
       v: 28
     }},
    {"userDexAbstraction", UserDexAbstraction, [@user, true, @nonce, true],
     %{
       r: "0x359abd5ec11d5e630cfea1c208b6857e497d8cd0a1b17961afdc25f2ae796943",
       s: "0x34ff77b37a3e3a2e1a5dc292cbc31ac78d31cda06e4769ee4328f8cbbdcd23b3",
       v: 27
     },
     %{
       r: "0xaf03978ca46edae8b83eced042efc6600ced4c88ddbaf0eeba61a37892c43047",
       s: "0x66321e7294514f4808db051fb5095fd4ed96460d373cfd6fd7be27bac61582ba",
       v: 28
     }},
    {"linkStakingUser", LinkStakingUser, [@user, false, @nonce, true],
     %{
       r: "0xa679a4a7c4aa6b1ebce4a8546573853f98ca21bab83889978f5c22c9a12aa05b",
       s: "0x20709c2af5a2e67e4a5021beab7cd534ef1be2324ca0bfd210b93dcf96cf7bbe",
       v: 28
     },
     %{
       r: "0x40709830ac98dc7871fda5d880bf6d9664cea21102bf3cc83dec44412a63c472",
       s: "0x58f7f6ec69aac7e28b68b5b276cfac3f932c41cecb3704dcabf8b8ab2d47f3d4",
       v: 27
     }},
    {"convertToMultiSigUser", ConvertToMultiSigUser, [@signers, @nonce, true],
     %{
       r: "0xae97304fac9c30bc60b99b928af5efde9054e1e25f1a0e2a6fb5d82ee398c219",
       s: "0x1361b0d048a8240206dd0fb04f60971370b98071a0dfbbd1f091e3723fa950fb",
       v: 27
     },
     %{
       r: "0x33a4f19a61d1f8f75ce7d59c0dfa6ba327fe54e75ad8261cd1a96d3f0dd70e0d",
       s: "0x34e6b896b91facd916fedccd879e579155aba4daf35113a64ff62d982f360756",
       v: 28
     }}
  ]

  describe "UserSigned.sign/5 against the Python SDK" do
    for {name, primary_type, fields, message, sig_421614, sig_42161} <- @vectors do
      for {chain_id, {r, s, v}} <- [{421_614, sig_421614}, {42_161, sig_42161}] do
        test "#{name} at chainId #{chain_id}" do
          with_chain_id(unquote(chain_id), fn ->
            assert {:ok, sig} =
                     UserSigned.sign(
                       @priv_key,
                       unquote(primary_type),
                       unquote(Macro.escape(fields)),
                       unquote(Macro.escape(message)),
                       true
                     )

            assert sig == %{r: unquote(r), s: unquote(s), v: unquote(v)}
          end)
        end
      end
    end
  end

  describe "actions converted from L1 to user-signed" do
    # Regression: userPortfolioMargin, userDexAbstraction, linkStakingUser and
    # convertToMultiSigUser used to build L1 msgpack actions — with the wrong
    # fields, too (`on`, no `user`, `linkTo`, inlined `authorizedUsers`).
    # nktkas signs all four as `HyperliquidTransaction:*` user-signed actions;
    # the Python SDK agrees for the two it implements.
    for {label, module, args, sig_421614, sig_42161} <- @module_vectors do
      for {chain_id, expected} <- [{421_614, sig_421614}, {42_161, sig_42161}] do
        test "#{label} module sign path matches the Python SDK at chainId #{chain_id}" do
          with_chain_id(unquote(chain_id), fn ->
            assert {:ok, sig} =
                     apply(unquote(module), :sign, [@priv_key | unquote(Macro.escape(args))])

            assert sig == unquote(Macro.escape(expected))
          end)
        end
      end
    end

    test "wire actions carry the user-signed envelope in canonical field order" do
      with_chain_id(421_614, fn ->
        for {action, keys} <- [
              {UserPortfolioMargin.build_action(@user, true, @nonce, true),
               [:type, :signatureChainId, :hyperliquidChain, :user, :enabled, :nonce]},
              {UserDexAbstraction.build_action(@user, true, @nonce, true),
               [:type, :signatureChainId, :hyperliquidChain, :user, :enabled, :nonce]},
              {LinkStakingUser.build_action(@user, false, @nonce, true),
               [:type, :signatureChainId, :hyperliquidChain, :user, :isFinalize, :nonce]},
              {ConvertToMultiSigUser.build_action(@signers, @nonce, true),
               [:type, :signatureChainId, :hyperliquidChain, :signers, :nonce]}
            ] do
          assert Enum.map(action.values, fn {k, _} -> k end) == keys
          assert action[:signatureChainId] == "0x66eee"
          assert action[:hyperliquidChain] == "Mainnet"
        end
      end)
    end

    test "convertToMultiSigUser renders signers as a compact, sorted JSON string" do
      assert ConvertToMultiSigUser.encode_signers(nil) == "null"
      assert ConvertToMultiSigUser.encode_signers(@signers) == @signers

      assert ConvertToMultiSigUser.encode_signers(%{
               authorized_users: [String.upcase("0X" <> String.slice(@user, 2..-1//1))],
               threshold: 1
             }) == @signers

      assert ConvertToMultiSigUser.encode_signers(%{
               "authorizedUsers" => [@dest, @user],
               "threshold" => 2
             }) == ~s({"authorizedUsers":["#{@user}","#{@dest}"],"threshold":2})
    end
  end

  # {label, module, sign/N args after the private key, sig_at_421614, sig_at_42161}
  # These modules used to build their own EIP-712 domain/types/message inline;
  # three of them disagreed with nktkas on the struct itself (see the module
  # docs). They now route through `UserSigned` like everything else.
  @converted_inline_vectors [
    {"tokenDelegate", TokenDelegate, [@validator, false, @wei, @nonce, true],
     %{
       r: "0x5f9051975bf851d2d8ce8149d770b1aa173334acb0ede45691fcaee013d4bd0c",
       s: "0x06234355a583df3e18ba107e32f5c0de7eee0e9f04c97542d99877838f479b0b",
       v: 27
     },
     %{
       r: "0x4c10e4d26a3f71874165ce627e5cb6a541be706d2927c22d14eea619fe0b75f8",
       s: "0x463b32f6fdc2a9e22a44edb62204e55263b5c40e570143f8de4663e5f7248595",
       v: 27
     }},
    {"userSetAbstraction", UserSetAbstraction, [@user, "unifiedAccount", @nonce, true],
     %{
       r: "0xa6a943968fb2acd8ca7a447e36299d858696174b0e0dbd7cc7fba6bb0f214880",
       s: "0x5d5195868fd4ea945f14c4a0b55025e05dea2a6d7e1a02addea5a55e0047c5dc",
       v: 27
     },
     %{
       r: "0x87229a076a931999eae368bb3e8ae8ba0f272f794c55c006934841d6b5723af8",
       s: "0x788a178107f344312fc29ead4ab17adc628e50f1bbe0ef0fd3d6525be24e04f6",
       v: 28
     }},
    {"sendToEvmWithData", SendToEvmWithData,
     [@token, "100", "", @user, "hex", 999, 200_000, @data, @nonce, true],
     %{
       r: "0xd1fb9a254d774105c911432f80a3ec99547bad1c967c3b90ab728edafe48652b",
       s: "0x0431d5917055464918dbff7ab4999a6996d40ce15a25641dd892bd9c4323c35a",
       v: 28
     },
     %{
       r: "0xe39cc869ed7d17b2afb41f35efe3e2463ca512cfe29f8064565b707560d6ced5",
       s: "0x244849f8326f1fe8d87719d77629ac8110efbbc1060ee8a75ea3353789283ec5",
       v: 27
     }},
    {"cDeposit", CDeposit, [@wei, @nonce, true],
     %{
       r: "0x73c3afb27a2f3ab12942daa8633cbf5fa18dc2beece904d52492bd9ab15fe458",
       s: "0x3a42195a3b648a41fa6cc1fb211cafc62821e83a58b7b3cc51ade1e12196a26e",
       v: 27
     },
     %{
       r: "0xc02c7ffefab875f90079a211b6f790b8d31c491852545bb2d8bc3f77c53fe9f2",
       s: "0x34111ce99d31668a4598aa4067734287c82c06f9cb9782937907568f959304ae",
       v: 28
     }},
    {"cWithdraw", CWithdraw, [@wei, @nonce, true],
     %{
       r: "0x583548c154432a16df2124db0308a0cee59275d98be619e5b7f98a4caf00285f",
       s: "0x07eab5d73cb964e595f686ad0c4a6b7ba445a3ed0957dcd18b71e73f96bb30aa",
       v: 28
     },
     %{
       r: "0x6d92ab5ea74865d97d98738c5caf8eab2172eb9f3fdeb59884768c6da4c4d5fa",
       s: "0x56cad469de655971eafa9a7003b7031ed2f544c4bf690052363f700262d79012",
       v: 27
     }},
    {"sendAsset", SendAsset, [@dest, "", "spot", @token, "100", "", @nonce, true],
     %{
       r: "0xf47b730b8238c65423efa111b3926f202eac3b069635f4f11682643310e7e158",
       s: "0x28a28e1bfb322eb44f589197faa2ef5f8a074a93b820dd881346236d7752bf58",
       v: 27
     },
     %{
       r: "0x83dbb1b5cac122fc7f58b83de1062034f768eb9082b2890b857ebb2705214d75",
       s: "0x0edf2b5fcb18d31b4af9a6957f981a098f184913825b7e4123240f8ff8646f4e",
       v: 27
     }},
    {"stakingLinkDisableTradingUser", StakingLinkDisableTradingUser, [@user, @nonce, true],
     %{
       r: "0x7f6ed71d9f05a2130a2520ebf8fd83f68ff81c21ec7af717e93ad4387e5a358f",
       s: "0x22a0270d678cb77cef41a3bacf73676acb330bef4488a395dce63df470c5e20c",
       v: 27
     },
     %{
       r: "0x3e6aebba81cb758d02148cc1839c593f7c9cfe913b1c421c60d1993c1b452d26",
       s: "0x1922325a5872c3815fbc217f092296d5862c13d2476daa6080e923f91b228d93",
       v: 28
     }}
  ]

  describe "inline typed data routed through UserSigned" do
    # Regression: tokenDelegate declared `validator` as `string` and put
    # `isUndelegate` before `wei`; userSetAbstraction omitted `user` entirely;
    # sendToEvmWithData declared `destinationChainId` as uint64 and `data` as
    # string. All three fed the wrong EIP-712 type hash and struct encoding, so
    # their signatures could never have recovered to the sending address.
    # cDeposit, cWithdraw, sendAsset and stakingLinkDisableTradingUser had the
    # right struct but built it by hand; they are pinned here too.
    for {label, module, args, sig_421614, sig_42161} <- @converted_inline_vectors do
      for {chain_id, expected} <- [{421_614, sig_421614}, {42_161, sig_42161}] do
        test "#{label} module sign path matches the reference SDKs at chainId #{chain_id}" do
          with_chain_id(unquote(chain_id), fn ->
            assert {:ok, sig} =
                     apply(unquote(module), :sign, [@priv_key | unquote(Macro.escape(args))])

            assert sig == unquote(Macro.escape(expected))
          end)
        end
      end
    end

    test "wire actions carry the user-signed envelope in nktkas field order" do
      with_chain_id(421_614, fn ->
        for {action, keys} <- [
              {TokenDelegate.build_action(@validator, false, @wei, @nonce, true),
               [
                 :type,
                 :signatureChainId,
                 :hyperliquidChain,
                 :validator,
                 :wei,
                 :isUndelegate,
                 :nonce
               ]},
              {UserSetAbstraction.build_action(@user, "unifiedAccount", @nonce, true),
               [:type, :signatureChainId, :hyperliquidChain, :user, :abstraction, :nonce]},
              {CDeposit.build_action(@wei, @nonce, true),
               [:type, :signatureChainId, :hyperliquidChain, :wei, :nonce]},
              {CWithdraw.build_action(@wei, @nonce, true),
               [:type, :signatureChainId, :hyperliquidChain, :wei, :nonce]},
              {SendAsset.build_action(@dest, "", "spot", @token, "100", "", @nonce, true),
               [
                 :type,
                 :signatureChainId,
                 :hyperliquidChain,
                 :destination,
                 :sourceDex,
                 :destinationDex,
                 :token,
                 :amount,
                 :fromSubAccount,
                 :nonce
               ]},
              {SendToEvmWithData.build_action(
                 @token,
                 "100",
                 "",
                 @user,
                 "hex",
                 999,
                 200_000,
                 @data,
                 @nonce,
                 true
               ),
               [
                 :type,
                 :signatureChainId,
                 :hyperliquidChain,
                 :token,
                 :amount,
                 :sourceDex,
                 :destinationRecipient,
                 :addressEncoding,
                 :destinationChainId,
                 :gasLimit,
                 :data,
                 :nonce
               ]},
              {StakingLinkDisableTradingUser.build_action(@user, @nonce, true),
               [:type, :signatureChainId, :hyperliquidChain, :tradingUser, :nonce]}
            ] do
          assert Enum.map(action.values, fn {k, _} -> k end) == keys
          assert action[:signatureChainId] == "0x66eee"
          assert action[:hyperliquidChain] == "Mainnet"
        end
      end)
    end
  end

  describe "signatureChainId configuration" do
    test "defaults to 0x66eee (421614), matching nktkas and the Python SDK" do
      Application.delete_env(:hyperliquid, :signature_chain_id)
      assert Config.signature_chain_id() == 421_614
      assert Config.signature_chain_id_hex() == "0x66eee"
      assert UserSigned.domain().chainId == 421_614
      assert UserSigned.signature_chain_id() == "0x66eee"
    end

    test "accepts a hex string" do
      with_chain_id("0xa4b1", fn ->
        assert Config.signature_chain_id() == 42_161
        assert Config.signature_chain_id_hex() == "0xa4b1"
      end)
    end

    test "rejects nonsense" do
      with_chain_id(:arbitrum, fn ->
        assert_raise ArgumentError, fn -> Config.signature_chain_id() end
      end)
    end
  end

  describe "usdClassTransfer is a user-signed action" do
    # Regression: this module used to build `{type, amount, toPerp}` and hash it
    # as an L1 msgpack action. Both nktkas and the Python SDK sign it as
    # `HyperliquidTransaction:UsdClassTransfer`, so the old signatures could
    # never recover to the sending address.
    test "the module's own sign path matches the Python SDK at both chain ids" do
      for {chain_id, expected} <- [
            {421_614,
             %{
               r: "0xeeb88f23eace172797fc664ff89e1acbde05651d6e43c45432b90a05544e6c28",
               s: "0x0dd83b4737c7ea3b5cddd20b6f3cec84dafaeae1546c20460e397fea44233170",
               v: 27
             }},
            {42_161,
             %{
               r: "0xcac32ff4b39b5ba68b3f593690a062e6281f8d31f67d2f032418d58ded998e25",
               s: "0x67c218d47c94a58705e11f65c6c55bb63a8b7e3d84e049661694c44cd3de85a6",
               v: 28
             }}
          ] do
        with_chain_id(chain_id, fn ->
          assert {:ok, sig} = UsdClassTransfer.sign(@priv_key, "100", true, @nonce, true)
          assert sig == expected
        end)
      end
    end

    test "the wire action carries the user-signed envelope in nktkas field order" do
      with_chain_id(421_614, fn ->
        action = UsdClassTransfer.build_action("100", true, @nonce, true)

        assert Enum.map(action.values, fn {k, _} -> k end) ==
                 [:type, :signatureChainId, :hyperliquidChain, :amount, :toPerp, :nonce]

        assert Jason.encode!(action) ==
                 ~s({"type":"usdClassTransfer","signatureChainId":"0x66eee",) <>
                   ~s("hyperliquidChain":"Mainnet","amount":"100","toPerp":true,) <>
                   ~s("nonce":#{@nonce}})
      end)
    end

    test "hyperliquidChain follows the network" do
      assert UserSigned.hyperliquid_chain(true) == "Mainnet"
      assert UserSigned.hyperliquid_chain(false) == "Testnet"

      action = UsdClassTransfer.build_action("100", false, @nonce, false)
      assert action[:hyperliquidChain] == "Testnet"
    end
  end
end
