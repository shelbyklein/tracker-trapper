#!/bin/bash
set -euo pipefail

# Consume Codex app-server JSON-RPC notifications. The app-server emits
# turn/plan/updated with plan entries shaped as {step,status}; stable TT IDs
# in step text are preferred, with exact description matching as fallback.
: "${TT_RUN_ID:?TT_RUN_ID is required}"
: "${TT_TRACKER_TRAPPER_BIN:?TT_TRACKER_TRAPPER_BIN is required}"
: "${TT_PLAN_ID:?TT_PLAN_ID is required}"
STORE="${TRACKER_TRAPPER_STORE:-$HOME/Library/Application Support/TrackerTrapper/store.json}"

while IFS= read -r line; do
  [ -n "$line" ] || continue
  METHOD="$(printf '%s' "$line" | jq -r '.method // empty')"
  [ "$METHOD" = "turn/plan/updated" ] || continue
  TURN_ID="$(printf '%s' "$line" | jq -r '.params.turnId // "turn"')"
  printf '%s' "$line" | jq -r '.params.plan[] | [.step, .status] | @tsv' |
    while IFS=$'\t' read -r STEP STATUS; do
      TODO_ID="$(printf '%s' "$STEP" | sed -nE 's/.*(TT-[0-9]+).*/\1/p')"
      if [ -z "$TODO_ID" ]; then
        TODO_ID="$(TRACKER_TRAPPER_STORE="$STORE" "$TT_TRACKER_TRAPPER_BIN" get-plan --plan-id "$TT_PLAN_ID" |
          jq -r --arg step "$STEP" '.todos[] | select(.description == $step) | .id' | head -n 1)"
      fi
      if [ -z "$TODO_ID" ]; then
        TRACKER_TRAPPER_STORE="$STORE" "$TT_TRACKER_TRAPPER_BIN" activity --run-id "$TT_RUN_ID" \
          --message "Codex plan item could not be matched: $STEP" \
          --event-id "codex:$TURN_ID:unmatched:$STEP" >/dev/null
        continue
      fi
      case "$STATUS" in
        inProgress) TARGET="in_progress"; MESSAGE="Codex plan started: $STEP" ;;
        completed) TARGET="completed"; MESSAGE="Codex plan completed: $STEP" ;;
        pending) continue ;;
        *) TARGET="pending"; MESSAGE="Codex plan status $STATUS: $STEP" ;;
      esac
      TRACKER_TRAPPER_STORE="$STORE" "$TT_TRACKER_TRAPPER_BIN" update-task \
        --run-id "$TT_RUN_ID" --todo-id "$TODO_ID" --status "$TARGET" \
        --message "$MESSAGE" --evidence "Codex app-server turn/plan/updated: $TURN_ID" \
        --event-id "codex:$TURN_ID:$TODO_ID:$STATUS" >/dev/null
    done
done
