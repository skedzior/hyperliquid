#!/usr/bin/env bash
#
# release.sh — cut a release of the `hyperliquid` Hex package.
#
#   scripts/release.sh 0.5.0            # do it
#   scripts/release.sh 0.5.0 --dry-run  # everything up to the first push
#
# The script is IDEMPOTENT and RE-RUNNABLE. Every step detects whether it has
# already been done (tag present? release assets complete? checksum file
# already for this version?) and skips itself rather than failing. If a step
# blows up, fix the cause and run exactly the same command again.
#
# See docs/releasing.md for the runbook and recovery instructions.

set -euo pipefail

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------

VERSION=""
DRY_RUN=0

usage() {
  cat >&2 <<'EOF'
usage: scripts/release.sh <version> [--dry-run]

  <version>   semver, no leading "v" (e.g. 0.5.0)
  --dry-run   run preflight, the version bump and the full check suite, but
              make no commit, no push, no tag and no publish. The edits are
              left in the working tree for inspection.
EOF
  exit 2
}

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h | --help) usage ;;
    -*) echo "unknown flag: $arg" >&2; usage ;;
    *)
      [ -n "$VERSION" ] && usage
      VERSION="$arg"
      ;;
  esac
done

[ -n "$VERSION" ] || usage

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
  echo "error: '$VERSION' is not a semver version (expected e.g. 0.5.0)" >&2
  exit 2
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

TAG="v$VERSION"
MINOR="${VERSION%.*}"                       # 0.5.0 -> 0.5
CHECKSUM_FILE="checksum-Elixir.Hyperliquid.Signer.exs"
NIF_WORKFLOW=".github/workflows/nif_build.yml"
WATCH_INTERVAL="${RELEASE_WATCH_INTERVAL:-30}"
WATCH_TIMEOUT="${RELEASE_WATCH_TIMEOUT:-2700}" # 45 minutes
HEX_RELEASE_ENV="${HEX_RELEASE_ENV:-$HOME/.config/hyperliquid-release/hex.env}"

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

if [ -t 1 ]; then
  B=$'\033[1m'; DIM=$'\033[2m'; GRN=$'\033[32m'; YLW=$'\033[33m'; RED=$'\033[31m'; RST=$'\033[0m'
else
  B=""; DIM=""; GRN=""; YLW=""; RED=""; RST=""
fi

step()  { printf '\n%s==> [%s] %s%s\n' "$B" "$1" "$2" "$RST"; }
info()  { printf '    %s\n' "$*"; }
skip()  { printf '    %sskip: %s%s\n' "$DIM" "$*" "$RST"; }
ok()    { printf '    %s* %s%s\n' "$GRN" "$*" "$RST"; }
warn()  { printf '    %s! %s%s\n' "$YLW" "$*" "$RST"; }
die()   { printf '\n%serror: %s%s\n' "$RED" "$*" "$RST" >&2; exit 1; }

run() {
  printf '    %s$ %s%s\n' "$DIM" "$*" "$RST"
  "$@"
}

# `true` when the step must not mutate anything outside the working tree.
readonly_mode() { [ "$DRY_RUN" -eq 1 ]; }

# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

mix_version() { sed -n 's/^ *@version "\([^"]*\)"/\1/p' mix.exs | head -1; }

# Number of (nif version x target) artifacts the nif_build matrix produces.
expected_artifact_count() {
  local nifs targets
  nifs=$(sed -n 's/.*nif: \[\(.*\)\].*/\1/p' "$NIF_WORKFLOW" | head -1 | tr ',' '\n' | grep -c .)
  targets=$(grep -c 'target: [a-z0-9_-]*,' "$NIF_WORKFLOW" || true)
  echo $((nifs * targets))
}

checksum_entries_for_version() {
  [ -f "$CHECKSUM_FILE" ] || { echo 0; return; }
  grep -c -- "-v${VERSION}-nif-" "$CHECKSUM_FILE" || true
}

tag_exists_locally()  { git rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1; }
tag_exists_remotely() { [ -n "$(git ls-remote --tags origin "refs/tags/$TAG" 2>/dev/null)" ]; }

