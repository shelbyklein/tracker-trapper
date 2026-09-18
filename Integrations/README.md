# Agent integrations

The adapters report activity through the same local service used by the menu-bar app. Agents may use the CLI or configure `tracker-trapper-mcp` as a local stdio MCP server. They intentionally do not infer task completion from file activity. The agent must call `update_task` or `update-task` with a stable todo ID and evidence when a task is actually complete.

Build the CLI, then set `TT_TRACKER_TRAPPER_BIN` to the absolute binary path and `TT_RUN_ID` to a run returned by `start-run`. Copy the matching JSON into the agent's local hook/settings configuration and replace both `/absolute/path/to` and `run-id` with values for your setup. Review and trust hooks in Codex before enabling them.

Supported automatic signals:

- Codex: `PostToolUse` and `Stop`.
- Claude Code: `PostToolUse` and `Stop`.

The current adapters intentionally report bounded activity only. Plan registration and todo status changes are explicit CLI operations, which keeps automatic hooks from marking work complete or recursively reporting their own updates.
