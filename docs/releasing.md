# Releasing

Cutting a release of the `hyperliquid` Hex package is two commands — one of
them only ever runs once per machine.

```bash
scripts/hex-auth-setup.sh     # once per machine: store a hex.pm API key
scripts/release.sh 0.5.0      # every release
```

Everything else — the version bump, the CHANGELOG, the dependency snippets in
the README and `docs/`, the git tag, the precompiled-NIF build on GitHub
Actions, the NIF checksum file, a consumer smoke test, the Hex tarball, the
docs, the publish and the GitHub release notes — is driven by
`scripts/release.sh`.

Rehearse first if you like. `--dry-run` does preflight, the version bump and
the full check suite, then stops before the first push:

```bash
scripts/release.sh 0.5.0 --dry-run
git diff              # inspect
git checkout -- .     # discard
```

---

## One-time setup

`scripts/hex-auth-setup.sh` writes `HEX_API_KEY` to
`~/.config/hyperliquid-release/hex.env` (file `0600`, directory `0700`) and
verifies it with `mix hex.user whoami` before writing. The key is never echoed
and never passed on a command line.

Hex 2.x has no `mix hex.user key generate` — `mix hex.user` offers only
`whoami`, `auth` and `deauth`, and `auth` stores a locally *encrypted* key that
cannot be read back as plaintext. So the key comes from the web dashboard:

1. <https://hex.pm/dashboard/keys> → **Generate new key**
2. Permissions: **`api` → `write`**
3. Copy it (hex.pm shows it exactly once) and paste it into the script's hidden
   prompt.

You can skip the script and write the file by hand:

```bash
mkdir -p ~/.config/hyperliquid-release && chmod 0700 ~/.config/hyperliquid-release
printf 'HEX_API_KEY=%s\n' "$KEY" > ~/.config/hyperliquid-release/hex.env
chmod 0600 ~/.config/hyperliquid-release/hex.env
```

Point `HEX_RELEASE_ENV` at a different path to override the location. Revoke a
key at <https://hex.pm/dashboard/keys>; delete the file and re-run the setup
script to replace it.

If no key is present, `scripts/release.sh` still does everything else and stops
at a **READY TO PUBLISH** banner with exit status 0. That is a normal outcome,
not a failure — re-run the same command once the key exists and only the
publish step will actually do work.

---

## What the release script does

Run it from a clean `main` that matches `origin/main`.

| Step | What happens | Already done? |
|---|---|---|
| **0** | Preflight: on `main`, clean tree, `git fetch`, `main == origin/main`, `gh` authenticated, `elixir`/`mix`/`cargo`/`rustc` on PATH, NIF matrix size read from the workflow | — |
| **1** | `@version` in `mix.exs`; CHANGELOG `## Unreleased` → `## <version> (<date>)`; `{:hyperliquid, "~> X.Y"}` snippets in `README.md` and `docs/**/*.md`; then `mix format --check-formatted`, `mix compile --force --warnings-as-errors`, `mix test --exclude known_failing`; commit `chore: release <version>` | version already bumped / section already present |
| **2** | `git push origin main`, annotated tag `v<version>`, push the tag | tag exists locally / on origin |
| **3** | Poll the `nif_build` run for that tag every 30 s, 45 min cap. On failure, print the failing job's log tail and stop | the GitHub release already has the full asset set |
| **4** | `mix rustler_precompiled.download Hyperliquid.Signer --all --print`, `scripts/verify_nif_checksums.exs`, commit `chore: regenerate NIF checksums for v<version>`, push | checksum file already covers this version *and* verifies |
| **5** | Consumer smoke test: a throwaway mix project depends on this repo **by path**, with no `HYPERLIQUID_BUILD_NIF` and no `force_build` config, so `RustlerPrecompiled` must fetch the published artifact. Then `Hyperliquid.Signer.derive_address/1` | always runs (it is cheap and it is the thing that actually matters) |
| **6** | `mix hex.build` and `mix docs` | always runs |
| **7** | Source `$HEX_RELEASE_ENV`, `mix hex.publish --yes` | no key → READY TO PUBLISH banner, exit 0 |
| **8** | `gh release edit v<version> --notes-file` with that version's CHANGELOG section | always runs |