# ---------------------------------------------------------------------------
# Step 0 — preflight
# ---------------------------------------------------------------------------

step 0 "Preflight"

for bin in git gh elixir mix cargo rustc; do
  command -v "$bin" >/dev/null 2>&1 || die "$bin is not on PATH"
done
ok "toolchain: $(elixir --version | tail -1), $(rustc --version)"

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[ "$BRANCH" = "main" ] || die "must release from 'main', currently on '$BRANCH'"

if [ -n "$(git status --porcelain)" ]; then
  if readonly_mode && [ -z "$(git status --porcelain -- ':!mix.exs' ':!CHANGELOG.md' ':!README.md' ':!docs')" ]; then
    warn "working tree has release edits from a previous --dry-run; continuing"
  else
    git status --short >&2
    die "working tree is not clean"
  fi
fi

run git fetch --prune --tags origin

LOCAL_MAIN="$(git rev-parse main)"
REMOTE_MAIN="$(git rev-parse origin/main)"
if [ "$LOCAL_MAIN" != "$REMOTE_MAIN" ]; then
  die "main ($LOCAL_MAIN) and origin/main ($REMOTE_MAIN) have diverged; reconcile first"
fi
ok "main == origin/main ($(git rev-parse --short main))"

gh auth status >/dev/null 2>&1 || die "gh is not authenticated (run: gh auth login)"
ok "gh authenticated as $(gh api user --jq .login)"

EXPECTED_ARTIFACTS="$(expected_artifact_count)"
[ "$EXPECTED_ARTIFACTS" -gt 0 ] || die "could not read the NIF matrix from $NIF_WORKFLOW"
ok "nif_build matrix expects $EXPECTED_ARTIFACTS artifacts"

if readonly_mode; then warn "DRY RUN: nothing will be committed, pushed, tagged or published"; fi

# ---------------------------------------------------------------------------
# Step 1 — version bump, docs, checks, commit
# ---------------------------------------------------------------------------

step 1 "Bump to $VERSION and run the checks"

CURRENT="$(mix_version)"
if [ "$CURRENT" = "$VERSION" ]; then
  skip "mix.exs @version is already $VERSION"
else
  info "mix.exs @version: $CURRENT -> $VERSION"
  perl -0pi -e "s/\@version \"\Q$CURRENT\E\"/\@version \"$VERSION\"/" mix.exs
  [ "$(mix_version)" = "$VERSION" ] || die "failed to rewrite @version in mix.exs"
fi

# CHANGELOG: `## Unreleased` -> `## <version> (<date>)`.
# The repo has no "keep an empty Unreleased on top" convention, so none is added.
if grep -q "^## ${VERSION} " CHANGELOG.md || grep -q "^## ${VERSION}$" CHANGELOG.md; then
  skip "CHANGELOG already has a ## $VERSION section"
elif grep -q '^## Unreleased$' CHANGELOG.md; then
  TODAY="$(date +%Y-%m-%d)"
  info "CHANGELOG: ## Unreleased -> ## $VERSION ($TODAY)"
  perl -0pi -e "s/^## Unreleased\$/## $VERSION ($TODAY)/m" CHANGELOG.md
else
  die "CHANGELOG.md has neither '## Unreleased' nor a '## $VERSION' section"
fi

# Dependency snippets in the README and the docs tree.
SNIPPET_FILES=$(git ls-files 'README.md' 'docs/**/*.md' 'docs/*.md')
CHANGED_SNIPPETS=0
for f in $SNIPPET_FILES; do
  if grep -q ':hyperliquid, "~> [0-9]' "$f"; then
    before="$(md5sum "$f" | cut -d' ' -f1)"
    perl -pi -e "s/(:hyperliquid, \"~> )[0-9]+\.[0-9]+(\.[0-9]+)?(\")/\${1}$MINOR\${3}/g" "$f"
    after="$(md5sum "$f" | cut -d' ' -f1)"
    if [ "$before" != "$after" ]; then
      info "dep snippet -> ~> $MINOR in $f"
      CHANGED_SNIPPETS=$((CHANGED_SNIPPETS + 1))
    fi
  fi
