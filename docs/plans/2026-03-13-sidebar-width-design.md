# Sidebar Width Design

## Goal

Make the sidebar narrower by default and expose a user-facing width setting that
works naturally for tmux plugin users.

## Current State

The sidebar width is currently controlled only by the `TMUX_SIDEBAR_WIDTH`
environment variable inside `scripts/ensure-sidebar-pane.sh`. If that variable
is unset, the script falls back to a hard-coded width of `40`.

## Approach Options

### Option 1: Change only the hard-coded default

This is the smallest code change, but it does not solve the user-facing
configuration problem because plugin users would still need to discover and set
an environment variable manually.

### Option 2: Add a tmux option and keep env override

Read a new tmux option such as `@tmux_sidebar_width`, use it as the documented
configuration mechanism, keep `TMUX_SIDEBAR_WIDTH` as a lower-level override,
and change the final fallback to `35`.

This fits tmux plugin conventions, keeps existing automation hooks working, and
adds only a small amount of shell logic.

### Option 3: Add a percentage-based sizing model

This is more flexible, but it adds unnecessary complexity for the current need
and would require broader design/testing work.

## Decision

Use Option 2.

## Detailed Design

- `scripts/ensure-sidebar-pane.sh` will resolve width in this order:
  `TMUX_SIDEBAR_WIDTH` environment variable, then `@tmux_sidebar_width`, then
  default `35`.
- The tmux option will be read with `tmux show-options -gv
  @tmux_sidebar_width`, swallowing missing-option errors the same way other
  option reads already do in the codebase.
- Tests will be updated to reflect the new default width of `35`.
- A new test will cover the tmux option path explicitly so the user-facing
  configuration is exercised.
- `README.md` will document:
  - the new default width
  - how to set `@tmux_sidebar_width` in `tmux.conf`
  - that `TMUX_SIDEBAR_WIDTH` still overrides the tmux option when needed

## Error Handling

If the tmux option is unset, empty, or unavailable, the script falls back to
the default width. No new user-visible error paths are introduced.

## Testing

- Update existing shell tests that currently assert width `40`
- Add a failing shell test proving `@tmux_sidebar_width` is honored
- Run the targeted width-related tests and then the full shell test suite
