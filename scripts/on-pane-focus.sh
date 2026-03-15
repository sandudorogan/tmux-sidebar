#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

pane_id="${1:-}"
window_id="${2:-}"

enabled="$(tmux show-options -gv @tmux_sidebar_enabled 2>/dev/null || printf '0\n')"

if [ -n "$pane_id" ]; then
  pane_title="$(tmux display-message -p -t "$pane_id" '#{pane_title}' 2>/dev/null || true)"
  if ! printf '%s\n' "$pane_title" | grep -Eq "$(sidebar_title_pattern)"; then
    tmux set-option -g @tmux_sidebar_main_pane "$pane_id"
  fi

  if [[ "$pane_id" =~ ^%[0-9]+$ ]]; then
    state_dir="$(print_state_dir)"
    state_file="$state_dir/pane-$pane_id.json"
    if [ -f "$state_file" ]; then
      app="$(json_get_string "$state_file" "app")"
      status="$(json_get_string "$state_file" "status")"
      case "$app:$status" in
        *:needs-input|*:done)
          tmp_file="$(mktemp "$state_dir/.pane-state.XXXXXX")"
          sed 's/"status":"[^"]*"/"status":"idle"/' "$state_file" > "$tmp_file"
          mv "$tmp_file" "$state_file"
          signal_sidebar_refresh
          ;;
      esac
    fi
  fi
fi

[ "$enabled" = "1" ] || exit 0
exec bash "$SCRIPT_DIR/ensure-sidebar-pane.sh" "$pane_id" "$window_id"
