#!/bin/bash
set -euo pipefail

: "${TT_RUN_ID:?TT_RUN_ID is required}"
: "${TT_TRACKER_TRAPPER_BIN:?TT_TRACKER_TRAPPER_BIN is required}"
STORE="${TRACKER_TRAPPER_STORE:-$HOME/Library/Application Support/TrackerTrapper/store.json}"
INPUT="$(cat)"
EVENT="$(printf '%s' "$INPUT" | jq -r '.hook_event_name // "activity"')"
SESSION="$(printf '%s' "$INPUT" | jq -r '.session_id // "session"')"
TASK_ID="$(printf '%s' "$INPUT" | jq -r '.task_id // empty')"
SUBJECT="$(printf '%s' "$INPUT" | jq -r '.task_subject // empty')"
TODO_ID="$(printf '%s' "$SUBJECT" | sed -nE 's/.*(TT-[0-9]+).*/\1/p')"
EVENT_ID="${SESSION}:${TASK_ID:-turn}:${EVENT}"

case "$EVENT" in
  TaskCreated)
    if [ -n "$TODO_ID" ]; then
      TRACKER_TRAPPER_STORE="$STORE" "$TT_TRACKER_TRAPPER_BIN" start-task --run-id "$TT_RUN_ID" --todo-id "$TODO_ID" --message "$SUBJECT" --event-id "$EVENT_ID" >/dev/null
    else
      TRACKER_TRAPPER_STORE="$STORE" "$TT_TRACKER_TRAPPER_BIN" activity --run-id "$TT_RUN_ID" --message "Claude task created without a TT ID" --event-id "$EVENT_ID" >/dev/null
    fi
    ;;
  TaskCompleted)
    if [ -n "$TODO_ID" ]; then
      TRACKER_TRAPPER_STORE="$STORE" "$TT_TRACKER_TRAPPER_BIN" complete-task --run-id "$TT_RUN_ID" --todo-id "$TODO_ID" --message "$SUBJECT" --evidence "Claude TaskCompleted: ${TASK_ID:-unknown}" --event-id "$EVENT_ID" >/dev/null
    else
      TRACKER_TRAPPER_STORE="$STORE" "$TT_TRACKER_TRAPPER_BIN" activity --run-id "$TT_RUN_ID" --message "Claude task completed without a TT ID" --event-id "$EVENT_ID" >/dev/null
    fi
    ;;
  *)
    TRACKER_TRAPPER_STORE="$STORE" "$TT_TRACKER_TRAPPER_BIN" activity --run-id "$TT_RUN_ID" --message "${TT_EVENT_MESSAGE:-$EVENT}" --event-id "$EVENT_ID" >/dev/null
    ;;
esac
