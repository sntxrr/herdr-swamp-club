#!/usr/bin/env bash
# Install the Swamp Club theme into herdr's config.toml.
#
#   curl -fsSL https://raw.githubusercontent.com/sntxrr/herdr-swamp-club/main/install.sh | bash
#
# What it does, in order:
#   1. backs up config.toml next to itself (config.toml.bak-<timestamp>)
#   2. removes any existing [theme] / [theme.custom*] tables
#   3. appends swamp-club.toml
#   4. validates the result (if python3 >= 3.11 is available)
#   5. asks a running herdr server to reload its config
#
# Flags:  --dry-run   show the resulting diff, write nothing
#         --config P  use P instead of ~/.config/herdr/config.toml
set -euo pipefail

THEME_URL="https://raw.githubusercontent.com/sntxrr/herdr-swamp-club/main/swamp-club.toml"
DEFAULT_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/herdr/config.toml"
CONFIG="$DEFAULT_CONFIG"
DRY_RUN=0

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --config)  CONFIG="$2"; shift ;;
        -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
        *) echo "unknown flag: $1" >&2; exit 2 ;;
    esac
    shift
done

# Prefer a local copy when run from a clone; otherwise fetch from GitHub.
here=""
if here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"; then :; else here=""; fi
if [ -n "$here" ] && [ -f "$here/swamp-club.toml" ]; then
    theme="$(cat "$here/swamp-club.toml")"
else
    theme="$(curl -fsSL "$THEME_URL")"
fi
[ -n "$theme" ] || { echo "error: theme file is empty" >&2; exit 1; }

mkdir -p "$(dirname "$CONFIG")"
[ -f "$CONFIG" ] || : > "$CONFIG"

# Drop existing [theme] and [theme.custom*] tables; keep everything else.
stripped="$(awk '
    /^[[:space:]]*\[theme(\.[A-Za-z0-9_.]+)?\][[:space:]]*$/ { skip = 1; next }
    /^[[:space:]]*\[/                                          { skip = 0 }
    !skip
' "$CONFIG")"

new="$(printf '%s\n\n%s\n' "$stripped" "$theme")"

if [ "$DRY_RUN" = 1 ]; then
    echo "--- dry run: $CONFIG would become ---"
    diff -u "$CONFIG" <(printf '%s\n' "$new") || true
    exit 0
fi

backup="$CONFIG.bak-$(date +%Y%m%d-%H%M%S)"
cp "$CONFIG" "$backup"
printf '%s\n' "$new" > "$CONFIG"
echo "wrote  $CONFIG"
echo "backup $backup"

# Validate if we can (tomllib is stdlib from Python 3.11).
if command -v python3 >/dev/null 2>&1; then
    if ! python3 - "$CONFIG" <<'PY'
import sys
try:
    import tomllib
except ImportError:
    sys.exit(0)  # too old to validate; not an error
with open(sys.argv[1], "rb") as f:
    cfg = tomllib.load(f)
tokens = cfg.get("theme", {}).get("custom", {})
assert len(tokens) == 19, f"expected 19 theme.custom tokens, found {len(tokens)}"
print("valid  TOML parses, 19 theme tokens present")
PY
    then
        echo "error: result did not validate; restoring backup" >&2
        cp "$backup" "$CONFIG"
        exit 1
    fi
fi

# Only poke the running server when we edited the config it actually reads.
if [ "$CONFIG" != "$DEFAULT_CONFIG" ]; then
    echo "note   wrote a non-default path; herdr was not reloaded"
elif command -v herdr >/dev/null 2>&1 && herdr server reload-config >/dev/null 2>&1; then
    echo "reload herdr picked up the theme"
else
    echo "reload herdr is not running -- the theme applies on next launch"
fi
