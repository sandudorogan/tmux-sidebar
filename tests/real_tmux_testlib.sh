#!/usr/bin/env bash
set -euo pipefail

TEST_TMP="$(mktemp -d "/tmp/tmux-sidebar-real-tests.XXXXXX")"
REAL_TMUX_SOCKET="tmux-sidebar-real-$$"
REAL_TMUX_SOCKET_PATH="$TEST_TMP/$REAL_TMUX_SOCKET.sock"
REAL_TMUX_STATE_DIR="$TEST_TMP/state"
REPO_ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"

trap 'tmux -S "$REAL_TMUX_SOCKET_PATH" kill-server 2>/dev/null || true; rm -rf "$TEST_TMP"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  case "$haystack" in
    *"$needle"*) ;;
    *) fail "expected output to contain [$needle]" ;;
  esac
}

assert_eq() {
  local actual="$1"
  local expected="$2"
  if [ "$actual" != "$expected" ]; then
    fail "expected [$expected], got [$actual]"
  fi
}

real_tmux() {
  tmux -S "$REAL_TMUX_SOCKET_PATH" -f /dev/null "$@"
}

real_tmux_shell_command() {
  local shell_command=""
  printf -v shell_command '%q ' "$@"
  printf '%s\n' "${shell_command% }"
}

real_tmux_run_shell_capture() {
  local shell_command=""
  local token="$$.$RANDOM"
  local output_file="$TEST_TMP/run-shell-output.$token"
  local status_file="$TEST_TMP/run-shell-status.$token"
  local wrapped_command=""
  local attempts=100
  local status=""
  local output=""
  local _attempt

  shell_command="$(real_tmux_shell_command "$@")"
  printf -v wrapped_command 'bash -lc %q' \
    "($shell_command) > \"$output_file\" 2>&1; printf '%s\n' \"\$?\" > \"$status_file\""
  real_tmux run-shell -b "$wrapped_command"

  for _attempt in $(seq 1 "$attempts"); do
    if [ -f "$status_file" ]; then
      status="$(tr -d '\n' < "$status_file")"
      if [ -f "$output_file" ]; then
        output="$(<"$output_file")"
      fi
      rm -f "$output_file" "$status_file"
      if [ "$status" = "0" ]; then
        printf '%s\n' "$output"
        return 0
      fi
      printf '%s\n' "$output"
      fail "run-shell command failed with status [$status]: [$shell_command]"
    fi
    sleep 0.05
  done

  if [ -f "$output_file" ]; then
    output="$(<"$output_file")"
  fi
  rm -f "$output_file" "$status_file"
  printf '%s\n' "$output"
  fail "run-shell command did not finish: [$shell_command]"
}

real_tmux_start_server() {
  mkdir -p "$REAL_TMUX_STATE_DIR"
  real_tmux new-session -d -s work -n editor
  real_tmux set-environment -g TMUX_SIDEBAR_STATE_DIR "$REAL_TMUX_STATE_DIR"
  real_tmux set-option -g remain-on-exit on
  real_tmux set-option -g status off
}

real_tmux_source_plugin() {
  real_tmux_source_file "$REPO_ROOT/sidebar.tmux"
}

real_tmux_source_file() {
  local path="$1"
  real_tmux source-file "$path"
}

real_tmux_wait_for_sidebar_pane() {
  local window_id="$1"
  local attempts="${2:-100}"
  local pane_id=""
  local pane_snapshot=""
  local _attempt

  for _attempt in $(seq 1 "$attempts"); do
    pane_id="$(
      real_tmux list-panes -t "$window_id" -F '#{pane_id}|#{pane_title}' \
        | awk -F'|' '$2 == "Sidebar" { print $1; exit }'
    )"
    if [ -n "$pane_id" ]; then
      printf '%s\n' "$pane_id"
      return 0
    fi
    sleep 0.05
  done

  pane_snapshot="$(real_tmux list-panes -t "$window_id" -F '#{pane_id}|#{pane_title}|#{pane_current_command}' 2>&1 || true)"
  fail "sidebar pane did not appear in window [$window_id]; panes: [$pane_snapshot]"
}

real_tmux_wait_for_capture() {
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
  fail "pane [$pane_id] never rendered [$expected]"
}
