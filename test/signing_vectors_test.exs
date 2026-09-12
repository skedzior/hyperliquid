defmodule Hyperliquid.SigningVectorsTest do
  @moduledoc """
  Cross-SDK signing vectors.

  Every vector in this file was produced by the **official Python SDK**
  (`hyperliquid-python-sdk`, `hyperliquid/utils/signing.py`) — an independent
  implementation with its own msgpack encoder, keccak and `eth_account`
  secp256k1 signer. Nothing here is a snapshot of this library's own output, so
  a key-order regression (H3) or a signing-path regression (H2) turns these red
  instead of silently producing rejected orders.

  Regenerate with `scripts/gen_signing_vectors.py` (see the module doc there).

  The generator's environment must use `msgpack >= 1.0` (`use_bin_type=True`),
  which encodes 32..255-byte strings as `str8` (`0xd9`) — the same encoding
  Rust's `rmp_serde` and `@std/msgpack` produce. A pre-1.0 `msgpack` emits
  `raw16` (`0xda`) and silently yields different, wrong hashes.

  """

  use ExUnit.Case, async: true

  alias Hyperliquid.Api.Exchange.Action
  alias Hyperliquid.Signer

  @priv_key "0x0123456789012345678901234567890123456789012345678901234567890123"

  # {name, action_json, nonce, vault, expires_after, has_declared_key_order?,
  #  action_hash, mainnet_sig, testnet_sig}
  @l1_vectors [
    {"order_limit_gtc",
     "{\"type\":\"order\",\"orders\":[{\"a\":1,\"b\":true,\"p\":\"100\",\"s\":\"100\",\"r\":false,\"t\":{\"limit\":{\"tif\":\"Gtc\"}}}],\"grouping\":\"na\"}",
     0, nil, nil, true, "0x884f2c32bb6dbdd65f6033e32fb28c0cb6f5b345db0f6471fd3366d85c9252c1",
     {"0xd65369825a9df5d80099e513cce430311d7d26ddf477f5b3a33d2806b100d78e",
      "0x2b54116ff64054968aa237c20ca9ff68000f977c93289157748a3162b6ea940e", 28},
     {"0x82b2ba28e76b3d761093aaded1b1cdad4960b3af30212b343fb2e6cdfa4e3d54",
      "0x6b53878fc99d26047f4d7e8c90eb98955a109f44209163f52d8dc4278cbbd9f5", 27}},
    {"order_with_cloid",
     "{\"type\":\"order\",\"orders\":[{\"a\":1,\"b\":true,\"p\":\"100\",\"s\":\"100\",\"r\":false,\"t\":{\"limit\":{\"tif\":\"Gtc\"}},\"c\":\"0x00000000000000000000000000000001\"}],\"grouping\":\"na\"}",
     0, nil, nil, true, "0x0ba500cedd8f4ba6ded620a0b1cd04f124d9ba745e2e2893fcc763bcc1444af5",
     {"0x041ae18e8239a56cacbc5dad94d45d0b747e5da11ad564077fcac71277a946e3",
      "0x3c61f667e747404fe7eea8f90ab0e76cc12ce60270438b2058324681a00116da", 27},
     {"0xeba0664bed2676fc4e5a743bf89e5c7501aa6d870bdb9446e122c9466c5cd16d",
      "0x7f3e74825c9114bc59086f1eebea2928c190fdfbfde144827cb02b85bbe90988", 28}},
    {"order_trigger_tpsl",
     "{\"type\":\"order\",\"orders\":[{\"a\":1,\"b\":true,\"p\":\"100\",\"s\":\"100\",\"r\":false,\"t\":{\"trigger\":{\"isMarket\":true,\"triggerPx\":\"103\",\"tpsl\":\"sl\"}}}],\"grouping\":\"na\"}",
     0, nil, nil, true, "0x430a86fb9876e901920d931f5bb20c9d011f6389bd179f39a73c09e6219adcad",
     {"0x98343f2b5ae8e26bb2587daad3863bc70d8792b09af1841b6fdd530a2065a3f9",
      "0x6b5bb6bb0633b710aa22b721dd9dee6d083646a5f8e581a20b545be6c1feb405", 27},
     {"0x971c554d917c44e0e1b6cc45d8f9404f32172a9d3b3566262347d0302896a2e4",
      "0x206257b104788f80450f8e786c329daa589aa0b32ba96948201ae556d5637eac", 28}},
    {"order_grouping_priority",
     "{\"type\":\"order\",\"orders\":[{\"a\":1,\"b\":true,\"p\":\"100\",\"s\":\"100\",\"r\":false,\"t\":{\"limit\":{\"tif\":\"Gtc\"}}}],\"grouping\":{\"p\":50000000}}",
     1_234_567_890, nil, nil, true,
     "0xc5a5ac58817f8e872e6a60231a68a45c898fb5ee8283c57ac4109e81eeba7531",
     {"0x82ce7a02c7ca949c0f8068a2501a3b79856e5f148392cfb3d67789fb4e39e6e3",
      "0x2f0ee6ff24cdc5b851606edbb91525339b57e9579a462287ae8b308eb55762a0", 27},
     {"0x4040b3a736b115a91ff3bcc5b673ce43340b0b3b33479d153edede8bd1cd1448",
      "0x3d55ab554020b02d894cce195bf15ed39a0bc708184c4231557b1afdd973330b", 28}},
    {"order_with_builder",
     "{\"type\":\"order\",\"orders\":[{\"a\":1,\"b\":true,\"p\":\"100\",\"s\":\"100\",\"r\":false,\"t\":{\"limit\":{\"tif\":\"Gtc\"}}}],\"grouping\":\"na\",\"builder\":{\"b\":\"0x1d9470d4b963f552e6f671a81619d395877bf409\",\"f\":10}}",
     1_234_567_890, nil, nil, true,
     "0x7c5dd013fb13431b41109e034211899b6fb440fbb08e55710f5cb4458e5d4d0e",
     {"0xa59597f42d8b90907c397e363eef81827f94a0eef607b595c308dbfd661912bd",
      "0x5cbd9a57e8873b08e36e0aabb587ecf9c2a09a220252797158257d5957091873", 27},
     {"0x2066a1d78d3662fb5d93d367576291b620f4e5dd564e8b351a0a015d2463f4ba",
      "0x0d807a2be730a00c92a65d1d186bc23ff7bedcf1c4eef2c76b25772955f8a084", 27}},
    {"order_with_vault_and_expires",
     "{\"type\":\"order\",\"orders\":[{\"a\":1,\"b\":true,\"p\":\"100\",\"s\":\"100\",\"r\":false,\"t\":{\"limit\":{\"tif\":\"Gtc\"}}}],\"grouping\":\"na\"}",
     1_234_567_890, "0x1719884eb866cb12b2287399b15f7db5e7d775ea", 1_234_567_890, true,
     "0x8a9dcb02b410e8b7d013eff256edd9e7e9cd1c6e56334c176bb954a335ec2e92",
     {"0x9792876c170de41e6c197135c97cae8638fe168bdfc19c5655f8945cc19d530c",
      "0x7c0a3468c1e87b241c51a5ae57a38a103bbad83108416bc3d3470f815da8f2d3", 27},
     {"0x38583cb56092edfa64b9d335bb215248ffec05f49d88ceeb550d15d94ea606b7",
      "0x366f8af1e9ee911a8556bef5d62e61d17eb478636490758c150d033c2f2dabd2", 28}},
    {"cancel", "{\"type\":\"cancel\",\"cancels\":[{\"a\":1,\"o\":12345}]}", 1_234_567_890, nil,
     nil, true, "0xaed0b18de72ff34fd5e84dbab74a01fa129885e9a260c3ba1cfd573aad244740",
     {"0x90eda33e2c4155ff685b2bf03211e8877dd2c08575e3bfe90f83de3a29258058",
      "0x29612dca902c1bbcd2f34f8b9694c689737ba1d4cd8c371539c13770233db6b0", 27},
     {"0x4980fcd11c5959b3865437be84966bef1ccc1f20faa6adfe30edb67b2ae043de",
      "0x395b5e4ee9f284227d37f8614489384d1781b48207700ee5575dd4778b498fd0", 27}},
    {"cancel_by_cloid",
     "{\"type\":\"cancelByCloid\",\"cancels\":[{\"asset\":1,\"cloid\":\"0x00000000000000000000000000000001\"}]}",
     1_234_567_890, nil, nil, true,
     "0x2c1e6813e12af52b1717b16b8e64a2d8e8973ece71376103bbcf5822f18a7b73",
     {"0xd275d64864e3e9e7428ec3a8a34add62bcff448808906afd7a8a8dec06be0d52",
      "0x41681c2cb985468dbce40f9d030e90ecf42e01a76647fbb5e2618244a28848a6", 27},
     {"0x23e0f3f90f382b12bc3256deca6b68c63c818f01857188e2a11d91f5b5024159",
      "0x33759dfc3be1ad8d189b215e18e3c274d11d2670da6e048297212a5539db1cc1", 27}},
    {"modify",
     "{\"type\":\"modify\",\"oid\":12345,\"order\":{\"a\":1,\"b\":true,\"p\":\"100\",\"s\":\"100\",\"r\":false,\"t\":{\"limit\":{\"tif\":\"Gtc\"}}}}",
     1_234_567_890, nil, nil, true,
     "0x9abb67924def256764751c4e072dca707e88b149ed5cf1e21e2e24219f2d1a5b",
     {"0xdc3f46744e5bc0eeac324752ba9ab2e9fc932e4e9b24351d5dc5c67b4749708b",
      "0x4d99cf9f90e0c0ad20501a92124d0c41b5f05e1a800d540fa3bf521bf9c9bb30", 27},
     {"0xd414800d2184e3be7bd2210c0ad354928be675114d06373ba1bfd17a0d1378b8",
      "0x0124d67e4616d9d904df67ed448943f76692ee7120fdf034bfab845adb8703c0", 27}},
    {"batch_modify",
     "{\"type\":\"batchModify\",\"modifies\":[{\"oid\":12345,\"order\":{\"a\":1,\"b\":true,\"p\":\"100\",\"s\":\"100\",\"r\":false,\"t\":{\"limit\":{\"tif\":\"Gtc\"}}}}]}",
     1_234_567_890, nil, nil, true,
     "0xf62a5d4f9eb8f92ad3d1b1abc68d7a7d663643227e91fff0b4139c5407162d6d",
     {"0x17a31d4b2db68023eb5a8ee435a02c4d5cb144d92a2c1ca7c4e20c07a776c147",
      "0x3c8bb12f37b183cb34b63f5f4a13ab77f379fae656fd5edda22a092c3c5b8672", 27},
     {"0xa99509d9d14cb7bc86b56a83541ecda475fd820cdc14498bdfe5751795770bc8",
      "0x08564844b66c5434772d9b8cb49ea9dea7081b5f8a55a06c434013a48bd1ad5b", 27}},
    {"schedule_cancel_no_time", "{\"type\":\"scheduleCancel\"}", 0, nil, nil, true,
     "0xa2887a3147b6542306b61d311a056fd1753913d63cc904f30cba61712a98f4ae",
     {"0x6cdfb286702f5917e76cd9b3b8bf678fcc49aec194c02a73e6d4f16891195df9",
      "0x6557ac307fa05d25b8d61f21fb8a938e703b3d9bf575f6717ba21ec61261b2a0", 27},
     {"0xc75bb195c3f6a4e06b7d395acc20bbb224f6d23ccff7c6a26d327304e6efaeed",
      "0x342f8ede109a29f2c0723bd5efb9e9100e3bbb493f8fb5164ee3d385908233df", 28}},
    {"schedule_cancel_with_time", "{\"type\":\"scheduleCancel\",\"time\":123456789}", 0, nil, nil,
     true, "0x4be18e445114437c5d1d9dd35a09f5601a3cc34ed4ac94a0281251b9bd8f6832",
     {"0x609cb20c737945d070716dcc696ba030e9976fcf5edad87afa7d877493109d55",
      "0x16c685d63b5c7a04512d73f183b3d7a00da5406ff1f8aad33f8ae2163bab758b", 28},
     {"0x4e4f2dbd4107c69783e251b7e1057d9f2b9d11cee213441ccfa2be63516dc5bc",
      "0x706c656b23428c8ba356d68db207e11139ede1670481a9e01ae2dfcdb0e1a678", 27}},
    {"update_leverage",
     "{\"type\":\"updateLeverage\",\"asset\":1,\"isCross\":true,\"leverage\":10}", 1_234_567_890,
     nil, nil, true, "0x18646dd0163799ee8d243819097d8c6eef20b6f5d4a080f018898bd3421fbcd2",
     {"0x4a7445846e9ee51c559f53316bebcea80d34151de76e3bb8e88b5dc981aa21f6",
      "0x04a6ece42227c9c49d96c0fdf350c7490e9cbddc6258c26d082c74d722f92708", 27},
     {"0x0ba23fc2f4e500218c67905d84c0a90e6cf6a16bde8821900bdbbfc0b0573e9c",
      "0x78cb00a185a1c8f3f2ad439d66afbf995779b2128e03498d404e65df46970cc4", 27}},
    {"update_isolated_margin",
     "{\"type\":\"updateIsolatedMargin\",\"asset\":1,\"isBuy\":true,\"ntli\":1000000}",
     1_234_567_890, nil, nil, true,
     "0x5be15137e3fb09df29a2f9d1b339435b65ec9b48cd263b3aa39d2fed81352219",
     {"0x6aef37f7c472de40035bc3604622f750f49e10f8f4e7281699b34cd21a47fc3b",
      "0x6267aa3609403525308e24f1f82f6d04d6de31244e0af3d325b2b3422148042a", 27},
     {"0x9df005c0798ea07b6d9521c35cb7476f31c85b42e3b0f1f7020258fbe88aed3d",
      "0x02f4bd134b96697e95a147c0c9a51d4b2e02cfd1208b7f94c61ec6dc5ca85e35", 27}},
    {"create_sub_account", "{\"type\":\"createSubAccount\",\"name\":\"example\"}", 0, nil, nil,
     true, "0x9a7b5272baf65d28b0589bd50863a42ac35897553a6beb274e625b6faf7d6bb1",
     {"0x51096fe3239421d16b671e192f574ae24ae14329099b6db28e479b86cdd6caa7",
      "0x0b71f7d293af92d3772572afb8b102d167a7cef7473388286bc01f52a5c5b423", 27},
     {"0xa699e3ed5c2b89628c746d3298b5dc1cca604694c2c855da8bb8250ec8014a5b",
      "0x53f1b8153a301c72ecc655b1c315d64e1dcea3ee58921fd7507e35818fcc1584", 28}},
    {"sub_account_modify",
     "{\"type\":\"subAccountModify\",\"subAccountUser\":\"0x1d9470d4b963f552e6f671a81619d395877bf409\",\"name\":\"renamed\"}",
     1_234_567_890, nil, nil, true,
     "0x78ab657528d354695c5f3d58985dd8fb3dfa4415fe17c285b92af1607b4080b9",
     {"0x1c27af78d9395bdb0495fcd15cb457fa0da7c53fb015474d1a864f50eed38e44",
      "0x64a77b0645e733e22709270a0011667193a8e573b1cf39c82a19d6b001243067", 28},
     {"0x4fcd0102933ed2b6091c32d783d0b50554346c58625f2d9a2d7beca30a309720",
      "0x7dd2c8f5932f3f9d6896fc33948bb8d9b0e5f5003ed809cb55a16a19a70963fe", 27}},
    {"sub_account_transfer",
     "{\"type\":\"subAccountTransfer\",\"subAccountUser\":\"0x1d9470d4b963f552e6f671a81619d395877bf409\",\"isDeposit\":true,\"usd\":10}",
     0, nil, nil, true, "0xd12f71eba9e3e792812bfdf01a6a92f4d4016bb0541e850b41f770891c0cc447",
     {"0x43592d7c6c7d816ece2e206f174be61249d651944932b13343f4d13f306ae602",
      "0x71a926cb5c9a7c01c3359ec4c4c34c16ff8107d610994d4de0e6430e5cc0f4c9", 28},
     {"0xe26574013395ad55ee2f4e0575310f003c5bb3351b5425482e2969fa51543927",
      "0x0efb08999196366871f919fd0e138b3a7f30ee33e678df7cfaf203e25f0a4278", 28}},
    {"sub_account_spot_transfer",
     "{\"type\":\"subAccountSpotTransfer\",\"subAccountUser\":\"0x1d9470d4b963f552e6f671a81619d395877bf409\",\"isDeposit\":true,\"token\":\"USDC:0xeb62eee3685fc4c43992febcd9e75443\",\"amount\":\"50\"}",
     1_234_567_890, nil, nil, true,
     "0x484611f585fde786c89a33f83dc3ffb038d18142dbdc7ba7017fe454283d416a",
     {"0x6afdbd7bea3f3e8e7e69e262090c5119c3b2ab80306dc4c5f310d442196e9b83",
      "0x46fb2de55c9f04346d204fe286b91ac501bef7c6d793278894af1bcc2f210cb1", 27},
     {"0x24d81248f4c2839a5809a140a65b98a920f3b4c8b30e3924b219c129d5d1f85c",
      "0x4b2a9748b8d8095904956a8fccdd755ad926f0b8cab10783b24b4fb97f12eb5e", 27}},
    {"spot_user", "{\"type\":\"spotUser\",\"toggleSpotDusting\":{\"optOut\":false}}",
     1_234_567_890, nil, nil, true,
     "0x5ca96bfea4f329bd66de83da1e8eddf5c483e61370628051fd09eff91eb16284",
     {"0xf12424bb7814c3252dcd6790631926621fbdb7089aa4ac795d7f751037d119c9",
      "0x5c4c279c76f389345dd7b0600842b6ea9d6ea8caefaec08576995d4bc41d8c04", 27},
     {"0xa61d4661003ded5005976109d6be6b3da77aaeec7e192ff60e4238cd522a8fab",
      "0x5984e5acef26433999f9b8e7e368878e83ff135b1d2b7bb69b80ebe346c81769", 28}},
    {"create_vault",
     "{\"type\":\"createVault\",\"name\":\"example vault\",\"description\":\"a test vault for vectors\",\"initialUsd\":100000000,\"nonce\":1234567890}",
     1_234_567_890, nil, nil, true,
     "0xb4a8ed51bac27ffe5d3397ef10e0ea14562ad2746222f8def23279d434c453f1",
     {"0x6dc4f04b28c4fda0e6885da7abd03500b75db6f13a89ecd8b5c42993edd58f3b",
      "0x3d38640e9f3ed2ba34fdcb932de9b45bda18408d57a1f61223b11f5c9f7f2c53", 28},
     {"0xa2a048e0fccad9e75abb40565ca02577d3941d295f7789e0ec18e3d78a023bed",
      "0x0390f679fcbde4d80db87072166983f9137d804ad477969240e936812bb825be", 27}},
    {"vault_transfer",
     "{\"type\":\"vaultTransfer\",\"vaultAddress\":\"0x1719884eb866cb12b2287399b15f7db5e7d775ea\",\"isDeposit\":true,\"usd\":1000000}",
     1_234_567_890, nil, nil, true,
     "0x688ed90a27b14f6fa2312dfb75330366cdad2efb06377278b8f3d479a2baf2c1",
     {"0xcf1862bca5f5e52d54708954fab3739168dc782c9193e94296e93f18f605192b",
      "0x7f0436dbcb5c17ae8e399ec8bfcfb38a056733a097286623f889716798c312e5", 27},
     {"0xadef7dc2b99cf8f79a78ca4744927a9c30527d6b87181878106eaea8a462a54b",
      "0x5adf9d6369c73ef3a0f31b3c26405252c5417b04bddea1735095a0b8022f58fc", 28}},
    {"vault_modify",
     "{\"type\":\"vaultModify\",\"vaultAddress\":\"0x1719884eb866cb12b2287399b15f7db5e7d775ea\",\"allowDeposits\":true,\"alwaysCloseOnWithdraw\":false}",
     1_234_567_890, nil, nil, true,
     "0xcbdb7597435597a1d88c9c2672fc64ec1c8f1e3a2028f94b40a7805e8f7e409e",
     {"0x43edf419d1cf3b1546ea0daa2d31b25c645f2a7f93c35ecb863f5d99a02dc8d4",
      "0x43a96ed4f039b3ab55dece711e76587935ba3d5dc00b8fdc56c5c077273da679", 28},
     {"0xfd865c479ad038fa5fc96ae2ff89f8f3a6c8a70073917a76a15d8e2bbc020626",
      "0x458cb061ea971163d5b62cffd818ad83b1d56f63ec6ffbb41f4d196c82493311", 28}},
    {"vault_distribute",
     "{\"type\":\"vaultDistribute\",\"vaultAddress\":\"0x1719884eb866cb12b2287399b15f7db5e7d775ea\",\"usd\":1000000}",
     1_234_567_890, nil, nil, true,
     "0x2c06073414289117682d68b4d9962dd70a59b752f15dbb2cc8f347ac1424dd85",
     {"0xf5c358d2718fedd0efb6dc12deee9ece2ba07dbfbe5470a54048e4fa99ddf289",
      "0x2e35a9b1f820f7370763177faf53854568ffcc7d5fc954063ecf5d64d9e65a20", 28},
     {"0xace0899dac57901019ff9c798fcc6024c3504011a94d0244fd3b9365ac41ae83",
      "0x70efe9b3dc8122e9bd0885892f710d82db026479af41844e026f75707db9ba2b", 27}},
    {"set_referrer", "{\"type\":\"setReferrer\",\"code\":\"TESTCODE\"}", 1_234_567_890, nil, nil,
     true, "0xa90149f2a1970e1d203ecbdef175cce3e17799ccdf7f05bffa5c6e488127b4d5",
     {"0x15ee356516fe183498fdd33a4056ea865a3323f5ffc29fbc403e9417bd908709",
      "0x135e485fd7eacccec60f01c86f62ef74e909f80e91e090f96e5f0232b0333e52", 28},
     {"0x3084b72f56fc130637ac4d7f3739d33865212ca5632fc3b3fcfdc7f771d44638",
      "0x00ea170cca9a7164ca5959b75e6fb066a18780c667a01c4e6ed0401feebc8294", 27}},
    {"register_referrer", "{\"type\":\"registerReferrer\",\"code\":\"TESTCODE\"}", 1_234_567_890,
     nil, nil, true, "0xee6f0ccc244e91fd1b509e73560b0abb010ef6c9002d7bb77c2b7c6553c3c6b0",
     {"0x85e27429ac25ed7272a0412e7807076ffca3a3cee8217e548aba53b98abb8264",
      "0x1e76f004fc433082da7843ecc26693dd2a62630c75da1a925e18d0600d2f9838", 28},
     {"0x37e12cf94f32c5371bda31170b7a2b37aa266e52d683b6b2e5d3dd69fed39d33",
      "0x4364c2952d4817f8b9e8a9b5386dc80facca9c4a7f48d6e3aa6153bc9c08723d", 27}},
    {"claim_rewards", "{\"type\":\"claimRewards\"}", 1_234_567_890, nil, nil, true,
     "0xd0469be3c27f0300e966b83eae479aa193744d38eb2603d3cbb9b4172ec474b3",
     {"0xd958c1b6e8a7cb6a086f26dcad8b2f512abdec60bae6a30d91ec984c66c2e057",
      "0x317468936cc26536ca35f5b54e040ea6d2cf7260dd8f4a58fd817e2e538486ee", 28},
     {"0xf30c0d75461ec70ab0eb1ce0fb8dcfbc0ee1f9806efdce09684db623779a2e49",
      "0x3aa61b21891527e1f005b306a1c6939bf5e3cffc13cba343cc23c61080f6a98a", 28}},
    {"evm_user_modify", "{\"type\":\"evmUserModify\",\"usingBigBlocks\":true}", 1_234_567_890,
     nil, nil, true, "0x711fb1836a1be55f1fdb55db412b0cfd1dead9586de200279a1d408d075a0669",
     {"0xc8703ea903378d1929126753323bc0fe89ed01a21902c1ebc94f7e2df67b6b51",
      "0x523f5c777990805c87aeb9caea186e6c02e76e0e3436e7498d07a537a9fb1b78", 28},
     {"0x9a66643f64b93a0c09475933dfcf77894694e37d67b4595fbe8763beae478dab",
      "0x541f76a9797a3494c0fb23b97bb83d86758dfdc5643e637ed79e6250c5ea4d70", 27}},
    {"noop", "{\"type\":\"noop\"}", 1_234_567_890, nil, nil, true,
     "0x2f31f6b11b0f2ab0773f7e37aa1f8901f771a9107b2fc99574476551e2bb8557",
     {"0x50900bd444fdccc62b191307a5e889ae9670c9cf56fa360fee693a34b0d46597",
      "0x2de9c308f14c69dda3a7c28e79d9dfe8fda31424cfdb6b51052f4ae5aa558be2", 28},
     {"0xf7ffdd3ac2bdb0ba06b1d16fecc97251af308ffaa33c8da2843b260cacf0bf96",
      "0x0e0aecf23efbb145962fd00fbc0a1c9b66b9d284c6db7543d8244c4ac02d5ee0", 27}},
    {"set_display_name", "{\"type\":\"setDisplayName\",\"displayName\":\"vector\"}",
     1_234_567_890, nil, nil, true,
     "0x27907f95aee52f984d6efc6187ddb5c3baba63391d9d972de00f801efb0e3e6f",
     {"0x53e8d83b2cb3d4f4a2c848aa61495f1f00b70519617e54837aacc9c8b1d58609",
      "0x4d2a900df7afa2f1704c14e3e9c9ee451aa534f04d360eb270a22d7ad9344ff8", 27},
     {"0x5983864dca287f89bbb1e4d13ef632cb5b012b146c43cb260d172c0e665940b9",
      "0x5143125ccd88b2c716ccc1142406ab8fe6b0da056cc6e15a85e3565752a6b292", 28}},
    {"twap_order",
     "{\"type\":\"twapOrder\",\"twap\":{\"a\":1,\"b\":true,\"s\":\"10\",\"r\":false,\"m\":30,\"t\":true}}",
     1_234_567_890, nil, nil, true,
     "0xbe5b53efe9514d98fd4c11ca1624992b74ad85c97e170575518433f3dc62e659",
     {"0x71fe585b8af7ed70c3c02ef16ed60346f38e938624df2598badbd9f45b8b84ff",
      "0x68e1d6dae3d70c09148bd3760c045ad8d9461b09d6d35f798a52eeac3740adc1", 28},
     {"0xd28173b52220fbb71929766d22ab1693e1a4e972c5c6f6f90d986549533acb86",
      "0x6eff68289371635dbe34be1b4ffe0da9c58b3709dfd1bf181fd5d6394c24bade", 27}},
    {"twap_cancel", "{\"type\":\"twapCancel\",\"a\":1,\"t\":5}", 1_234_567_890, nil, nil, true,
     "0x05065b21e68a8edaffb9c067aa3a39ca69993fdf41a673524b68598f846f7d2a",
     {"0xe9ee1c58415c2d85e07df26296aea29983a5febca8246e730b4ba229f407287e",
      "0x1b1285c1b038762c2462878f7e7fb7005d84c2c9c2bf72fae355384cb1d49c77", 28},
     {"0x4078a1cf259802d411c974b1875fd062550f5e6b34aaecbef04b0f674ccf23ea",
      "0x64e6d6d7c888aa084a00bf584ed48a65c7be96dd453204d61689f7839badb10b", 28}},
    {"reserve_request_weight", "{\"type\":\"reserveRequestWeight\",\"weight\":100}",
     1_234_567_890, nil, nil, true,
     "0x30c6ebe1f93a258b2aa67aa0da31a245ecbba755a21215ee9e32bb11907c1989",
     {"0x39fc0d15b6b91da2b69c1ed892bf32d2d2d92a5f319ed41deff89327464b58b5",
      "0x467c2137f82ac33aa0c67a947c65a0db214feed5c222618ee4a674b657eb069b", 28},
     {"0x4f4540dc730acc4c61b060d4585dee52ea362f3a88baf1cb73e27617c3c1a098",
      "0x60b6c34ae9d90674d6e498623d5dc9151d1c001d224f99d21269a39646704504", 27}},
    {"validator_l1_stream", "{\"type\":\"validatorL1Stream\",\"riskFreeRate\":\"0.05\"}",
     1_234_567_890, nil, nil, true,
     "0xdf9e9c205ecfc295355b3217615c65e67db38444d1167eabf09381b9cd1b072b",
     {"0x1844edf0473c5f5ad5ff5ee1b2bfb391ee996578e8cdaad70156c231c29643ce",
      "0x07320b3d5a9b30f9e9ecccb6c0f4b96854824381f9b2df5186806239ecd7ea0d", 28},
     {"0x977dfbf9dbbb9959b63e5c15c7b01f57206c32f1ef0d9bc7e99cbd43193d99f8",
      "0x713ad04339a30925299bd63990535edaea208cc148db853781e491cfdc9adb31", 27}},
    {"agent_set_abstraction", "{\"type\":\"agentSetAbstraction\",\"abstraction\":\"u\"}",
     1_234_567_890, nil, nil, true,
     "0x88b4781344b0a185d36f61fe24ce408b14afa2ac92bec4bfd6a77070751433ef",
     {"0x4b34b80231ad032a8cf8e4b864f51e84f8db83b3345a987746c7b41d49785ae4",
      "0x077af07cdaa4a91f6cf426fdcdd1850fad6e0e9370782c4d7f3c568e6598568d", 28},
     {"0x70c83c39765c8712a5fcb047bbbe8494633818e680572cca097f8d976ee991f6",
      "0x37a83367db0c24770566874371f0d3041dbf12f517b77d787575c479ebfc2077", 28}},
    {"agent_enable_dex_abstraction", "{\"type\":\"agentEnableDexAbstraction\"}", 1_234_567_890,
     nil, nil, true, "0x7067c21f6ac7da0db65c8d532d54a0e4e877427aae972c40e8c992fc01365136",
     {"0x4155768e5410aa724870120f527c83d0e1e584d9123c1a9039f4973e30bfbeb6",
      "0x3d60c45b3d6f11b5c946b9ea205d9e21ef14b55e423594d2d36123096fb9560d", 28},
     {"0x8a7fc31b88a946b1da2ac5f3519c0711b0bca080dab8a49f1a0aee6d16cbb9f9",
      "0x1f81ad136f24584966178fed7a3a89288971ed830d9192a6cbb1fbb7c083970c", 27}},
    {"borrow_lend",
     "{\"type\":\"borrowLend\",\"operation\":\"borrow\",\"token\":0,\"amount\":\"10\"}",
     1_234_567_890, nil, nil, true,
     "0x43cf31e248c0deb77b3a245b15d687d643657c52325ed31c859cf750494bff0f",
     {"0xfc9fee9de8c4c0bb7b4fc5605965297219543755be61bf5cb7fd0053cfa5399d",
      "0x0a188d9c02e8a2f064f6a39711dd789f4711f6159838843b865432b72a165a49", 27},
     {"0x9a70d995c0cb9c745439b770f42708ae0702c8f76bb28b0a66035a857a29d199",
      "0x25a5c822e6388c046853b1aa50429cc8c956867e6ae57fba15ebfd0ed20a6f5c", 27}},
    {"top_up_isolated_only_margin",
     "{\"type\":\"topUpIsolatedOnlyMargin\",\"asset\":1,\"leverage\":\"5\"}", 1_234_567_890, nil,
     nil, true, "0xa1897dfa9f80a07d7d6c913c3a3a9d60cd49915463e0ad40d5b33846b60fcddb",
     {"0x07a26f8330768efd1c57609e5f7e3df19ec73ff6e1e995ad153ae3ceda482486",
      "0x7bc928781920efb4119f89ff2ca0fe616c4c7910b743a44d67c59238c6e67398", 27},
     {"0x9eb8631ceecd545a6968d6ce65c17fbc3bd8a2aa522f280d8366db3f89069de8",
      "0x79d4471f3071b7de00bf902b2681e8c5c44cce2c57a02839f7be84629c106687", 27}},
    {"hip3_liquidator_transfer",
     "{\"type\":\"hip3LiquidatorTransfer\",\"dex\":\"test\",\"ntl\":1000000,\"isDeposit\":true}",
     1_234_567_890, nil, nil, true,
     "0xa89a583a246011283954ba4bc81e649cdcaf79e4869bd9e21447d553d0265d52",
     {"0x7dd8ec4aae68ef99841a21ff28e29982007ab0ff7cc16104186d16d74f28ee91",
      "0x2ad658831fb1efda5f98be91fbb0affa05ff31bbf59b2c68222c49d80746f477", 27},
     {"0x8551b30378931568d99c34bd44e7c9d149f7704dc954a05832e0f058ad86a458",
      "0x4f59e060d1848519fff7e76e5f225197ebe0467e4ef5750934e731d5b1feae34", 27}},
    {"authorize_aqav2_role",
     "{\"type\":\"authorizeAqav2Role\",\"token\":0,\"role\":\"deployer\"}", 1_234_567_890, nil,
     nil, true, "0x5ecf871da7bb6bd46024d348b2b7f06d0e11c554e18a6caa6a2247bc9e65edad",
     {"0xc7b539425b4ec38379e1cc593275da70089506a3034742bb159659b306bb894d",
      "0x34a54a30c49da01cf75d3d2217befae68ff219724161ae447dea0ceb96c606fc", 27},
     {"0x85c7cea5cfa85698e851e51f85883e40e52c8643cf22578bc5dae3f7ec406357",
      "0x5be2a8269b4ca66f36ebe831ef06e24f5b265d04cba670c82291f4ab8d9e6196", 27}},
    {"finalize_evm_contract",
     "{\"type\":\"finalizeEvmContract\",\"token\":0,\"input\":{\"create\":{\"nonce\":1}}}",
     1_234_567_890, nil, nil, true,
     "0x14a49dcd450e38247fe2d1555683a51086b459f5bb9a7d56f6f380e8c9932660",
     {"0x96815931e022d20f2f8f047b3f88ec0bb9ae14612ca50c545fda7f47a7f917a9",
      "0x79e9b242288bcbd0129a1960dbf8d26ce084d792d1c5b14f340e16b1050fd08d", 28},
     {"0x27ad1e8f942f2e8b634386d4898e37e740fce4d57514c45b111347516928dbc6",
      "0x339c3d98d1c17f6a4a5201a15c293382b377e85623518905671c646feb7c0e2b", 28}},
    {"gossip_priority_bid",
     "{\"type\":\"gossipPriorityBid\",\"slotId\":1,\"ip\":\"1.2.3.4\",\"maxGas\":1000}",
     1_234_567_890, nil, nil, true,
     "0x8dacfeddaef7257e38e45f592ba2dae2d8ac153604d864edeb5d35778723af5a",
     {"0x1df34fdff0bcec723c4a8db42c52e99e4d58fc5e8054cb4e2b5d0cd808dd2692",
      "0x5dd992e460d17acbd2899eb96e66cfe7d76ae8c3dc42262f3fdd191eaee3f6d9", 28},
     {"0x68b1d1b80fa9a605abb8c7f1b1c070666c55d01a06aff1b2f846f3488e2a2a2c",
      "0x04bc8f5f4ee2ba2e2bc31c42360f0486f6432d9c154d804b2fae2d879b7e6627", 27}},
    {"agent_send_asset",
     "{\"type\":\"agentSendAsset\",\"destination\":\"0x1d9470d4b963f552e6f671a81619d395877bf409\",\"sourceDex\":\"\",\"destinationDex\":\"spot\",\"token\":\"USDC:0xeb62eee3685fc4c43992febcd9e75443\",\"amount\":\"100\",\"fromSubAccount\":\"\",\"nonce\":1234567890}",
     1_234_567_890, nil, nil, true,
     "0xd91df56b68836cd051bd8e784f5af706ee699f14f38edfaf5eac651feae38d72",
     {"0x24758505bfdbb0a40b0ffa111dacfd8dac721e209ee0cf483d3bc4872aa9ba3a",
      "0x40e32cd3fac833efc949772bf67f044f2e4b4f6e1521ef00d81fb3ab0ca212d9", 28},
     {"0x8121ac9d3aafa2688330d53dff956662f3d8bf3bb7f5573ce344413bb58848a2",
      "0x194268b53a861c443549a4722f750c39b3123f1877f83686f0305c952330b280", 27}},
    {"usd_class_transfer_l1",
     "{\"type\":\"usdClassTransfer\",\"amount\":\"100\",\"toPerp\":true}", 1_234_567_890, nil,
     nil, true, "0x607a1e6d2e1ff2ab358135c363958ec9dba98e3d21e81d87ef5d1a4ef58f4610",
     {"0x1d12d0b4caba694166c3a41145e66d85a1bebe7315c10db2d00c98db6a8c0ad7",
      "0x01b6b5f0bd6b83d3b96c0a8b6070411817883f9fc8a89a3cfb9579f8590bf694", 27},
     {"0x961123352717bd0aea5d45b66e0d0ea93aaca2e938c0f285a806e67e4911f3f4",
      "0x0ef1f6b6983b55ba12645cb4a509ee5c5347a6dbe0905438fd78170ca52e24f7", 28}},
    {"activate_outcome_deployer", "{\"type\":\"activateOutcomeDeployer\",\"isDeactivate\":false}",
     1_234_567_890, nil, nil, true,
     "0x9831431b72b4c2cb688a9af7fe5a8beb1d8ca2866ba315ac936d7934e5ece963",
     {"0x76c4c114abad9bfed06a0d00e9c116e8c6d89aeee57fe5ebcc2a4a0d52ac8120",
      "0x296769358d541524b36d777dec2d4a9aee16c5f54a1bb2755635060e07861ee6", 27},
     {"0x47396ac95e980dd8deef75c3a24fbb95fe64199a8e875004d1bf4daafd3ce6bd",
      "0x4ef67be84ce58ae4c86b1f2ba4626b2d043698533532204db70b9775e831770b", 28}}
  ]

  # {name, primary_type, domain_json, types_json, message_json, {r, s, v}}
  @user_signed_vectors [
    {"usd_send_421614", "HyperliquidTransaction:UsdSend",
     "{\"name\":\"HyperliquidSignTransaction\",\"version\":\"1\",\"chainId\":421614,\"verifyingContract\":\"0x0000000000000000000000000000000000000000\"}",
     "{\"HyperliquidTransaction:UsdSend\":[{\"name\":\"hyperliquidChain\",\"type\":\"string\"},{\"name\":\"destination\",\"type\":\"string\"},{\"name\":\"amount\",\"type\":\"string\"},{\"name\":\"time\",\"type\":\"uint64\"}]}",
     "{\"hyperliquidChain\":\"Mainnet\",\"destination\":\"0x5e9ee1089755c3435139848e47e6635505d5a13a\",\"amount\":\"1\",\"time\":1687816341423,\"signatureChainId\":\"0x66eee\"}",
     {"0x9adbd066e8ae671f06b5d18e51fd2ec11b5443d64b13718028c7ff06905c71fb",
      "0x1eba4172075f8a8037481400ae86ed56c5e5f672e3db084528a8e3b2daeff976", 28}},
    {"spot_send_421614", "HyperliquidTransaction:SpotSend",
     "{\"name\":\"HyperliquidSignTransaction\",\"version\":\"1\",\"chainId\":421614,\"verifyingContract\":\"0x0000000000000000000000000000000000000000\"}",
     "{\"HyperliquidTransaction:SpotSend\":[{\"name\":\"hyperliquidChain\",\"type\":\"string\"},{\"name\":\"destination\",\"type\":\"string\"},{\"name\":\"token\",\"type\":\"string\"},{\"name\":\"amount\",\"type\":\"string\"},{\"name\":\"time\",\"type\":\"uint64\"}]}",
     "{\"hyperliquidChain\":\"Mainnet\",\"destination\":\"0x5e9ee1089755c3435139848e47e6635505d5a13a\",\"token\":\"USDC:0xeb62eee3685fc4c43992febcd9e75443\",\"amount\":\"1\",\"time\":1687816341423,\"signatureChainId\":\"0x66eee\"}",
     {"0x60fdd21a858c4a8b3278d047a7ba85bb8ce933e8a28f9dc89989e2e2bc325f45",
      "0x1823ce35e5b1f0aae05be776f1a3eb243c2dbc77f8f41cc3edf5c72825f04287", 27}},
    {"withdraw3_421614", "HyperliquidTransaction:Withdraw",
     "{\"name\":\"HyperliquidSignTransaction\",\"version\":\"1\",\"chainId\":421614,\"verifyingContract\":\"0x0000000000000000000000000000000000000000\"}",
     "{\"HyperliquidTransaction:Withdraw\":[{\"name\":\"hyperliquidChain\",\"type\":\"string\"},{\"name\":\"destination\",\"type\":\"string\"},{\"name\":\"amount\",\"type\":\"string\"},{\"name\":\"time\",\"type\":\"uint64\"}]}",
     "{\"hyperliquidChain\":\"Mainnet\",\"destination\":\"0x5e9ee1089755c3435139848e47e6635505d5a13a\",\"amount\":\"1\",\"time\":1687816341423,\"signatureChainId\":\"0x66eee\"}",
     {"0xa155eccb6deecc343d5ce1d69ca20a6b8959cc3f21ffff6b82790e2e9f7fe888",
      "0x6e78708de0806beceab552e1a97378fa80090d902bfffa8b6ee6b35d713f58c4", 28}},
    {"usd_class_transfer_421614", "HyperliquidTransaction:UsdClassTransfer",
     "{\"name\":\"HyperliquidSignTransaction\",\"version\":\"1\",\"chainId\":421614,\"verifyingContract\":\"0x0000000000000000000000000000000000000000\"}",
     "{\"HyperliquidTransaction:UsdClassTransfer\":[{\"name\":\"hyperliquidChain\",\"type\":\"string\"},{\"name\":\"amount\",\"type\":\"string\"},{\"name\":\"toPerp\",\"type\":\"bool\"},{\"name\":\"nonce\",\"type\":\"uint64\"}]}",
     "{\"hyperliquidChain\":\"Mainnet\",\"amount\":\"100\",\"toPerp\":true,\"nonce\":1687816341423,\"signatureChainId\":\"0x66eee\"}",
     {"0xeeb88f23eace172797fc664ff89e1acbde05651d6e43c45432b90a05544e6c28",
      "0x0dd83b4737c7ea3b5cddd20b6f3cec84dafaeae1546c20460e397fea44233170", 27}},
    {"token_delegate_421614", "HyperliquidTransaction:TokenDelegate",
     "{\"name\":\"HyperliquidSignTransaction\",\"version\":\"1\",\"chainId\":421614,\"verifyingContract\":\"0x0000000000000000000000000000000000000000\"}",
     "{\"HyperliquidTransaction:TokenDelegate\":[{\"name\":\"hyperliquidChain\",\"type\":\"string\"},{\"name\":\"validator\",\"type\":\"address\"},{\"name\":\"wei\",\"type\":\"uint64\"},{\"name\":\"isUndelegate\",\"type\":\"bool\"},{\"name\":\"nonce\",\"type\":\"uint64\"}]}",
     "{\"hyperliquidChain\":\"Mainnet\",\"validator\":\"0x1d9470d4b963f552e6f671a81619d395877bf409\",\"wei\":100000000,\"isUndelegate\":false,\"nonce\":1687816341423,\"signatureChainId\":\"0x66eee\"}",
     {"0x5f9051975bf851d2d8ce8149d770b1aa173334acb0ede45691fcaee013d4bd0c",
      "0x06234355a583df3e18ba107e32f5c0de7eee0e9f04c97542d99877838f479b0b", 27}},
    {"approve_agent_421614", "HyperliquidTransaction:ApproveAgent",
     "{\"name\":\"HyperliquidSignTransaction\",\"version\":\"1\",\"chainId\":421614,\"verifyingContract\":\"0x0000000000000000000000000000000000000000\"}",
     "{\"HyperliquidTransaction:ApproveAgent\":[{\"name\":\"hyperliquidChain\",\"type\":\"string\"},{\"name\":\"agentAddress\",\"type\":\"address\"},{\"name\":\"agentName\",\"type\":\"string\"},{\"name\":\"nonce\",\"type\":\"uint64\"}]}",
     "{\"hyperliquidChain\":\"Mainnet\",\"agentAddress\":\"0x1d9470d4b963f552e6f671a81619d395877bf409\",\"agentName\":\"agent\",\"nonce\":1687816341423,\"signatureChainId\":\"0x66eee\"}",
     {"0xa73999aeae0c688601e37a7b62b92be104d806d560794230df1a5b274b6a5de0",
      "0x121570fc3b914104f6c93c9f0abed3735db285a7579eab24310377f4e5d06184", 28}},
    {"user_portfolio_margin_421614", "HyperliquidTransaction:UserPortfolioMargin",
     "{\"name\":\"HyperliquidSignTransaction\",\"version\":\"1\",\"chainId\":421614,\"verifyingContract\":\"0x0000000000000000000000000000000000000000\"}",
     "{\"HyperliquidTransaction:UserPortfolioMargin\":[{\"name\":\"hyperliquidChain\",\"type\":\"string\"},{\"name\":\"user\",\"type\":\"address\"},{\"name\":\"enabled\",\"type\":\"bool\"},{\"name\":\"nonce\",\"type\":\"uint64\"}]}",
     "{\"hyperliquidChain\":\"Mainnet\",\"user\":\"0x1d9470d4b963f552e6f671a81619d395877bf409\",\"enabled\":true,\"nonce\":1687816341423,\"signatureChainId\":\"0x66eee\"}",
     {"0xcecca6b5a263e2e874c7923bfddd852c0182fd901f49bbb60e7763eed9b3ab27",
      "0x6de12a217b0cf4dba1a9ae9333fbb4a106560a42053d21426c0766a1ab9f3c94", 28}},
    {"user_dex_abstraction_421614", "HyperliquidTransaction:UserDexAbstraction",
     "{\"name\":\"HyperliquidSignTransaction\",\"version\":\"1\",\"chainId\":421614,\"verifyingContract\":\"0x0000000000000000000000000000000000000000\"}",
     "{\"HyperliquidTransaction:UserDexAbstraction\":[{\"name\":\"hyperliquidChain\",\"type\":\"string\"},{\"name\":\"user\",\"type\":\"address\"},{\"name\":\"enabled\",\"type\":\"bool\"},{\"name\":\"nonce\",\"type\":\"uint64\"}]}",
     "{\"hyperliquidChain\":\"Mainnet\",\"user\":\"0x1d9470d4b963f552e6f671a81619d395877bf409\",\"enabled\":true,\"nonce\":1687816341423,\"signatureChainId\":\"0x66eee\"}",
     {"0x359abd5ec11d5e630cfea1c208b6857e497d8cd0a1b17961afdc25f2ae796943",
      "0x34ff77b37a3e3a2e1a5dc292cbc31ac78d31cda06e4769ee4328f8cbbdcd23b3", 27}},
    {"link_staking_user_421614", "HyperliquidTransaction:LinkStakingUser",
     "{\"name\":\"HyperliquidSignTransaction\",\"version\":\"1\",\"chainId\":421614,\"verifyingContract\":\"0x0000000000000000000000000000000000000000\"}",
     "{\"HyperliquidTransaction:LinkStakingUser\":[{\"name\":\"hyperliquidChain\",\"type\":\"string\"},{\"name\":\"user\",\"type\":\"address\"},{\"name\":\"isFinalize\",\"type\":\"bool\"},{\"name\":\"nonce\",\"type\":\"uint64\"}]}",
     "{\"hyperliquidChain\":\"Mainnet\",\"user\":\"0x1d9470d4b963f552e6f671a81619d395877bf409\",\"isFinalize\":false,\"nonce\":1687816341423,\"signatureChainId\":\"0x66eee\"}",
     {"0xa679a4a7c4aa6b1ebce4a8546573853f98ca21bab83889978f5c22c9a12aa05b",
      "0x20709c2af5a2e67e4a5021beab7cd534ef1be2324ca0bfd210b93dcf96cf7bbe", 28}},
    {"convert_to_multi_sig_user_421614", "HyperliquidTransaction:ConvertToMultiSigUser",
     "{\"name\":\"HyperliquidSignTransaction\",\"version\":\"1\",\"chainId\":421614,\"verifyingContract\":\"0x0000000000000000000000000000000000000000\"}",
     "{\"HyperliquidTransaction:ConvertToMultiSigUser\":[{\"name\":\"hyperliquidChain\",\"type\":\"string\"},{\"name\":\"signers\",\"type\":\"string\"},{\"name\":\"nonce\",\"type\":\"uint64\"}]}",
     "{\"hyperliquidChain\":\"Mainnet\",\"signers\":\"{\\\"authorizedUsers\\\":[\\\"0x1d9470d4b963f552e6f671a81619d395877bf409\\\"],\\\"threshold\\\":1}\",\"nonce\":1687816341423,\"signatureChainId\":\"0x66eee\"}",
     {"0xae97304fac9c30bc60b99b928af5efde9054e1e25f1a0e2a6fb5d82ee398c219",
      "0x1361b0d048a8240206dd0fb04f60971370b98071a0dfbbd1f091e3723fa950fb", 27}},
    {"approve_builder_fee_421614", "HyperliquidTransaction:ApproveBuilderFee",
     "{\"name\":\"HyperliquidSignTransaction\",\"version\":\"1\",\"chainId\":421614,\"verifyingContract\":\"0x0000000000000000000000000000000000000000\"}",
     "{\"HyperliquidTransaction:ApproveBuilderFee\":[{\"name\":\"hyperliquidChain\",\"type\":\"string\"},{\"name\":\"maxFeeRate\",\"type\":\"string\"},{\"name\":\"builder\",\"type\":\"address\"},{\"name\":\"nonce\",\"type\":\"uint64\"}]}",
     "{\"hyperliquidChain\":\"Mainnet\",\"maxFeeRate\":\"0.001%\",\"builder\":\"0x1d9470d4b963f552e6f671a81619d395877bf409\",\"nonce\":1687816341423,\"signatureChainId\":\"0x66eee\"}",
     {"0xb2b1df833cb6a99f4c2416ee3d8f2be484f3104b949256f6f478a63c2c2eadc8",
      "0x1a9a2925db804f1a8d4dd6abdd4d198ffbf544e6b7c38a9307af47ebc8b8d623", 28}},
    {"usd_send_42161", "HyperliquidTransaction:UsdSend",
     "{\"name\":\"HyperliquidSignTransaction\",\"version\":\"1\",\"chainId\":42161,\"verifyingContract\":\"0x0000000000000000000000000000000000000000\"}",
     "{\"HyperliquidTransaction:UsdSend\":[{\"name\":\"hyperliquidChain\",\"type\":\"string\"},{\"name\":\"destination\",\"type\":\"string\"},{\"name\":\"amount\",\"type\":\"string\"},{\"name\":\"time\",\"type\":\"uint64\"}]}",
     "{\"hyperliquidChain\":\"Mainnet\",\"destination\":\"0x5e9ee1089755c3435139848e47e6635505d5a13a\",\"amount\":\"1\",\"time\":1687816341423,\"signatureChainId\":\"0xa4b1\"}",
     {"0xff67e331a1466b4afaf343f251e3bc9cdef48cc88c6ff60c41559905f9b8896a",
      "0x032928340520808eedb79faa05a67664e8f8393e9c54e5a7277d13212a209f07", 28}},
    {"spot_send_42161", "HyperliquidTransaction:SpotSend",
     "{\"name\":\"HyperliquidSignTransaction\",\"version\":\"1\",\"chainId\":42161,\"verifyingContract\":\"0x0000000000000000000000000000000000000000\"}",
     "{\"HyperliquidTransaction:SpotSend\":[{\"name\":\"hyperliquidChain\",\"type\":\"string\"},{\"name\":\"destination\",\"type\":\"string\"},{\"name\":\"token\",\"type\":\"string\"},{\"name\":\"amount\",\"type\":\"string\"},{\"name\":\"time\",\"type\":\"uint64\"}]}",
     "{\"hyperliquidChain\":\"Mainnet\",\"destination\":\"0x5e9ee1089755c3435139848e47e6635505d5a13a\",\"token\":\"USDC:0xeb62eee3685fc4c43992febcd9e75443\",\"amount\":\"1\",\"time\":1687816341423,\"signatureChainId\":\"0xa4b1\"}",
     {"0x4e37108b707e9ff9aecdf1326a66e7f9cdf116fcdc50bcaab168880a79e240cd",
      "0x23452d87d6f901574bbe9c76eb16f85e533082df4f4522541f7582c6b48c0e13", 27}},
    {"withdraw3_42161", "HyperliquidTransaction:Withdraw",
     "{\"name\":\"HyperliquidSignTransaction\",\"version\":\"1\",\"chainId\":42161,\"verifyingContract\":\"0x0000000000000000000000000000000000000000\"}",
     "{\"HyperliquidTransaction:Withdraw\":[{\"name\":\"hyperliquidChain\",\"type\":\"string\"},{\"name\":\"destination\",\"type\":\"string\"},{\"name\":\"amount\",\"type\":\"string\"},{\"name\":\"time\",\"type\":\"uint64\"}]}",
     "{\"hyperliquidChain\":\"Mainnet\",\"destination\":\"0x5e9ee1089755c3435139848e47e6635505d5a13a\",\"amount\":\"1\",\"time\":1687816341423,\"signatureChainId\":\"0xa4b1\"}",
     {"0x4929562d7f5ba20a15d883c6b7fbbabbdf423ce529595a59e913e2b4092105ff",
      "0x0d8988041184c87a11ddfdaa7dfd810b099f8ef2d0e82beaa0cb136c3e5e99ab", 27}},
    {"usd_class_transfer_42161", "HyperliquidTransaction:UsdClassTransfer",
     "{\"name\":\"HyperliquidSignTransaction\",\"version\":\"1\",\"chainId\":42161,\"verifyingContract\":\"0x0000000000000000000000000000000000000000\"}",
     "{\"HyperliquidTransaction:UsdClassTransfer\":[{\"name\":\"hyperliquidChain\",\"type\":\"string\"},{\"name\":\"amount\",\"type\":\"string\"},{\"name\":\"toPerp\",\"type\":\"bool\"},{\"name\":\"nonce\",\"type\":\"uint64\"}]}",
     "{\"hyperliquidChain\":\"Mainnet\",\"amount\":\"100\",\"toPerp\":true,\"nonce\":1687816341423,\"signatureChainId\":\"0xa4b1\"}",
     {"0xcac32ff4b39b5ba68b3f593690a062e6281f8d31f67d2f032418d58ded998e25",
      "0x67c218d47c94a58705e11f65c6c55bb63a8b7e3d84e049661694c44cd3de85a6", 28}},
    {"token_delegate_42161", "HyperliquidTransaction:TokenDelegate",
     "{\"name\":\"HyperliquidSignTransaction\",\"version\":\"1\",\"chainId\":42161,\"verifyingContract\":\"0x0000000000000000000000000000000000000000\"}",
     "{\"HyperliquidTransaction:TokenDelegate\":[{\"name\":\"hyperliquidChain\",\"type\":\"string\"},{\"name\":\"validator\",\"type\":\"address\"},{\"name\":\"wei\",\"type\":\"uint64\"},{\"name\":\"isUndelegate\",\"type\":\"bool\"},{\"name\":\"nonce\",\"type\":\"uint64\"}]}",
     "{\"hyperliquidChain\":\"Mainnet\",\"validator\":\"0x1d9470d4b963f552e6f671a81619d395877bf409\",\"wei\":100000000,\"isUndelegate\":false,\"nonce\":1687816341423,\"signatureChainId\":\"0xa4b1\"}",
     {"0x4c10e4d26a3f71874165ce627e5cb6a541be706d2927c22d14eea619fe0b75f8",
      "0x463b32f6fdc2a9e22a44edb62204e55263b5c40e570143f8de4663e5f7248595", 27}},
    {"approve_agent_42161", "HyperliquidTransaction:ApproveAgent",
     "{\"name\":\"HyperliquidSignTransaction\",\"version\":\"1\",\"chainId\":42161,\"verifyingContract\":\"0x0000000000000000000000000000000000000000\"}",
     "{\"HyperliquidTransaction:ApproveAgent\":[{\"name\":\"hyperliquidChain\",\"type\":\"string\"},{\"name\":\"agentAddress\",\"type\":\"address\"},{\"name\":\"agentName\",\"type\":\"string\"},{\"name\":\"nonce\",\"type\":\"uint64\"}]}",
     "{\"hyperliquidChain\":\"Mainnet\",\"agentAddress\":\"0x1d9470d4b963f552e6f671a81619d395877bf409\",\"agentName\":\"agent\",\"nonce\":1687816341423,\"signatureChainId\":\"0xa4b1\"}",
     {"0x80faa7bc459ac17d0add234184435784e301cd4c795361d94f905ebbed36e7c7",
      "0x2ee65ec5957781a0521fe6cbdce32ff1eafbb5b6fe55bd7ddcd3d3c668e0194f", 28}},
    {"user_portfolio_margin_42161", "HyperliquidTransaction:UserPortfolioMargin",
     "{\"name\":\"HyperliquidSignTransaction\",\"version\":\"1\",\"chainId\":42161,\"verifyingContract\":\"0x0000000000000000000000000000000000000000\"}",
     "{\"HyperliquidTransaction:UserPortfolioMargin\":[{\"name\":\"hyperliquidChain\",\"type\":\"string\"},{\"name\":\"user\",\"type\":\"address\"},{\"name\":\"enabled\",\"type\":\"bool\"},{\"name\":\"nonce\",\"type\":\"uint64\"}]}",
     "{\"hyperliquidChain\":\"Mainnet\",\"user\":\"0x1d9470d4b963f552e6f671a81619d395877bf409\",\"enabled\":true,\"nonce\":1687816341423,\"signatureChainId\":\"0xa4b1\"}",
     {"0x1dc4be4e067460a189a37093b55b3e5fb73f13c4c8762099af7028ed2793dfc4",
      "0x5617005ec24ef9cab46729152cd14e5eb6e2fca25b310927f9e52d0f1568fa93", 28}},
    {"user_dex_abstraction_42161", "HyperliquidTransaction:UserDexAbstraction",
     "{\"name\":\"HyperliquidSignTransaction\",\"version\":\"1\",\"chainId\":42161,\"verifyingContract\":\"0x0000000000000000000000000000000000000000\"}",
     "{\"HyperliquidTransaction:UserDexAbstraction\":[{\"name\":\"hyperliquidChain\",\"type\":\"string\"},{\"name\":\"user\",\"type\":\"address\"},{\"name\":\"enabled\",\"type\":\"bool\"},{\"name\":\"nonce\",\"type\":\"uint64\"}]}",
     "{\"hyperliquidChain\":\"Mainnet\",\"user\":\"0x1d9470d4b963f552e6f671a81619d395877bf409\",\"enabled\":true,\"nonce\":1687816341423,\"signatureChainId\":\"0xa4b1\"}",
     {"0xaf03978ca46edae8b83eced042efc6600ced4c88ddbaf0eeba61a37892c43047",
      "0x66321e7294514f4808db051fb5095fd4ed96460d373cfd6fd7be27bac61582ba", 28}},
    {"link_staking_user_42161", "HyperliquidTransaction:LinkStakingUser",
     "{\"name\":\"HyperliquidSignTransaction\",\"version\":\"1\",\"chainId\":42161,\"verifyingContract\":\"0x0000000000000000000000000000000000000000\"}",
     "{\"HyperliquidTransaction:LinkStakingUser\":[{\"name\":\"hyperliquidChain\",\"type\":\"string\"},{\"name\":\"user\",\"type\":\"address\"},{\"name\":\"isFinalize\",\"type\":\"bool\"},{\"name\":\"nonce\",\"type\":\"uint64\"}]}",
     "{\"hyperliquidChain\":\"Mainnet\",\"user\":\"0x1d9470d4b963f552e6f671a81619d395877bf409\",\"isFinalize\":false,\"nonce\":1687816341423,\"signatureChainId\":\"0xa4b1\"}",
     {"0x40709830ac98dc7871fda5d880bf6d9664cea21102bf3cc83dec44412a63c472",
      "0x58f7f6ec69aac7e28b68b5b276cfac3f932c41cecb3704dcabf8b8ab2d47f3d4", 27}},
    {"convert_to_multi_sig_user_42161", "HyperliquidTransaction:ConvertToMultiSigUser",
     "{\"name\":\"HyperliquidSignTransaction\",\"version\":\"1\",\"chainId\":42161,\"verifyingContract\":\"0x0000000000000000000000000000000000000000\"}",
     "{\"HyperliquidTransaction:ConvertToMultiSigUser\":[{\"name\":\"hyperliquidChain\",\"type\":\"string\"},{\"name\":\"signers\",\"type\":\"string\"},{\"name\":\"nonce\",\"type\":\"uint64\"}]}",
     "{\"hyperliquidChain\":\"Mainnet\",\"signers\":\"{\\\"authorizedUsers\\\":[\\\"0x1d9470d4b963f552e6f671a81619d395877bf409\\\"],\\\"threshold\\\":1}\",\"nonce\":1687816341423,\"signatureChainId\":\"0xa4b1\"}",
     {"0x33a4f19a61d1f8f75ce7d59c0dfa6ba327fe54e75ad8261cd1a96d3f0dd70e0d",
      "0x34e6b896b91facd916fedccd879e579155aba4daf35113a64ff62d982f360756", 28}},
    {"approve_builder_fee_42161", "HyperliquidTransaction:ApproveBuilderFee",
     "{\"name\":\"HyperliquidSignTransaction\",\"version\":\"1\",\"chainId\":42161,\"verifyingContract\":\"0x0000000000000000000000000000000000000000\"}",
     "{\"HyperliquidTransaction:ApproveBuilderFee\":[{\"name\":\"hyperliquidChain\",\"type\":\"string\"},{\"name\":\"maxFeeRate\",\"type\":\"string\"},{\"name\":\"builder\",\"type\":\"address\"},{\"name\":\"nonce\",\"type\":\"uint64\"}]}",
     "{\"hyperliquidChain\":\"Mainnet\",\"maxFeeRate\":\"0.001%\",\"builder\":\"0x1d9470d4b963f552e6f671a81619d395877bf409\",\"nonce\":1687816341423,\"signatureChainId\":\"0xa4b1\"}",
     {"0xc833e4e98281ea8e1c743455434278182d4b75edb4d3ed2d08e5174083c92c04",
      "0x3cacd0c5de0b738cc440a1a691842ba6bd013cf947ca933430d6ed67e426bdb6", 27}}
  ]

  describe "L1 action hash (msgpack + keccak)" do
    for {name, json, nonce, vault, expires, _ordered, hash, _m, _t} <- @l1_vectors do
      test "#{name} hashes to the Python SDK's action_hash" do
        assert Signer.compute_connection_id_ex(
                 unquote(json),
                 unquote(nonce),
                 unquote(vault),
                 unquote(expires)
               ) == unquote(hash)
      end
    end
  end

  describe "L1 action signature (phantom agent EIP-712)" do
    for {name, json, nonce, vault, expires, _ordered, _hash, {mr, ms, mv}, {tr, ts, tv}} <-
          @l1_vectors do
      test "#{name} mainnet r/s/v matches the Python SDK" do
        assert Action.sign_json(
                 @priv_key,
                 unquote(json),
                 unquote(nonce),
                 unquote(vault),
                 unquote(expires),
                 true
               ) == {:ok, %{r: unquote(mr), s: unquote(ms), v: unquote(mv)}}
      end

      test "#{name} testnet r/s/v matches the Python SDK" do
        assert Action.sign_json(
                 @priv_key,
                 unquote(json),
                 unquote(nonce),
                 unquote(vault),
                 unquote(expires),
                 false
               ) == {:ok, %{r: unquote(tr), s: unquote(ts), v: unquote(tv)}}
      end
    end
  end

  describe "canonical key order (H3)" do
    # Decoding the canonical JSON into plain Elixir maps destroys key order
    # (BEAM map iteration order is not insertion order). `Action.ordered/1` has
    # to put it back, byte for byte, or the hash above is unreachable from the
    # action builders.
    for {name, json, _nonce, _vault, _expires, ordered, _hash, _m, _t} <- @l1_vectors,
        ordered do
      test "#{name} survives a scrambled round-trip through Action.ordered/1" do
        assert unquote(json)
               |> Jason.decode!()
               |> Action.ordered()
               |> Jason.encode!() == unquote(json)
      end
    end

    test "every action module's declared type has a canonical key order" do
      module_types =
        Path.wildcard(Path.expand("../lib/hyperliquid/api/exchange/*.ex", __DIR__))
        |> Enum.flat_map(fn path ->
          Regex.scan(~r/(?:\{:type,\s*|type:\s*)"([a-zA-Z0-9]+)"/, File.read!(path))
        end)
        |> Enum.map(fn [_, type] -> type end)
        |> Enum.uniq()

      # Deploy/validator actions are tagged unions whose shape is chosen by the
      # caller; they build their own `Jason.OrderedObject` explicitly.
      unions =
        ~w(perpDeploy spotDeploy outcomeDeploy userOutcome cSignerAction cValidatorAction
           delegate undelegate changeSigner editValidator)

      eip712_primitives = ~w(string bool address bytes bytes32 uint8 uint64 uint256)

      missing =
        module_types
        |> Enum.reject(&(&1 in unions or &1 in eip712_primitives))
        |> Enum.reject(&(Action.key_order(&1) != nil))

      assert missing == [],
             "actions without a declared key order: #{inspect(missing)}"
    end
  end

  describe "user-signed actions (EIP-712 typed data)" do
    for {name, primary_type, domain, types, message, {r, s, v}} <- @user_signed_vectors do
      test "#{name} matches the Python SDK" do
        sig =
          Signer.sign_typed_data(
            @priv_key,
            unquote(domain),
            unquote(types),
            unquote(message),
            unquote(primary_type)
          )

        assert Map.take(sig, ["r", "s", "v"]) == %{
                 "r" => unquote(r),
                 "s" => unquote(s),
                 "v" => unquote(v)
               }
      end
    end
  end
end
