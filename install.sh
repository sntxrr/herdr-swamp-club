#!/usr/bin/env bash
# Install the Swamp Club theme into herdr's config.toml.
#
#   curl -fsSL https://raw.githubusercontent.com/sntxrr/herdr-swamp-club/main/install.sh | bash
#
# What it does, in order:
#   1. backs up config.toml next to itself (config.toml.bak-<timestamp>)
#   2. merges swamp-club.toml into the existing [theme] / [theme.custom] tables:
#      the tokens it defines are set, everything else in those tables (extra
#      tokens, comments, other tables) is left alone
#   3. copies the notification sounds to sounds/swamp-club-*.mp3 beside the
#      config and points [ui.sound] done_path / request_path at them
#   4. validates the result (if python3 >= 3.11 is available)
#   5. asks a running herdr server to reload its config
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
        -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
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

theme_file="$(mktemp)"
trap 'rm -f "$theme_file"' EXIT
printf '%s\n' "$theme" > "$theme_file"

# Merge the theme into the config: every token swamp-club.toml defines is set
# in place, any other token the user has in [theme.custom] survives, as do
# unrelated tables and comments. The theme file itself is the first input, so
# the merge knows exactly which keys it is allowed to touch.
merged="$(awk '
    function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
    # Blank lines are held back so a table can still grow (missing keys) before
    # the gap that ends it.
    function put(s) { print s; emitted = 1; lastline = s }
    function emit(s) {
        if (trim(s) == "") { pendblanks++; return }
        while (pendblanks > 0) { put(""); pendblanks-- }
        put(s)
    }
    function gap() {
        if (!emitted || pendblanks > 0) return
        # the marker comment already separates the block it belongs to
        if (lastline ~ /^# Swamp Club -- a herdr theme/) return
        pendblanks = 1
    }
    function key_of(s,   i) {
        i = index(s, "="); if (i == 0) return ""
        return trim(substr(s, 1, i - 1))
    }
    function marker() {
        if (marker_done) return
        gap()
        emit("# Swamp Club -- a herdr theme (https://github.com/sntxrr/herdr-swamp-club)")
        marker_done = 1
    }
    function flush_custom(   j, k, held) {
        held = pendblanks; pendblanks = 0
        for (j = 1; j <= nkeys; j++) {
            k = order[j]
            if (k in seen) continue
            put(sprintf("%-*s = %s", maxkey, k, cval[k]))
            seen[k] = 1
        }
        pendblanks = held
    }
    function flush_theme(   held) {
        held = pendblanks; pendblanks = 0
        if (!("name" in tseen)) { put("name = " tname); tseen["name"] = 1 }
        if (!("auto_switch" in tseen)) { put("auto_switch = " tauto); tseen["auto_switch"] = 1 }
        pendblanks = held
    }
    # pass 1: the theme file. Comments are whole lines there (the values
    # themselves contain "#rrggbb"), so only leading-# lines are skipped.
    FNR == NR {
        line = trim($0)
        if (line == "" || line ~ /^#/) next
        if (line ~ /^\[/) { sec = line; gsub(/[][[:space:]]/, "", sec); next }
        if (index(line, "=") == 0) next
        i = index(line, "=")
        k = trim(substr(line, 1, i - 1))
        v = trim(substr(line, i + 1))
        if (sec == "theme") {
            if (k == "name") tname = v
            else if (k == "auto_switch") tauto = v
            next
        }
        if (sec == "theme.custom") {
            if (!(k in cval)) order[++nkeys] = k
            cval[k] = v
            if (length(k) > maxkey) maxkey = length(k)
        }
        next
    }
    # pass 2: the config. `sec` still holds the last section of the theme file.
    NR != FNR && !pass2 { pass2 = 1; sec = "" }
    {
        line = $0
        # the marker a previous run left behind; drop it so re-runs stay clean
        if (line ~ /^# Swamp Club -- a herdr theme/) next
        if (line ~ /^# https:\/\/github\.com\/sntxrr\/herdr-swamp-club[[:space:]]*$/) next

        if (line ~ /^[[:space:]]*\[/) {
            if (sec == "theme") flush_theme()
            else if (sec == "theme.custom") flush_custom()
            sec = line
            sub(/^[[:space:]]*\[/, "", sec)
            sub(/\][[:space:]]*$/, "", sec)
            gsub(/[[:space:]]/, "", sec)
            if (sec == "theme" || sec == "theme.custom") {
                marker()
                if (sec == "theme") seen_theme = 1
                else seen_custom = 1
            }
            emit(line)
            next
        }
        if (sec == "theme") {
            k = key_of(line)
            if (k == "name" && tname != "") { emit("name = " tname); tseen["name"] = 1; next }
            if (k == "auto_switch" && tauto != "") { emit("auto_switch = " tauto); tseen["auto_switch"] = 1; next }
            emit(line); next
        }
        if (sec == "theme.custom") {
            k = key_of(line)
            if (k != "" && (k in cval)) {
                emit(sprintf("%-*s = %s", maxkey, k, cval[k]))
                seen[k] = 1
                next
            }
            emit(line); next
        }
        emit(line)
    }
    END {
        if (!pass2) { pass2 = 1; sec = "" }   # empty config: no record ran
        if (sec == "theme") flush_theme()
        else if (sec == "theme.custom") flush_custom()
        if (!seen_theme) {
            marker()
            gap()
            emit("[theme]")
            flush_theme()
        }
        if (!seen_custom) {
            marker()
            gap()
            emit("[theme.custom]")
            flush_custom()
        }
    }
' "$theme_file" "$CONFIG")"

# Point [ui.sound] at our files: replace any done_path / request_path in
# that table (keeping enabled, path and [ui.sound.agents]), or add the
# table if there is none. Paths are relative to the config's directory.
if [ "$WITH_SOUNDS" = 1 ]; then
    merged="$(printf '%s\n' "$merged" | awk '
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

new="$merged"

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

# Validate if we can (tomllib is stdlib from Python 3.11). Every token the
# theme defines must be in place; tokens herdr knows about but the theme does
# not are allowed to stay as the user had them.
if command -v python3 >/dev/null 2>&1; then
    if ! python3 - "$CONFIG" "$WITH_SOUNDS" "$theme" <<'PY'
import sys

try:
    import tomllib
except ImportError:
    sys.exit(0)  # too old to validate; not an error

with open(sys.argv[1], "rb") as f:
    cfg = tomllib.load(f)
want = tomllib.loads(sys.argv[3])["theme"]
got = cfg.get("theme", {}).get("custom", {})
missing = {k: v for k, v in want["custom"].items() if got.get(k) != v}
assert not missing, f"theme tokens not applied: {missing}"
assert cfg["theme"]["name"] == want["name"], f"theme.name is {cfg['theme']['name']!r}"
extra = sorted(set(got) - set(want["custom"]))
print(f"valid  TOML parses, {len(want['custom'])} Swamp Club tokens applied"
      + (f", {len(extra)} kept from the previous theme: {', '.join(extra)}" if extra else ""))
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