done
if [ "$CHANGED_SNIPPETS" -eq 0 ]; then skip "dep snippets already at ~> $MINOR"; fi

info "running the release checks (this compiles the NIF from source)"
run mix format --check-formatted
run mix compile --force --warnings-as-errors
# :known_failing is already excluded unconditionally by test/test_helper.exs;
# naming it here keeps the intent visible at the call site.
run mix test --exclude known_failing

if readonly_mode; then
  warn "dry run: not committing. Inspect with 'git diff', revert with 'git checkout -- .'"
elif [ -z "$(git status --porcelain)" ]; then
  skip "nothing to commit — release commit already exists"
else
  run git add -A
  run git commit -m "chore: release $VERSION"
  ok "committed: $(git log -1 --oneline)"
fi

if readonly_mode; then
  step "-" "Dry run complete"
  info "stopping before push / tag / publish, as requested."
  exit 0
fi

# ---------------------------------------------------------------------------
# Step 2 — push main, tag, push tag
# ---------------------------------------------------------------------------

step 2 "Push main and tag $TAG"

if [ "$(git rev-parse main)" = "$(git rev-parse origin/main 2>/dev/null || echo none)" ]; then
  skip "origin/main already up to date"
else
  run git push origin main
fi

if tag_exists_locally; then
  skip "local tag $TAG already exists"
else
  run git tag -a "$TAG" -m "hyperliquid $VERSION"
fi

if tag_exists_remotely; then
  skip "origin already has $TAG"
else
  run git push origin "refs/tags/$TAG"
fi
ok "tag $TAG -> $(git rev-parse --short "$TAG^{commit}")"

# ---------------------------------------------------------------------------
# Step 3 — wait for the precompiled-NIF build
# ---------------------------------------------------------------------------

step 3 "Build precompiled NIFs (GitHub Actions)"

# Match on the tag's COMMIT as well as its name. A re-run after
# `gh release delete --cleanup-tag` recreates the tag on a new commit, and the
# runs from the deleted attempts are still listed under the same headBranch —
# selecting by name alone would latch onto a stale, already-failed run forever.
nif_run_id() {
  local sha
  sha="$(git rev-parse "$TAG^{commit}")"
  gh run list --workflow nif_build.yml --limit 30 \
    --json databaseId,headBranch,headSha,status,conclusion \
    --jq "[.[] | select(.headBranch == \"$TAG\" and .headSha == \"$sha\")] | first | .databaseId" 2>/dev/null
}

nif_run_field() {
  gh run view "$1" --json status,conclusion --jq ".$2" 2>/dev/null
}

release_asset_count() {
  gh release view "$TAG" --json assets --jq '[.assets[] | select(.name | endswith(".tar.gz"))] | length' 2>/dev/null || echo 0
}

ASSETS="$(release_asset_count)"
if [ "${ASSETS:-0}" -ge "$EXPECTED_ARTIFACTS" ]; then
  skip "release $TAG already has $ASSETS/$EXPECTED_ARTIFACTS NIF assets"
