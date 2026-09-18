#!/bin/bash
set -euo pipefail

# Consume Codex app-server JSON-RPC notifications. Current clients can expose
# either turn/plan/updated ({step,status}) or native item/plan/delta events.
# Stable TT IDs are preferred; unmatched or status-free plan text becomes
# activity instead of silently changing an issue todo.
: "${TT_RUN_ID:?TT_RUN_ID is required}"
: "${TT_TRACKER_TRAPPER_BIN:?TT_TRACKER_TRAPPER_BIN is required}"
: "${TT_PLAN_ID:?TT_PLAN_ID is required}"
STORE="${TRACKER_TRAPPER_STORE:-$HOME/Library/Application Support/TrackerTrapper/store.json}"
DELTA_DIR="$(mktemp -d -t tracker-trapper-codex-plan)"
trap 'rm -rf "$DELTA_DIR"' EXIT

resolve_todo() {
  local step="$1" todo_id
  todo_id="$(printf '%s' "$step" | sed -nE 's/.*(TT-[0-9]+).*/\1/p')"
  if [ -z "$todo_id" ]; then
    todo_id="$(TRACKER_TRAPPER_STORE="$STORE" "$TT_TRACKER_TRAPPER_BIN" get-plan --plan-id "$TT_PLAN_ID" | jq -r --arg step "$step" '.todos[] | select(.description == $step) | .id' | head -n 1)"
  fi
  printf '%s' "$todo_id"
}

report_activity() {
  local message="$1" event_id="$2"
  TRACKER_TRAPPER_STORE="$STORE" "$TT_TRACKER_TRAPPER_BIN" activity --run-id "$TT_RUN_ID" --message "$message" --event-id "$event_id" >/dev/null
}

apply_status_plan() {
  local step="$1" status="$2" turn_id="$3" todo_id target message
  todo_id="$(resolve_todo "$step")"
  if [ -z "$todo_id" ]; then report_activity "Codex plan item could not be matched: $step" "codex:$turn_id:unmatched:$step"; return; fi
  case "$status" in
    inProgress) target="in_progress"; message="Codex plan started: $step" ;;
    completed) target="completed"; message="Codex plan completed: $step" ;;
    pending) return ;;
    *) target="pending"; message="Codex plan status $status: $step" ;;
  esac
  TRACKER_TRAPPER_STORE="$STORE" "$TT_TRACKER_TRAPPER_BIN" update-task --run-id "$TT_RUN_ID" --todo-id "$todo_id" --status "$target" --message "$message" --evidence "Codex app-server plan update: $turn_id" --event-id "codex:$turn_id:$todo_id:$status" >/dev/null
}

apply_native_plan_text() {
  local text="$1" turn_id="$2" raw step todo_id index=0
  while IFS= read -r raw; do
    case "$raw" in *TT-[0-9]*) ;; *) continue ;; esac
    index=$((index + 1))
    step="$(printf '%s' "$raw" | sed -E 's/^[[:space:]]*[0-9]+\.[[:space:]]*//; s/^[[:space:]]*-[[:space:]]*\[[^]]\][[:space:]]*//')"
    todo_id="$(resolve_todo "$step")"
    if printf '%s' "$raw" | grep -Eq '\[[xX]\]'; then
      apply_status_plan "$step" completed "$turn_id"
    elif printf '%s' "$raw" | grep -Eq '\[[>~]\]'; then
      apply_status_plan "$step" inProgress "$turn_id"
    elif [ -n "$todo_id" ]; then
      report_activity "Codex native plan item: $step" "codex:$turn_id:native:$index"
    else
      report_activity "Codex native plan item could not be matched: $step" "codex:$turn_id:unmatched-native:$index"
    fi
  done <<< "$text"
}

while IFS= read -r line; do
  [ -n "$line" ] || continue
  method="$(printf '%s' "$line" | jq -r '.method // empty')"
  case "$method" in
    turn/plan/updated)
      turn_id="$(printf '%s' "$line" | jq -r '.params.turnId // "turn"')"
      while IFS=$'\t' read -r step status; do apply_status_plan "$step" "$status" "$turn_id"; done < <(printf '%s' "$line" | jq -r '.params.plan[] | [.step, .status] | @tsv')
      ;;
    item/plan/delta)
      item_id="$(printf '%s' "$line" | jq -r '.params.itemId // empty')"
      [ -n "$item_id" ] || continue
      printf '%s' "$(printf '%s' "$line" | jq -r '.params.delta // empty')" >> "$DELTA_DIR/$item_id"
      ;;
    item/completed)
      [ "$(printf '%s' "$line" | jq -r '.params.item.type // empty')" = "plan" ] || continue
      turn_id="$(printf '%s' "$line" | jq -r '.params.turnId // "turn"')"
      item_id="$(printf '%s' "$line" | jq -r '.params.item.id // .params.itemId // empty')"
      text="$(printf '%s' "$line" | jq -r '.params.item.text // empty')"
      if [ -z "$text" ] && [ -n "$item_id" ] && [ -f "$DELTA_DIR/$item_id" ]; then
        text="$(cat "$DELTA_DIR/$item_id")"
      fi
      apply_native_plan_text "$text" "$turn_id"
      ;;
  esac
done