Every step detects its own state, so **re-running the same command is always
safe**. That is the intended way to resume after a failure: fix the cause, run
`scripts/release.sh <version>` again, and the completed steps report `skip:`.

Tuning knobs (environment): `RELEASE_WATCH_INTERVAL` (default `30`),
`RELEASE_WATCH_TIMEOUT` (default `2700`), `HEX_RELEASE_ENV`.

---

## The checksum bootstrap

`checksum-Elixir.Hyperliquid.Signer.exs` is generated *from* the release it
describes: `mix rustler_precompiled.download --all` downloads the assets that
the tag build just uploaded and hashes them. So on the first build of a new
version the committed file necessarily still describes the previous version,
and a strict gate on the tag build could never pass.

`nif_build.yml`'s `verify_release` job therefore checks whether the checksum
file has any `-v<version>-nif-` entries. If it does not, it logs a notice and
skips the checksum check for that run. Nothing is lost: `ci.yml` runs the same
`scripts/verify_nif_checksums.exs` on every push to `main` and every PR, so the
regenerated file still has to land and verify before anything is published —
which is exactly what step 4 does, on `main`, before step 7 publishes.

The verify script asserts three things: every entry is for the current
`mix.exs` `@version`; there is exactly one entry per (NIF version × target) in
the `nif_build.yml` matrix, with no gaps and no strays; and every checksum is a
well-formed sha256.

---

## Recovery

**A NIF matrix job failed.** The script prints the failing job's log tail and
stops. Fix the Rust or the workflow on `main` with a small commit, then wipe
the tag and its release and re-run:

```bash
gh release delete v0.5.0 --yes --cleanup-tag
git tag -d v0.5.0
git push origin :refs/tags/v0.5.0   # if --cleanup-tag did not get it
scripts/release.sh 0.5.0
```

**The build succeeded but the release is short of assets.** `fail-fast: false`
means a partial matrix still produces a release that looks complete. Step 3
counts the assets against the matrix and refuses to continue; step 4's verify
script would catch it too. Same recovery as above.

**Step 5 failed — the precompiled NIF would not load.** Do not publish. Either
an asset is missing for your platform's target/NIF-version pair, or the
checksum file disagrees with what is on the release. Re-run step 4's download,
and check that `base_url` in `lib/hyperliquid/signer.ex` points at
`releases/download/v<version>` (it is built from `@version`, so a stale
`@version` is the usual cause).

**`mix hex.publish` failed.** Nothing else needs redoing — the tag, the release
and the checksums are already correct. Fix the credential and re-run
`scripts/release.sh <version>`; steps 0–6 and 8 will all skip or repeat
harmlessly.

**Published the wrong thing.** Hex allows a revert within one hour of
publishing a new version of an existing package (24 hours for a brand-new
package):

```bash
mix hex.publish --revert 0.5.0
```

---

## Known-failing tests

`test/rpc/evm_test.exs` is tagged `@moduletag :known_failing` and is excluded
unconditionally by `test/test_helper.exs`. It predates the v0.2.0 DSL migration
and targets `Hyperliquid.Rpc.Evm`, a module that was split into
`Hyperliquid.Rpc.Eth`, `.Net`, `.Web3` and `.Custom`. Run it deliberately with:

```bash
HYPERLIQUID_TEST_KNOWN_FAILING=1 mix test test/rpc/evm_test.exs
```

Do not add tags to this list to get a release out. The point of the tag is that
the exclusion is visible in the test file, in the helper, and in the release
script's `mix test --exclude known_failing`.
