#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib.sh"
pane_id=""
app=""
status=""
message=""
updated_at=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --pane)
      pane_id="${2:-}"
      shift 2
      ;;
    --app)
      app="${2:-}"
      shift 2
      ;;
    --status)
      status="${2:-}"
      shift 2
      ;;
    --message)
      message="${2:-}"
      shift 2
      ;;
    --updated-at)
      updated_at="${2:-}"
      shift 2
      ;;
    *)
      printf 'unknown arg: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

if [ -z "$pane_id" ]; then
  pane_id="$(tmux display-message -p '#{pane_id}' 2>/dev/null || true)"
fi

[ -n "$pane_id" ] || exit 0
[[ "$pane_id" =~ ^%[0-9]+$ ]] || { printf 'invalid pane_id: %s\n' "$pane_id" >&2; exit 1; }

state_dir="$(print_state_dir)"
mkdir -p "$state_dir"
state_file="$state_dir/pane-$pane_id.json"

if [ -z "$updated_at" ]; then
  updated_at="$(date +%s)"
fi
[[ "$updated_at" =~ ^[0-9]+$ ]] || { printf 'invalid updated_at: %s\n' "$updated_at" >&2; exit 1; }

if [ -f "$state_file" ]; then
  existing_updated_at="$(json_get_number "$state_file" "updated_at")"
  if [ -n "$existing_updated_at" ] && [ "$existing_updated_at" -gt "$updated_at" ]; then
    exit 0
  fi
fi

session_name=""
window_id=""
window_name=""
pane_title=""
pane_current_command=""

metadata="$(tmux display-message -p -t "$pane_id" '#{session_name}|#{window_id}|#{window_name}|#{pane_title}|#{pane_current_command}' 2>/dev/null || true)"
if [ -n "$metadata" ]; then
  IFS='|' read -r session_name window_id window_name pane_title pane_current_command <<EOF
$metadata
EOF
elif [ -f "$state_file" ]; then
  session_name="$(json_get_string "$state_file" "session_name")"
  window_id="$(json_get_string "$state_file" "window_id")"
  window_name="$(json_get_string "$state_file" "window_name")"
  pane_title="$(json_get_string "$state_file" "pane_title")"
  pane_current_command="$(json_get_string "$state_file" "pane_current_command")"
fi

tmp_file="$(mktemp "$state_dir/.pane-state.XXXXXX")"
printf '{' > "$tmp_file"
printf '"pane_id":"%s",' "$(json_escape "$pane_id")" >> "$tmp_file"
printf '"session_name":"%s",' "$(json_escape "$session_name")" >> "$tmp_file"
printf '"window_id":"%s",' "$(json_escape "$window_id")" >> "$tmp_file"
printf '"window_name":"%s",' "$(json_escape "$window_name")" >> "$tmp_file"
printf '"pane_title":"%s",' "$(json_escape "$pane_title")" >> "$tmp_file"
printf '"pane_current_command":"%s",' "$(json_escape "$pane_current_command")" >> "$tmp_file"
printf '"app":"%s",' "$(json_escape "$app")" >> "$tmp_file"
printf '"status":"%s",' "$(json_escape "$status")" >> "$tmp_file"
printf '"message":"%s",' "$(json_escape "$message")" >> "$tmp_file"
printf '"updated_at":%s' "$updated_at" >> "$tmp_file"
printf '}\n' >> "$tmp_file"
mv "$tmp_file" "$state_file"
signal_sidebar_refresh
