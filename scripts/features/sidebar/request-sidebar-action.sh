#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
. "$SCRIPTS_DIR/core/lib.sh"

action="${1:-}"

case "$action" in
  jump_back|jump_forward) ;;
  *) exit 1 ;;
esac

current_pane="${TMUX_PANE:-}"
current_title=""
if [ -n "$current_pane" ]; then
  current_title="$(tmux display-message -p -t "$current_pane" '#{pane_title}' 2>/dev/null || true)"
fi
if [ -z "$current_pane" ] || [ -z "$current_title" ]; then
  current_pane="$(tmux display-message -p '#{pane_id}' 2>/dev/null || true)"
  [ -n "$current_pane" ] || exit 0
  current_title="$(tmux display-message -p -t "$current_pane" '#{pane_title}' 2>/dev/null || true)"
fi
is_sidebar_pane_title "$current_title" || exit 0

state_dir="$(print_state_dir)"
mkdir -p "$state_dir"
action_file="$state_dir/sidebar-$current_pane.actions"
lock_name="@tmux_sidebar_action_${current_pane//%/p}"
tmp_file=""

tmux wait-for -L "$lock_name"
trap 'tmux wait-for -U "$lock_name" 2>/dev/null || true; [ -z "$tmp_file" ] || rm -f "$tmp_file"' EXIT

tmp_file="$(mktemp "$state_dir/.sidebar-action.XXXXXX")"
if [ -f "$action_file" ]; then
  cat "$action_file" > "$tmp_file"
fi
printf '%s\n' "$action" >> "$tmp_file"
mv "$tmp_file" "$action_file"
tmp_file=""

signal_sidebar_refresh
