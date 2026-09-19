# Swamp Club — a theme for [herdr](https://herdr.dev)

Bioluminescent swamp at night: pitch-black water, a neon-green glow, and
magenta and cyan will-o'-the-wisps for everything else.

![herdr running the Swamp Club theme](screenshots/herdr.png)

There is a matching terminal theme so the panes and the sidebar read as one
surface: [ghostty-swamp-club](https://github.com/sntxrr/ghostty-swamp-club).

## Install

### One line

```sh
curl -fsSL https://raw.githubusercontent.com/sntxrr/herdr-swamp-club/main/install.sh | bash
```

That backs up `~/.config/herdr/config.toml` next to itself, replaces the
`[theme]` section with Swamp Club, validates the result, and reloads a running
herdr. Nothing else in your config is touched. Add `--dry-run` to see the diff
first:

```sh
curl -fsSL https://raw.githubusercontent.com/sntxrr/herdr-swamp-club/main/install.sh | bash -s -- --dry-run
```

### By hand

1. Open `~/.config/herdr/config.toml`.
2. Delete your existing `[theme]` and `[theme.custom]` sections, if any.
   TOML allows each table once, so the new one can't simply be appended.
3. Paste in the contents of [`swamp-club.toml`](swamp-club.toml).
4. Reload:

   ```sh
   herdr server reload-config
   ```

   or press `prefix + shift + r` inside herdr.

## Uninstall

Restore the backup the installer wrote (or just delete the two `[theme]`
tables) and reload:

```sh
cp ~/.config/herdr/config.toml.bak-<timestamp> ~/.config/herdr/config.toml
herdr server reload-config
```

## Palette

![Swamp Club palette](screenshots/palette.svg)

| role | token | value |
|---|---|---|
| black water → moss | `panel_bg` `sidebar_bg` `surface_dim` `surface0` `surface1` | `#080a08` → `#1a261a` |
| focused row / navigate cursor | `active_row_bg` `selection_bg` | `#14241a` `#1c3322` |
| borders, dim glyphs | `overlay0` `overlay1` | `#3d5240` `#5f7a62` |
| text / muted | `text` `subtext0` | `#d6ead0` `#8fae8c` |
| the glow | `accent` | `#39ff14` |
| done / attention / blocked | `green` `yellow` `red` | `#4ade80` `#fde047` `#ff003c` |
| wisps | `teal` `mauve` `blue` `peach` | `#22d3ee` `#e879f9` `#60a5fa` `#fb923c` |

`accent` and `green` are deliberately different: the neon marks focus and
highlights, while agent *done* states use the calmer green so a sidebar full
of finished agents doesn't glow.

## Tweaks

Every value lives under `[theme.custom]` and can be changed on its own.
Three that people tend to want:

- **Too bright?** Swap `accent` for `#4ade80` and `green` for `#39ff14`.
- **Panes should follow the terminal's background** rather than the theme's
  black: `panel_bg = "reset"`.
- **Dracula/Nord/… as the base** instead of catppuccin: change `name`.
  Every token is overridden, so the base only matters for anything herdr adds
  in a future version.

## Notes

- Requires herdr 0.9 or newer (`[theme.custom]` with per-token overrides).
- The palette is borrowed, with affection, from [swamp.club](https://swamp.club).
  This project is not affiliated with Swamp Club, Inc.
- MIT licensed.