else
  info "waiting for the nif_build run for $TAG (poll ${WATCH_INTERVAL}s, cap $((WATCH_TIMEOUT / 60))m)"
  RUN_ID=""
  ELAPSED=0
  while [ "$ELAPSED" -lt "$WATCH_TIMEOUT" ]; do
    if [ -z "$RUN_ID" ] || [ "$RUN_ID" = "null" ]; then
      RUN_ID="$(nif_run_id || true)"
    fi
    if [ -n "$RUN_ID" ] && [ "$RUN_ID" != "null" ]; then
      STATUS="$(nif_run_field "$RUN_ID" status)"
      CONCL="$(nif_run_field "$RUN_ID" conclusion)"
      if [ "$STATUS" = "completed" ]; then
        if [ "$CONCL" = "success" ]; then
          ok "nif_build run $RUN_ID succeeded"
          break
        fi
        printf '\n%s--- failing job logs (tail) ---%s\n' "$RED" "$RST" >&2
        gh run view "$RUN_ID" --log-failed 2>&1 | tail -80 >&2 || true
        printf '%s-------------------------------%s\n' "$RED" "$RST" >&2
        die "nif_build run $RUN_ID finished '$CONCL'. Fix it, then: gh release delete $TAG --yes --cleanup-tag && git tag -d $TAG && re-run this script."
      fi
      info "run $RUN_ID: $STATUS (${ELAPSED}s elapsed)"
    else
      info "no nif_build run for $TAG yet (${ELAPSED}s elapsed)"
    fi
    sleep "$WATCH_INTERVAL"
    ELAPSED=$((ELAPSED + WATCH_INTERVAL))
  done
  [ "$ELAPSED" -lt "$WATCH_TIMEOUT" ] || die "timed out after $((WATCH_TIMEOUT / 60))m waiting for the nif_build run for $TAG"

  ASSETS="$(release_asset_count)"
  [ "${ASSETS:-0}" -ge "$EXPECTED_ARTIFACTS" ] ||
    die "release $TAG has $ASSETS NIF assets, expected $EXPECTED_ARTIFACTS"
fi
ok "GitHub release $TAG carries $ASSETS NIF assets"

# ---------------------------------------------------------------------------
# Step 4 — regenerate and commit the NIF checksum file
# ---------------------------------------------------------------------------

step 4 "NIF checksums"

HAVE="$(checksum_entries_for_version)"
if [ "$HAVE" -ge "$EXPECTED_ARTIFACTS" ] && mix run --no-start scripts/verify_nif_checksums.exs >/dev/null 2>&1; then
  skip "$CHECKSUM_FILE already covers $TAG ($HAVE entries) and verifies"
else
  run env MIX_ENV=dev mix rustler_precompiled.download Hyperliquid.Signer --all --print
fi

run mix run --no-start scripts/verify_nif_checksums.exs
CHECKSUM_COUNT="$(checksum_entries_for_version)"
ok "$CHECKSUM_COUNT checksum entries for $TAG"

if [ -n "$(git status --porcelain -- "$CHECKSUM_FILE")" ]; then
  run git add "$CHECKSUM_FILE"
  run git commit -m "chore: regenerate NIF checksums for $TAG"
  run git push origin main
  ok "committed and pushed: $(git log -1 --oneline)"
else
  skip "$CHECKSUM_FILE unchanged — already committed"
  if [ "$(git rev-parse main)" != "$(git rev-parse origin/main)" ]; then
    run git push origin main
  fi
fi

# ---------------------------------------------------------------------------
# Step 5 — prove the PRECOMPILED NIF loads for a consumer
# ---------------------------------------------------------------------------

step 5 "Consumer smoke test (precompiled NIF, no Rust toolchain path)"

SMOKE_DIR="$(mktemp -d)"
cleanup_smoke() { rm -rf "$SMOKE_DIR"; }
trap cleanup_smoke EXIT

(
  # Critically: no HYPERLIQUID_BUILD_NIF, no force_build config. A path dep does
  # not inherit the dependency's own config/, so RustlerPrecompiled must fetch
  # the artifact from the GitHub release we just made.
  unset HYPERLIQUID_BUILD_NIF RUSTLER_PRECOMPILED_FORCE_BUILD_ALL
  cd "$SMOKE_DIR"
  mix new hl_smoke --app hl_smoke >/dev/null
  cd hl_smoke
  cat > mix.exs <<EOF
defmodule HlSmoke.MixProject do
  use Mix.Project

  def project do
    [app: :hl_smoke, version: "0.0.1", elixir: "~> 1.16", deps: deps()]
  end

  def application, do: [extra_applications: [:logger]]

  defp deps do
    [{:hyperliquid, path: "$REPO_ROOT"}]
  end
end
EOF
  mkdir -p config
  printf 'import Config\n' > config/config.exs
  mix deps.get >/dev/null
  mix compile
  mix run --no-start -e '
    key = "0x" <> String.duplicate("11", 32)
    addr = Hyperliquid.Signer.derive_address(key)
    unless is_binary(addr) and String.starts_with?(addr, "0x") and byte_size(addr) == 42 do
      IO.puts(:stderr, "unexpected derive_address result: #{inspect(addr)}")
      System.halt(1)
    end
    IO.puts("precompiled NIF OK — derive_address/1 -> #{addr}")
  '
) || die "the precompiled NIF did not load for a plain consumer"
ok "a consumer with no Rust toolchain can load the precompiled NIF"

