#!/usr/bin/env bash
#
# hex-auth-setup.sh — one-time hex.pm credential setup for scripts/release.sh.
#
#   scripts/hex-auth-setup.sh
#
# Writes HEX_API_KEY into ~/.config/hyperliquid-release/hex.env (mode 0600,
# directory 0700). scripts/release.sh sources that file in its publish step, so
# after this runs once, every future release publishes without a prompt.
#
# The key is never echoed, never passed on a command line, and never written
# anywhere except that file.
#
# Override the destination with HEX_RELEASE_ENV=/some/other/path.

set -euo pipefail

HEX_RELEASE_ENV="${HEX_RELEASE_ENV:-$HOME/.config/hyperliquid-release/hex.env}"
ENV_DIR="$(dirname "$HEX_RELEASE_ENV")"
KEY_NAME="hyperliquid-release-$(hostname -s 2>/dev/null || hostname)-$(date +%Y%m%d)"

if [ -t 1 ]; then
  B=$'\033[1m'; DIM=$'\033[2m'; GRN=$'\033[32m'; YLW=$'\033[33m'; RED=$'\033[31m'; RST=$'\033[0m'
else
  B=""; DIM=""; GRN=""; YLW=""; RED=""; RST=""
fi

say()  { printf '%s\n' "$*"; }
ok()   { printf '%s* %s%s\n' "$GRN" "$*" "$RST"; }
warn() { printf '%s! %s%s\n' "$YLW" "$*" "$RST"; }
die()  { printf '%serror: %s%s\n' "$RED" "$*" "$RST" >&2; exit 1; }

command -v mix >/dev/null 2>&1 || die "mix is not on PATH"

printf '\n%s=== hyperliquid release: hex.pm credential setup ===%s\n\n' "$B" "$RST"

if [ -f "$HEX_RELEASE_ENV" ] && grep -q '^HEX_API_KEY=' "$HEX_RELEASE_ENV"; then
  warn "$HEX_RELEASE_ENV already contains a HEX_API_KEY."
  printf 'Replace it? [y/N] '
  read -r replace
  case "$replace" in
    y | Y | yes | YES) ;;
    *) say "Keeping the existing key. Nothing changed."; exit 0 ;;
  esac
fi

# ---------------------------------------------------------------------------
# Where does the key come from?
# ---------------------------------------------------------------------------
#
# Hex 2.x removed the old `mix hex.user key generate` subcommand: `mix hex.user`
# now offers only `whoami`, `auth` and `deauth`, and `auth` stores a locally
# *encrypted* key in ~/.hex/hex.config that cannot be read back out as
# plaintext. So the dashboard is the supported way to get a pasteable key.
# We still probe for a key subcommand in case a newer Hex restores one.

HEX_VERSION="$(mix hex.info 2>/dev/null | sed -n 's/^Hex: *//p' | head -1 || true)"
say "Hex version: ${HEX_VERSION:-unknown}"

HAS_KEY_SUBCOMMAND=0
if mix help hex.user 2>/dev/null | grep -qE '^\s+\$ mix hex\.user key generate'; then
  HAS_KEY_SUBCOMMAND=1
fi

KEY=""

if [ "$HAS_KEY_SUBCOMMAND" -eq 1 ]; then
  say ""
  say "This Hex provides 'mix hex.user key generate'. Running it interactively;"
  say "type your hex.pm username, password and 2FA code at its prompts."
  say ""
  LOG="$(mktemp)"
  trap 'rm -f "$LOG"' EXIT
  if mix hex.user key generate --key-name "$KEY_NAME" 2>&1 | tee "$LOG"; then
    KEY="$(grep -oE '[A-Za-z0-9_-]{20,}' "$LOG" | tail -1 || true)"
  fi
  rm -f "$LOG"
  trap - EXIT
  [ -n "$KEY" ] || warn "could not capture a key from the command output; falling back to paste"
fi

if [ -z "$KEY" ]; then
  cat <<EOF

${B}Create an API key on hex.pm${RST}

  1. Open  ${B}https://hex.pm/dashboard/keys${RST}
  2. "Generate new key"
       Name:        ${KEY_NAME}
       Permissions: ${B}api  ->  write${RST}
  3. Copy the key. hex.pm shows it exactly once.

Then paste it below. Input is hidden and the value is never echoed.

EOF
  printf 'hex.pm API key: '
  stty -echo 2>/dev/null || true
  IFS= read -r KEY || true
  stty echo 2>/dev/null || true
  printf '\n'
fi

# Trim stray whitespace without ever printing the value.
KEY="$(printf '%s' "$KEY" | tr -d '[:space:]')"
[ -n "$KEY" ] || die "no key entered; nothing written"

# ---------------------------------------------------------------------------
# Verify before writing
# ---------------------------------------------------------------------------

say ""
say "Verifying the key with 'mix hex.user whoami'..."
WHOAMI="$(HEX_API_KEY="$KEY" mix hex.user whoami 2>&1 || true)"

case "$WHOAMI" in
  *[Uu]nauthorized* | *"API key"*[Ii]nvalid* | *"** (Mix)"*)
    printf '%s\n' "$WHOAMI" >&2
    die "hex.pm rejected that key. Check it has 'api: write' and was copied whole."
    ;;
esac

HEX_USER="$(printf '%s' "$WHOAMI" | tail -1 | tr -d '[:space:]')"
[ -n "$HEX_USER" ] || die "could not determine the hex.pm user from 'mix hex.user whoami'"
ok "authenticated to hex.pm as: $HEX_USER"

# ---------------------------------------------------------------------------
# Write it
# ---------------------------------------------------------------------------

mkdir -p "$ENV_DIR"
chmod 0700 "$ENV_DIR"

umask 077
cat > "$HEX_RELEASE_ENV" <<EOF
# hex.pm credentials for scripts/release.sh — generated $(date -u +%Y-%m-%dT%H:%M:%SZ)
# Key name on hex.pm: $KEY_NAME
# hex.pm user:        $HEX_USER
# Revoke at https://hex.pm/dashboard/keys
HEX_API_KEY=$KEY
EOF
chmod 0600 "$HEX_RELEASE_ENV"

unset KEY

ok "wrote $HEX_RELEASE_ENV (mode $(stat -c '%a' "$HEX_RELEASE_ENV"), dir mode $(stat -c '%a' "$ENV_DIR"))"

cat <<EOF

${GRN}${B}Done.${RST} Releases can now publish without a prompt:

    scripts/release.sh <version>

${DIM}Revoke the key any time at https://hex.pm/dashboard/keys, then delete
$HEX_RELEASE_ENV and re-run this script.${RST}

EOF
