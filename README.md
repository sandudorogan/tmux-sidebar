# tmux-sidebar

[![Tests](https://github.com/sandudorogan/tmux-sidebar/actions/workflows/test.yml/badge.svg)](https://github.com/sandudorogan/tmux-sidebar/actions/workflows/test.yml)

A tmux plugin that gives you a persistent, interactive session tree on the left
side of every window — with live agent status badges for `claude`, `codex`, and
`opencode`.

```
  ┌─ Sidebar ────────────┬────────────────────────────────┐
  │                      │                                │
  │   ├─ work            │  $ claude                      │
  │   │  └─ zsh          │                                │
  │   │     ├─ claude    │  Working on your request...    │
  │   │     └─ zsh       │                                │
  │   └─ env             │                                │
  │      ├─ claude       │                                │
  │      │  ├─ claude    │                                │
  │      │  ├─ lazygit   │                                │
  │ ▶    │  ├─ claude ⏳│                                │
  │      │  └─ yazi      │                                │
  │      └─ yazi         │                                │
  │         ├─ yazi      │                                │
  │         └─ yazi      │                                │
  │                      │                                │
  └──────────────────────┴────────────────────────────────┘
```

![tmux-sidebar showcase](images/showcase.gif)

## Features

**Interactive tree** — sessions, windows, and panes rendered as a navigable
Unicode tree. Select any pane and jump to it with `Enter`.

**Agent badges** — per-pane status indicators update in real time:

| Badge | Status      | Meaning                        |
| :---: | ----------- | ------------------------------ |
| `⏳`  | running     | Agent is working               |
| `❓`  | needs-input | Waiting for permission / input |
| `✅`  | done        | Finished                       |
| `❌`  | error       | Something went wrong           |

Badges for `done` and `needs-input` clear automatically when you focus the pane.

**Auto-mirroring** — the sidebar follows you across windows. Open it once and it
stays visible as you move around.

**Session management** — add windows, add sessions, rename sessions, rename
windows, and close panes directly from the sidebar without leaving context.

## Install

### With TPM

```tmux
set -g @plugin 'sandudorogan/tmux-sidebar'
```

Reload tmux and press `prefix + I` to install.

### Manual

```bash
git clone https://github.com/sandudorogan/tmux-sidebar \
  ~/.tmux/plugins/tmux-sidebar
```

Source it in your tmux config:

```tmux
source-file ~/.tmux/plugins/tmux-sidebar/sidebar.tmux
```

Then `tmux source-file ~/.tmux.conf`.

## Usage

### Toggle

`<prefix> t` opens or closes the sidebar.

### Focus

`<prefix> T` toggles focus between the sidebar and your main pane:

- **In sidebar** — returns to the pane you were in before
- **Sidebar open** — moves focus into the sidebar
- **Sidebar closed** — opens the sidebar and focuses it

### Navigation (inside the sidebar)

| Key          | Action                           |
| ------------ | -------------------------------- |
| `j` / `Down` | Move selection down              |
| `k` / `Up`   | Move selection up                |
| `gg`         | Jump to the top of the list      |
| `G`          | Jump to the bottom of the list   |
| `Enter`      | Jump to the selected pane        |
| `aw`         | Add a window (prompts for name)  |
| `as`         | Add a session (prompts for name) |
| `rw`         | Rename the selected window       |
| `rs`         | Rename the selected session      |
| `x`          | Close the selected pane          |
| `p`          | Toggle hide-panes mode           |
| `q`          | Close the sidebar                |
| `Ctrl+l`     | Return focus to the main pane    |

New windows and sessions are inserted relative to the currently selected row.
Closing the last pane in a window removes the window; the last window removes
the session.

## Configuration

All options are set with `set -g` in your tmux config.

### Sidebar width

```tmux
set -g @tmux_sidebar_width 30      # default: 25
```

The env var `TMUX_SIDEBAR_WIDTH` takes precedence if set.

### Focus on open

By default, toggling the sidebar moves focus into it. Disable this to keep
focus in your main pane:

```tmux
set -g @tmux_sidebar_focus_on_open 0   # default: 1
```

### Session order

Control the order sessions appear in the tree:

```tmux
set -g @tmux_sidebar_session_order "work,ops,scratch"
```

Sessions not in this list appear after the listed ones in their default order.
Adding a session via the sidebar (`as`) automatically inserts it into this
list, and renaming a session via `rs` updates the existing entry in place.

### Custom shortcuts

Override the default sidebar shortcuts:

```tmux
set -g @tmux_sidebar_add_window_shortcut  zw   # default: aw
set -g @tmux_sidebar_add_session_shortcut zs   # default: as
set -g @tmux_sidebar_go_top_shortcut      tt   # default: gg
set -g @tmux_sidebar_go_bottom_shortcut   B    # default: G
set -g @tmux_sidebar_rename_window_shortcut rw # default: rw
set -g @tmux_sidebar_rename_session_shortcut rs # default: rs
set -g @tmux_sidebar_close_pane_shortcut  dd   # default: x
```

Shortcuts are validated on load. If any value is empty, duplicates another,
overlaps as a prefix, or contains the reserved `q` key, all seven revert to
defaults.

### Scroll offset

Control how many lines of context stay visible above and below the cursor
when navigating (like vim's `scrolloff`):

```tmux
set -g @tmux_sidebar_scrolloff 8      # default: 8
```

Set to `0` for edge-only scrolling — the viewport scrolls only when the
cursor reaches the very top or bottom.

### Hide panes

Show only sessions and windows in the tree, hiding individual panes. Panes
with an active agent badge still appear under their window.

```tmux
set -g @tmux_sidebar_hide_panes on     # default: off
```

### Badge icons

Override the default badge icons for agent status indicators:

```tmux
set -g @tmux_sidebar_badge_running      "⏳"   # default: ⏳
set -g @tmux_sidebar_badge_needs_input  "❓"   # default: ❓
set -g @tmux_sidebar_badge_done         "✅"   # default: ✅
set -g @tmux_sidebar_badge_error        "❌"   # default: ❌
```

### Colors

Override the colors used for each element type in the tree:

```tmux
set -g @tmux_sidebar_color_session "#1a2f4e"
set -g @tmux_sidebar_color_window  "#4a5568"
set -g @tmux_sidebar_color_pane    "#a0aec0"
```

Values are hex color codes. When not set, colors are derived from your tmux
theme — session color falls back to `pane-active-border-style` foreground,
window color to `pane-border-style` foreground, and pane color to
`status-style` foreground.

### Key overrides

Override the default tmux keybindings for toggle and focus:

```tmux
set -g @tmux_sidebar_toggle_key  b    # default: t
set -g @tmux_sidebar_focus_key   B    # default: T
```

### Quick reference

| Option                               | Default | Description                      |
| ------------------------------------ | :-----: | -------------------------------- |
| `@tmux_sidebar_width`                |  `25`   | Sidebar column width             |
| `@tmux_sidebar_focus_on_open`        |   `1`   | Focus sidebar when toggled open  |
| `@tmux_sidebar_session_order`        |    —    | Comma-separated session ordering |
| `@tmux_sidebar_add_window_shortcut`  |  `aw`   | Shortcut to add a window         |
| `@tmux_sidebar_add_session_shortcut` |  `as`   | Shortcut to add a session        |
| `@tmux_sidebar_go_top_shortcut`      |  `gg`   | Shortcut to jump to the top      |
| `@tmux_sidebar_go_bottom_shortcut`   |   `G`   | Shortcut to jump to the bottom   |
| `@tmux_sidebar_rename_window_shortcut` | `rw` | Shortcut to rename a window      |
| `@tmux_sidebar_rename_session_shortcut` | `rs` | Shortcut to rename a session     |
| `@tmux_sidebar_close_pane_shortcut`  |   `x`   | Shortcut to close selected pane  |
| `@tmux_sidebar_hide_panes`           |  `off`  | Show only sessions and windows   |
| `@tmux_sidebar_scrolloff`            |   `8`   | Cursor scroll margin (like vim)  |
| `@tmux_sidebar_badge_running`         |  `⏳`   | Badge for running status         |
| `@tmux_sidebar_badge_needs_input`    |  `❓`   | Badge for needs-input status     |
| `@tmux_sidebar_badge_done`           |  `✅`   | Badge for done status            |
| `@tmux_sidebar_badge_error`          |  `❌`   | Badge for error status           |
| `@tmux_sidebar_color_session`        |    —    | Session name color (hex)         |
| `@tmux_sidebar_color_window`         |    —    | Window name color (hex)          |
| `@tmux_sidebar_color_pane`           |    —    | Pane name color (hex)            |
| `@tmux_sidebar_toggle_key`           |   `t`   | Tmux key to toggle sidebar       |
| `@tmux_sidebar_focus_key`            |   `T`   | Tmux key to focus sidebar        |

| Environment variable     | Description                                                                                    |
| ------------------------ | ---------------------------------------------------------------------------------------------- |
| `TMUX_SIDEBAR_WIDTH`     | Overrides `@tmux_sidebar_width`                                                                |
| `TMUX_SIDEBAR_STATE_DIR` | State file directory (default `$XDG_STATE_HOME/tmux-sidebar` or `~/.local/state/tmux-sidebar`) |

## Hook Integration

Agents report their status through `scripts/features/state/update-pane-state.sh`:

```bash
~/.tmux/plugins/tmux-sidebar/scripts/features/state/update-pane-state.sh \
  --pane "$TMUX_PANE" \
  --app claude \
  --status needs-input \
  --message "Permission request"
```

Supported `--status` values: `running`, `needs-input`, `done`, `error`, `idle`.

### Agent hook examples

Ready-to-use hook wrappers live in `examples/`:

- **`examples/claude-hook.sh`** — reads `CLAUDE_HOOK_EVENT_NAME` and
  `CLAUDE_NOTIFICATION_MESSAGE`
- **`examples/codex-hook.sh`** — reads `CODEX_STATUS` and `CODEX_MESSAGE`
- **`examples/opencode-hook.sh`** — reads `OPENCODE_STATUS` and
  `OPENCODE_MESSAGE`

The built-in `scripts/features/hooks/hook-claude.sh` and `scripts/features/hooks/hook-codex.sh` provide
richer event parsing if you need finer-grained status mapping.

## Requirements

- tmux 3.0+
- Python 3 (for the interactive UI)
- bash 4.0+

## Development

### Internal layout

The runtime entrypoints stay small and most shared logic now lives in focused
helpers:

```text
scripts/
  core/
    lib.sh                 <- shared bash utilities
    hook-lib.sh            <- shared shell hook input handling
    hook-parser.py         <- shared Claude/Codex event parsing
  ui/
    sidebar-ui.py          <- interactive loop entrypoint
    sidebar_ui_lib/
      core.py              <- tmux/config helpers, prompts, pane actions
      status.py            <- live agent detection, badge selection
      tree.py              <- tree loading, selection, search helpers
      render.py            <- curses colors, drawing, row-map/context-menu IPC
  features/
    sidebar/               <- pane lifecycle, focus, rendering, reload helpers
    hooks/                 <- Claude/Codex hook wrappers
    state/                 <- pane-state file writers/cleanup
    context-menu/          <- right-click menu integration
    sessions/              <- prompted window/session creation helpers
```

`scripts/ui/sidebar-ui.py` remains the import surface used by the tests, while the
implementation details live under `scripts/ui/sidebar_ui_lib/`.

### Tests

```bash
bash tests/run.sh
```

Tests use a fake tmux binary — no live session needed.

### Live reload

After editing scripts or the UI, push your changes into the running plugin
directory and reload all sidebar panes in one step:

```bash
bash scripts/install-live.sh
```

This copies the working tree into `~/.config/tmux/plugins/tmux-sidebar`,
patches `#{d:current_file}` references, re-sources the tmux config, and
respawns every open sidebar pane. It also keeps agent hooks in
`~/.claude/settings.json` and `~/.codex/config.toml` pointing at the installed
copy.

If you only changed `scripts/ui/sidebar-ui.py` and want to skip the full install, you can
respawn the sidebar panes directly:

```bash
bash scripts/features/sidebar/reload-sidebar-panes.sh
```

## License

MIT
