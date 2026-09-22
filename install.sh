#!/usr/bin/env bash
# Install the Swamp Club theme into herdr's config.toml.
#
#   curl -fsSL https://raw.githubusercontent.com/sntxrr/herdr-swamp-club/main/install.sh | bash
#
# What it does, in order:
#   1. backs up config.toml next to itself (config.toml.bak-<timestamp>)
#   2. removes any existing [theme] / [theme.custom*] tables
#   3. appends swamp-club.toml
#   4. copies the notification sounds to sounds/swamp-club-*.mp3 beside the
#      config and points [ui.sound] done_path / request_path at them
#   5. validates the result (if python3 >= 3.11 is available)
#   6. asks a running herdr server to reload its config
#
# Flags:  --dry-run    show the resulting diff, write nothing
#         --config P   use P instead of ~/.config/herdr/config.toml
#         --no-sounds  theme only; leave [ui.sound] and sound files alone
set -euo pipefail

RAW_URL="https://raw.githubusercontent.com/sntxrr/herdr-swamp-club/main"
SOUNDS="done request"
DEFAULT_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/herdr/config.toml"
CONFIG="$DEFAULT_CONFIG"
DRY_RUN=0
WITH_SOUNDS=1

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --config)  CONFIG="$2"; shift ;;
        --no-sounds) WITH_SOUNDS=0 ;;
        -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
        *) echo "unknown flag: $1" >&2; exit 2 ;;
    esac
    shift
done

# Prefer a local copy when run from a clone; otherwise fetch from GitHub.
here=""
if here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"; then :; else here=""; fi
local=0
if [ -n "$here" ] && [ -f "$here/swamp-club.toml" ]; then
    local=1
    theme="$(cat "$here/swamp-club.toml")"
else
    theme="$(curl -fsSL "$RAW_URL/swamp-club.toml")"
fi
[ -n "$theme" ] || { echo "error: theme file is empty" >&2; exit 1; }

config_dir="$(dirname "$CONFIG")"
mkdir -p "$config_dir"
[ -f "$CONFIG" ] || : > "$CONFIG"

# Drop existing [theme] and [theme.custom*] tables; keep everything else.
stripped="$(awk '
    /^[[:space:]]*\[theme(\.[A-Za-z0-9_.]+)?\][[:space:]]*$/ { skip = 1; next }
    /^[[:space:]]*\[/                                          { skip = 0 }
    !skip
' "$CONFIG")"

# Point [ui.sound] at our files: replace any done_path / request_path in
# that table (keeping enabled, path and [ui.sound.agents]), or add the
# table if there is none. Paths are relative to the config's directory.
if [ "$WITH_SOUNDS" = 1 ]; then
    stripped="$(printf '%s\n' "$stripped" | awk '
        function emit() {
            print "done_path = \"sounds/swamp-club-done.mp3\"       # Swamp Club"
            print "request_path = \"sounds/swamp-club-request.mp3\" # Swamp Club"
        }
        /^[[:space:]]*\[ui\.sound\][[:space:]]*$/ { print; emit(); in_sound = 1; found = 1; next }
        /^[[:space:]]*\[/                           { in_sound = 0 }
        in_sound && /^[[:space:]]*(done_path|request_path)[[:space:]]*=/ { next }
        { print }
        END { if (!found) { print ""; print "[ui.sound]"; emit() } }
    ')"
fi

new="$(printf '%s\n\n%s\n' "$stripped" "$theme")"

if [ "$DRY_RUN" = 1 ]; then
    echo "--- dry run: $CONFIG would become ---"
    diff -u "$CONFIG" <(printf '%s\n' "$new") || true
    if [ "$WITH_SOUNDS" = 1 ]; then
        for s in $SOUNDS; do echo "sound  would write $config_dir/sounds/swamp-club-$s.mp3"; done
    fi
    exit 0
fi

# Fetch the sounds before touching the config, so a failed download
# leaves nothing half-installed.
if [ "$WITH_SOUNDS" = 1 ]; then
    mkdir -p "$config_dir/sounds"
    for s in $SOUNDS; do
        dest="$config_dir/sounds/swamp-club-$s.mp3"
        if [ "$local" = 1 ]; then
            cp "$here/sounds/$s.mp3" "$dest"
        else
            curl -fsSL "$RAW_URL/sounds/$s.mp3" -o "$dest"
        fi
        [ -s "$dest" ] || { echo "error: $dest is empty" >&2; exit 1; }
        echo "sound  $dest"
    done
fi

backup="$CONFIG.bak-$(date +%Y%m%d-%H%M%S)"
cp "$CONFIG" "$backup"
printf '%s\n' "$new" > "$CONFIG"
echo "wrote  $CONFIG"
echo "backup $backup"

# Validate if we can (tomllib is stdlib from Python 3.11).
if command -v python3 >/dev/null 2>&1; then
    if ! python3 - "$CONFIG" "$WITH_SOUNDS" <<'PY'
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
if sys.argv[2] == "1":
    import os
    sound = cfg.get("ui", {}).get("sound", {})
    for key in ("done_path", "request_path"):
        path = os.path.join(os.path.dirname(sys.argv[1]), sound[key])
        assert os.path.getsize(path) > 0, f"{key} -> {path} is missing or empty"
    print("valid  [ui.sound] done_path / request_path point at real files")
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
