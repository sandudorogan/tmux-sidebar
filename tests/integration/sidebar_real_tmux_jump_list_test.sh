#!/usr/bin/env bash
set -euo pipefail
export PS4='+${LINENO}: '
set -x

. "$(dirname "$0")/real_tmux_testlib.sh"

wait_for_selected_capture() {
  local pane_id="$1"
  local expected="$2"
  local attempts="${3:-100}"
  local capture=""
  local _attempt

  for _attempt in $(seq 1 "$attempts"); do
    capture="$(real_tmux capture-pane -pt "$pane_id" || true)"
    case "$capture" in
      *"$expected"*)
        printf '%s\n' "$capture"
        return 0
        ;;
    esac
    sleep 0.05
  done

  printf '%s\n' "$capture"
  fail "pane [$pane_id] never selected [$expected]"
}

real_tmux_start_server
real_tmux_source_plugin

real_tmux new-session -d -s ops -n logs 'cat'
real_tmux new-session -d -s tailing -n third 'tail -f /dev/null'
real_tmux set-option -g @tmux_sidebar_session_order 'ops,work,tailing'
real_tmux set-option -g @tmux_sidebar_enabled 1
real_tmux set-option -g @tmux_sidebar_focus_on_open 0

main_window_id="$(real_tmux display-message -p -t work:editor '#{window_id}')"
main_pane_id="$(real_tmux display-message -p -t work:editor '#{pane_id}')"
real_tmux set-option -g @tmux_sidebar_main_pane "$main_pane_id"
printf -v ensure_sidebar_cmd 'TMUX_SIDEBAR_TRACE=1 %q %q %q' \
  "$REPO_ROOT/scripts/features/sidebar/ensure-sidebar-pane.sh" "$main_pane_id" "$main_window_id"
real_tmux run-shell -b "$ensure_sidebar_cmd"

sidebar_pane_id="$(real_tmux_wait_for_sidebar_pane "$main_window_id")"
initial_capture="$(real_tmux_wait_for_capture "$sidebar_pane_id" 'tailing')"
main_pane_command="$(real_tmux display-message -p -t "$main_pane_id" '#{pane_current_command}')"
assert_contains "$initial_capture" "▶ │     └─ \$ $main_pane_command"

real_tmux select-pane -t "$sidebar_pane_id"
assert_eq "$(real_tmux display-message -p -t "$sidebar_pane_id" '#{pane_active}')" "1"

real_tmux send-keys -t "$sidebar_pane_id" G
bottom_capture="$(wait_for_selected_capture "$sidebar_pane_id" '▶       └─ : tail')"
assert_contains "$bottom_capture" 'tailing'

real_tmux send-keys -t "$sidebar_pane_id" g g
top_capture="$(wait_for_selected_capture "$sidebar_pane_id" '▶ │     └─ c cat')"
assert_contains "$top_capture" 'ops'
