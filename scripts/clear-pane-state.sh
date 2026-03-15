#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib.sh"
pane_id="${1:-}"
[ -n "$pane_id" ] || exit 0
[[ "$pane_id" =~ ^%[0-9]+$ ]] || exit 0

state_dir="$(print_state_dir)"
state_file="$state_dir/pane-$pane_id.json"
[ -f "$state_file" ] || exit 0

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