cleanup_smoke
trap - EXIT

# ---------------------------------------------------------------------------
# Step 6 — build the Hex tarball and the docs
# ---------------------------------------------------------------------------

step 6 "Package and docs"

run mix hex.build
run env MIX_ENV=dev mix docs
TARBALL="hyperliquid-$VERSION.tar"
if [ -f "$TARBALL" ]; then
  ok "$TARBALL — $(du -h "$TARBALL" | cut -f1), $(tar tf "$TARBALL" | wc -l) entries"
  info "contents:"
  tar tf "$TARBALL" | sed 's/^/      /'
else
  warn "expected $TARBALL in the repo root but it is not there"
fi

# ---------------------------------------------------------------------------
# Step 7 — publish to hex.pm
# ---------------------------------------------------------------------------

step 7 "Publish to hex.pm"

if [ -f "$HEX_RELEASE_ENV" ]; then
  info "sourcing $HEX_RELEASE_ENV"
  # shellcheck disable=SC1090
  set -a; . "$HEX_RELEASE_ENV"; set +a
else
  info "no $HEX_RELEASE_ENV — skipping"
fi

if [ -n "${HEX_API_KEY:-}" ]; then
  info "HEX_API_KEY present; publishing non-interactively"
  run mix hex.publish --yes
  ok "published hyperliquid $VERSION to hex.pm"
else
  cat <<EOF

${YLW}${B}=============================================================
  READY TO PUBLISH — hyperliquid $VERSION
=============================================================${RST}

Everything is built, tagged and verified. The only thing missing is a
hex.pm API key, so nothing was published.

  1. One-time setup (writes $HEX_RELEASE_ENV, mode 0600):

       scripts/hex-auth-setup.sh

  2. Then publish — re-running the release script is safe, every earlier
     step detects it is already done and skips:

       scripts/release.sh $VERSION

     or publish directly:

       set -a; . "$HEX_RELEASE_ENV"; set +a
       mix hex.publish --yes

EOF
fi

# ---------------------------------------------------------------------------
# Step 8 — GitHub release notes from the CHANGELOG
# ---------------------------------------------------------------------------

step 8 "GitHub release notes"

NOTES_FILE="$(mktemp)"
awk -v ver="$VERSION" '
  $0 ~ "^## " ver "([ (]|$)" { inside = 1; next }
  inside && /^## / { exit }
  inside { print }
' CHANGELOG.md > "$NOTES_FILE"

if [ -s "$NOTES_FILE" ]; then
  run gh release edit "$TAG" --notes-file "$NOTES_FILE"
  ok "release notes set from the CHANGELOG ## $VERSION section ($(wc -l < "$NOTES_FILE") lines)"
else
  warn "no CHANGELOG section found for $VERSION; leaving the release notes alone"
fi
rm -f "$NOTES_FILE"

RELEASE_URL="$(gh release view "$TAG" --json url --jq .url 2>/dev/null || echo '')"

step "-" "Done"
ok "version:       $VERSION"
ok "tag:           $TAG"
ok "NIF assets:    $ASSETS"
ok "checksums:     $CHECKSUM_COUNT entries"
if [ -n "$RELEASE_URL" ]; then ok "release:       $RELEASE_URL"; fi
if [ -n "${HEX_API_KEY:-}" ]; then
  ok "hex.pm:        https://hex.pm/packages/hyperliquid/$VERSION"
else
  warn "hex.pm:        NOT PUBLISHED — see the READY TO PUBLISH banner above"
fi
