#!/bin/sh
set -eu

# Configure TT_PLAN_ID/TT_RUN_ID in the agent process. Hooks only report
# bounded activity; explicit task IDs and completion evidence come from the
# agent's update-task call.
: "${TT_RUN_ID:?TT_RUN_ID is required}"
STORE="${TRACKER_TRAPPER_STORE:-$HOME/Library/Application Support/TrackerTrapper/store.json}"
MESSAGE="${TT_EVENT_MESSAGE:-agent activity}"
exec "$TT_TRACKER_TRAPPER_BIN" activity --run-id "$TT_RUN_ID" --message "$MESSAGE" --event-id "${TT_EVENT_ID:-$(uuidgen)}"
