#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "$0")/real_tmux_testlib.sh"

case "$REAL_TMUX_SOCKET_PATH" in
  "$TEST_TMP"/*) ;;
  *) fail "expected real tmux socket path [$REAL_TMUX_SOCKET_PATH] to live under [$TEST_TMP]" ;;
esac

real_tmux_start_server

session_name="$(real_tmux display-message -p -t work:editor '#{session_name}')"
assert_eq "$session_name" 'work'

client_log="$TEST_TMP/client.log"
linux_command="$(
  REAL_TMUX_SCRIPT_PLATFORM=Linux \
    real_tmux_script_command "$client_log" \
      tmux -S /tmp/test.sock -f /dev/null attach-session -t work
)"
assert_contains "$linux_command" 'script -q'
assert_contains "$linux_command" "$client_log -- tmux -S /tmp/test.sock -f /dev/null attach-session -t work"

darwin_command="$(
  REAL_TMUX_SCRIPT_PLATFORM=Darwin \
    real_tmux_script_command "$client_log" \
      tmux -S /tmp/test.sock -f /dev/null attach-session -t work
)"
assert_contains "$darwin_command" 'script -q'
assert_contains "$darwin_command" "$client_log tmux -S /tmp/test.sock -f /dev/null attach-session -t work"
case "$darwin_command" in
  *"$client_log -- tmux"*) fail 'expected Darwin script command to omit [--]' ;;
esac
