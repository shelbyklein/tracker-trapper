# Agent integrations

The adapters report activity through the same local service used by the menu-bar app. Agents may use the CLI or configure `tracker-trapper-mcp` as a local stdio MCP server. They intentionally do not infer task completion from file activity. The agent must call `update_task` or `update-task` with a stable todo ID and evidence when a task is actually complete.

Build the CLI, then set `TT_TRACKER_TRAPPER_BIN` to the absolute binary path and `TT_RUN_ID` to a run returned by `start-run`. Copy the matching JSON into the agent's local hook/settings configuration and replace both `/absolute/path/to` and `run-id` with values for your setup. Review and trust hooks in Codex before enabling them.

Supported automatic signals:

- Codex: `PostToolUse` and `Stop`; `report-codex-plan.sh` consumes legacy `turn/plan/updated` notifications and native v2 `item/plan/delta` plus `item/completed` plan items.
- Claude Code: `PostToolUse` and `Stop`.

Claude `TaskCreated` and `TaskCompleted` hooks use `report-hook.sh`. If the task subject contains a stable ID such as `[TT-07] Map native tasks`, the hook maps it to `start-task` or `complete-task`. Tasks without a TT ID become activity events and cannot silently complete a plan item.

The current adapters intentionally report bounded activity only. Plan registration and todo status changes are explicit CLI operations, which keeps automatic hooks from marking work complete or recursively reporting their own updates.

For Codex app-server integrations, pipe its JSON-RPC notification stream to `report-codex-plan.sh` with `TT_RUN_ID`, `TT_PLAN_ID`, `TT_TRACKER_TRAPPER_BIN`, and optionally `TRACKER_TRAPPER_STORE`. The adapter accumulates native plan deltas until the plan item completes, then matches stable `TT-xx` IDs in plan steps first and exact todo descriptions second; unmatched or status-free steps become activity events instead of changing a todo by guesswork.
