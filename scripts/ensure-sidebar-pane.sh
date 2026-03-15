#!/usr/bin/env bash
set -euo pipefail

enabled="$(tmux show-options -gv @tmux_sidebar_enabled 2>/dev/null || printf '0\n')"
[ "$enabled" = "1" ] || exit 0

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib.sh"
sidebar_titles="$(sidebar_title_pattern)"
target_pane="${1:-}"
current_window="${2:-}"

if [ -z "$target_pane" ] && [ -z "$current_window" ]; then
  target_pane="$(tmux display-message -p '#{pane_id}' 2>/dev/null || true)"
fi
if [ -z "$current_window" ] && [ -n "$target_pane" ]; then
  current_window="$(tmux display-message -p -t "$target_pane" '#{window_id}' 2>/dev/null || true)"
fi
if [ -z "$current_window" ]; then
  current_window="$(tmux display-message -p '#{window_id}' 2>/dev/null || true)"
fi
[ -n "$current_window" ] || exit 0

sidebar_pane_option="$(sidebar_window_option "pane" "$current_window")"
sidebar_creating_option="$(sidebar_window_option "creating" "$current_window")"
sidebar_focus_option="$(sidebar_focus_request_option "$current_window")"
ensure_lock="@tmux_sidebar_ensure_$(window_key_for_id "$current_window")"

tmux wait-for -L "$ensure_lock"

cleanup() {
  tmux set-option -g -u "$sidebar_creating_option" 2>/dev/null || true
  tmux set-option -g -u "$sidebar_focus_option" 2>/dev/null || true
  tmux wait-for -U "$ensure_lock" 2>/dev/null || true
}
trap cleanup EXIT

stored_pane="$(tmux show-options -gv "$sidebar_pane_option" 2>/dev/null || true)"
if [ -n "$stored_pane" ]; then
  stored_sidebar="$(
    tmux list-panes -a -F '#{pane_id}|#{pane_title}|#{window_id}' \
      | awk -F'|' -v target_pane="$stored_pane" -v current_window="$current_window" -v sidebar_titles="$sidebar_titles" \
          '$1 == target_pane && $2 ~ sidebar_titles && $3 == current_window { print $1; exit }'
  )"
  if [ -n "$stored_sidebar" ]; then
    exit 0
  fi
  tmux set-option -g -u "$sidebar_pane_option" 2>/dev/null || true
fi

existing_pane="$(
  tmux list-panes -a -F '#{pane_id}|#{pane_title}|#{window_id}' \
    | awk -F'|' -v current_window="$current_window" -v sidebar_titles="$sidebar_titles" \
        '$2 ~ sidebar_titles && $3 == current_window { print $1; exit }'
)"
if [ -n "$existing_pane" ]; then
  tmux set-option -g "$sidebar_pane_option" "$existing_pane"
  exit 0
fi

creating="$(tmux show-options -gv "$sidebar_creating_option" 2>/dev/null || true)"
[ "$creating" != "1" ] || exit 0

configured_sidebar_width="$(tmux show-options -gv @tmux_sidebar_width 2>/dev/null || true)"
sidebar_width="${TMUX_SIDEBAR_WIDTH:-${configured_sidebar_width:-25}}"
current_pane="$target_pane"
if [ -z "$current_pane" ]; then
  current_pane="$(
    tmux list-panes -t "$current_window" -F '#{pane_id}|#{pane_active}' 2>/dev/null \
      | awk -F'|' '$2 == 1 { print $1; exit }'
  )"
fi
if [ -z "$current_pane" ]; then
  current_pane="$(tmux display-message -p '#{pane_id}' 2>/dev/null || true)"
fi
sidebar_command="$(sidebar_ui_command "$SCRIPT_DIR")"
focus_sidebar="$(tmux show-options -gv "$sidebar_focus_option" 2>/dev/null || true)"

save_sidebar_window_snapshot "$current_window" "$current_pane"
tmux set-option -g "$sidebar_creating_option" 1

split_window_args=(-h -b -d -f -l "$sidebar_width" -P -F '#{pane_id}')
if [ -n "$current_pane" ]; then
  split_window_args=(-t "$current_pane" "${split_window_args[@]}")
fi
sidebar_pane="$(tmux split-window "${split_window_args[@]}" "$sidebar_command")"
tmux set-option -p -t "$sidebar_pane" allow-set-title off
tmux select-pane -t "$sidebar_pane" -T "$(sidebar_pane_title)"
tmux set-option -g "$sidebar_pane_option" "$sidebar_pane"
if [ "$focus_sidebar" = "1" ]; then
  tmux select-pane -t "$sidebar_pane"
elif [ -n "$current_pane" ]; then
  tmux select-pane -t "$current_pane"
fi
