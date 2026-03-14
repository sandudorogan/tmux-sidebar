# tmux-sidebar

A tmux plugin that adds an interactive sidebar showing sessions, windows, and panes with agent status badges. Written in bash and python3 (curses UI).

## Architecture

```
sidebar.tmux          <- TPM entry point, registers hooks and keybindings
scripts/
  lib.sh              <- shared bash utilities (state, tmux helpers, json)
  sidebar-ui.py       <- interactive curses UI (tree render, input, agent detection)
  toggle-sidebar.sh   <- main user-facing toggle (<prefix>t)
  ensure-sidebar-pane.sh  <- creates/maintains sidebar pane per window
  close-sidebar.sh    <- tears down all sidebar panes, restores layouts
  apply-key-overrides.sh  <- rebinds toggle/focus keys from user options
  update-pane-state.sh    <- agent hook entry point, writes pane JSON state
  refresh-sidebar.sh  <- triggers sidebar re-render
  remember-main-pane.sh   <- tracks last active non-sidebar pane
  clear-pane-state.sh     <- clears agent badge on pane focus
  focus-main-pane.sh      <- returns focus to main pane
  focus-sidebar.sh        <- toggle focus between sidebar and main pane
  handle-pane-exited.sh   <- cleanup when a pane exits
  add-window.sh / add-session.sh  <- prompted creation of windows/sessions
  configure-pane-border-format.sh <- pane border format wrapping
  install-live.sh     <- dev installer (copies to plugin dir, patches paths, reloads)
tests/
  testlib.sh          <- test framework with fake tmux binary
  run.sh              <- test runner
  *_test.sh           <- unit tests (30 files)
examples/
  claude-hook.sh / codex-hook.sh / opencode-hook.sh  <- agent integration hooks
```

State files live in `$XDG_STATE_HOME/tmux-sidebar/pane-{PANE_ID}.json` (defaults to `~/.local/state/tmux-sidebar/`).

## Testing

### Unit tests (fake tmux, no live session needed)

```bash
bash tests/run.sh tests/*_test.sh
```

Run a single test file:
```bash
bash tests/run.sh tests/lib_test.sh
```

The test framework (`tests/testlib.sh`) creates a fake `tmux` binary that simulates core commands using temp files. Tests source `testlib.sh`, set up state with helpers like `fake_tmux_register_pane` and `fake_tmux_set_tree`, then call scripts and assert results.

### Live testing in a separate tmux session

For integration testing against a real tmux server, use a dedicated session so you don't disrupt your work:

```bash
# 1. Install the working copy into the plugin directory
bash scripts/install-live.sh

# 2. Open a separate tmux session for testing
tmux new-session -d -s sidebar-test
tmux send-keys -t sidebar-test 'echo "test pane"' Enter

# 3. Toggle sidebar in the test session
tmux send-keys -t sidebar-test 'prefix' ''   # or trigger via:
tmux run-shell -t sidebar-test "$HOME/.config/tmux/plugins/tmux-sidebar/scripts/toggle-sidebar.sh"

# 4. Simulate agent state updates
bash scripts/update-pane-state.sh --pane %0 --app claude --status running
bash scripts/update-pane-state.sh --pane %0 --app claude --status needs-input
bash scripts/update-pane-state.sh --pane %0 --app claude --status idle

# 5. Clean up
tmux kill-session -t sidebar-test
```

To manually verify changes without install-live:
```bash
# Source the plugin directly in a test session
tmux new-session -d -s sidebar-test
tmux source-file sidebar.tmux   # won't work — uses #{d:current_file}
# Use install-live.sh instead, it patches paths
```

### After any code change

1. Run `bash tests/run.sh tests/*_test.sh` — all tests must pass
2. If changing UI or hooks, also run `bash scripts/install-live.sh` and verify in a live tmux session
3. If adding new functionality, add a corresponding `tests/<name>_test.sh`

## Code style

### Bash

- Always start with `#!/usr/bin/env bash` and `set -euo pipefail`
- Source shared code via `. "$SCRIPT_DIR/lib.sh"` where `SCRIPT_DIR` is resolved with `CDPATH= cd`
- Use `printf` over `echo` for output
- Quote all variable expansions: `"$var"`, `"${var:-default}"`
- Prefer `[ condition ]` for simple tests, `[[ ]]` for pattern matching
- Use `local` for all function variables
- Suppress expected errors with `2>/dev/null || true`, not by removing `set -e`
- Argument parsing uses `while [ "$#" -gt 0 ]; do case "$1" in ...` pattern
- No unnecessary comments — code should be self-documenting
- Functions go in `lib.sh` if reused across scripts
- Use `awk` for structured text processing, not complex bash string manipulation
- Temp files via `mktemp` with cleanup traps
- Atomic file writes: write to tmp, then `mv`

### Python

- Target python3, use `from __future__ import annotations`
- Type hints on function signatures
- Use `pathlib.Path` over `os.path`
- `subprocess.check_output` / `subprocess.run` for external commands
- Constants at module top as ALL_CAPS
- No classes unless genuinely needed — functions and module-level state
- `shlex.quote` for shell escaping
- Keep curses code isolated in dedicated functions

### tmux plugin conventions

- `sidebar.tmux` has no shebang — tmux sources it directly
- Use `#{d:current_file}` for relative paths in hook registrations
- Hook indices (e.g. `[198]`) are namespaced to avoid collisions with other plugins
- State stored in tmux global options prefixed `@tmux_sidebar_`
- Per-window state keyed by window ID: `@tmux_sidebar_{suffix}_w{ID}`
- Background execution via `run-shell -b` to avoid blocking tmux

### Testing conventions

- One test file per script/feature, named `<script>_test.sh`
- Test files source `testlib.sh` which provides the fake tmux and assertions
- Use `fake_tmux_register_pane`, `fake_tmux_set_tree`, `fake_tmux_no_sidebar` to set up state
- Use `run_script` to execute a script and capture output into `$output`
- Assertions: `assert_eq`, `assert_contains`, `assert_not_contains`, `assert_file_contains`, `assert_file_not_contains`
- Each test is a function called directly — no test framework dependencies
- Reset state between tests with `fake_tmux_no_sidebar`

### General

- No fallback logic unless explicitly requested
- Fail fast — `set -euo pipefail` in bash, no silent error swallowing
- Separation of concerns: lib.sh for shared logic, individual scripts for single responsibilities, sidebar-ui.py for all UI
- Atomic state mutations — write to temp file then `mv` to avoid partial reads
- Mutex via `tmux wait-for` for operations that race (e.g. ensure-sidebar-pane)
