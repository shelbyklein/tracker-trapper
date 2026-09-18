# Agent integrations

Start with the [Mac installation and usage guide](../docs/mac-guide.md#5-connect-codex-or-claude-code) for building the executables and connecting Codex or Claude Code.

Core CLI/MCP reporting, hook adapters, background session watching, explicit
next-task selection, and the **Stop watching** UI are included in source.
Rebuild and reconnect older MCP clients to load the current tools.

## Local plans and session-scoped commands

Local plans use the same store, runs, stable todo IDs, evidence, watcher, and
menu-bar cards without requiring Git, `gh`, or a GitHub account. Tracking is
off by default and no startup hook asks about it. Start it only for the current
session with the tracker skill or through a workflow that deliberately binds a
plan and run.

`register-local-plan` and MCP `register_local_plan` require a stable
`creationRequestKey`; retrying with that key returns the existing plan. Local
events stay in local history and never enter the GitHub sync outbox.

Install the `Integrations/skills/tracker` folder at
`~/.agents/skills/tracker` for Codex and `~/.claude/skills/tracker` for Claude
Code. Codex uses `$tracker on|off|start|status`; Claude Code exposes
`/tracker on|off|start|status`. `on` and `start` opt in only the current
session. `off` pauses that session's active run and keeps its saved plan.

Copy the skill after building Tracker Trapper:

```sh
mkdir -p ~/.agents/skills ~/.claude/skills
ditto Integrations/skills/tracker ~/.agents/skills/tracker
ditto Integrations/skills/tracker ~/.claude/skills/tracker
```

The `issue-to-work` skill uses `set_session_tracking` after it retrieves or
registers the issue plan and starts the current session run. This binds the
session without creating a second local plan. Reconnect clients after a rebuild
so the local-plan and session-binding MCP tools are visible.

## Background session watcher

The running menu-bar app observes explicitly linked Codex/Claude JSONL sessions every second, including when its popover is closed. This is independent of agent MCP calls. Select **Link session…** on an active run, call MCP `watch_session` with `runID`, absolute `sourcePath`, and `format` (`codex` or `claude`), or run:

```sh
.build/release/tracker-trapper watch-session --run-id RUN_ID --source /absolute/session.jsonl --format codex
.build/release/tracker-trapper watch-status
```

Use the actual session identity, not a guess based on repository or filename. The source header is validated; linking an already-linked file is idempotent. The observer starts at EOF and does not import historical completions. Its read cursor survives restart. Only new assistant messages and tool activity refresh the agent's activity timestamp. Reasoning, user messages, tool arguments and raw tool output are not copied into progress; summaries are local and bounded to 240 characters.

Explicit assistant completion lines are supported as a fallback:

```text
TT-87-04: completed — unit tests passed
- [x] TT-87-05 — acceptance checks passed
```

The entire ID must match a todo on the linked issue. These are **agent-reported** completions, not independently verified acceptance. Quoted/code-fenced examples, ordinary prose, tool output and unknown IDs never check a box. Completed/skipped tasks and newer explicit updates are preserved. Each batch keeps explicit completions and coalesces ordinary activity; the watcher doesn't run another LLM.

MCP `unwatch_session` or CLI `unwatch-session --run-id RUN_ID` detaches one watcher. The menu-bar **Stop watching** button also clears the issue card, as described below. `watch-once` polls linked sources once for diagnostics. A non-active run is not observed. Polls with no output never manufacture activity. If a file disappears or its session identity changes, the UI reports the problem. Replacement/truncation with the same identity starts from the new EOF to avoid replay. A source record over 2 MiB requires relinking after it finishes. The checkpoint file is `store.watchers.json` beside the plan store; back it up with the store. No login service is installed: quitting the menu-bar app stops observation.

These JSONL readers are compatibility adapters for current local logs, not a stable provider protocol. The Codex shared app-server control socket was unavailable during implementation, so the observer does not attach to, resume, or start agent threads. Only files explicitly selected for tracking are read. Unsupported formats fail visibly; remote-only sessions require a separate transport.

The adapters report activity through the same local service used by the menu-bar app. Agents may use the CLI or configure `tracker-trapper-mcp` as a local stdio MCP server. They intentionally do not infer task completion from file activity. The agent must call `update_task` or `update-task` with a stable todo ID and evidence when a task is actually complete.

Build the CLI, then set `TT_TRACKER_TRAPPER_BIN` to the absolute binary path and `TT_RUN_ID` to a run returned by `start-run`. Copy the matching JSON into the agent's local hook/settings configuration and replace both `/absolute/path/to` and `run-id` with values for your setup. Review and trust hooks in Codex before enabling them.

Supported automatic signals:

- Codex: `PostToolUse` and `Stop`; `report-codex-plan.sh` consumes legacy `turn/plan/updated` notifications and native v2 `item/plan/delta` plus `item/completed` plan items.
- Claude Code: `PostToolUse` and `Stop`.

Claude `TaskCreated` and `TaskCompleted` hooks use `report-hook.sh`. If the task subject contains a stable ID such as `[TT-07] Map native tasks`, the hook maps it to `start-task` or `complete-task`. Tasks without a TT ID become activity events and cannot silently complete a plan item.

Activity hooks report bounded activity. Native task/plan adapters can update statuses only through their documented stable-ID or exact-description mapping. They do not treat arbitrary tool activity as proof of completion; explicit CLI/MCP reports with evidence remain the primary progress contract.

For Codex app-server integrations, pipe its JSON-RPC notification stream to `report-codex-plan.sh` with `TT_RUN_ID`, `TT_PLAN_ID`, `TT_TRACKER_TRAPPER_BIN`, and optionally `TRACKER_TRAPPER_STORE`. The adapter accumulates native plan deltas until the plan item completes, then matches stable `TT-xx` IDs in plan steps first and exact todo descriptions second; unmatched or status-free steps become activity events instead of changing a todo by guesswork.

### Explicit next task

Set the issue's next unfinished task with MCP `set_next_task(runID, nextTodoID)`
or CLI `tracker-trapper set-next-task --run-id RUN --next-todo-id TT-ID`.
The same optional `nextTodoID` / `--next-todo-id` parameter is supported on
start, update, complete, and activity reports. For example, complete one task
and select the next in a single atomic report:

```sh
tracker-trapper complete-task --run-id RUN --todo-id TT-01 --evidence "Checks passed" --next-todo-id TT-02
```

Omitting the parameter preserves the selection. An empty string explicitly
clears it. Unknown, completed, or skipped IDs are rejected without applying
any part of that update. Completing or skipping the selected task clears it;
watcher-reported completion also clears it. No next task is inferred from
checklist order. The selection is stored on the plan and returned by `get_plan`.
The menu-bar card marks it with a filled blue dot and an accessible “Next task”
label. Every panel reveal starts all cards in remaining-only mode.

Reconnect MCP clients after upgrading so their running server processes expose
the new parameter. The selection is also journaled in existing event fields so
unrelated writes from older running clients preserve it.

The menu-bar **Stop watching** button stops all session watchers for that issue
and removes its card and attention messages from the panel. This dismissal
persists across refreshes and app restarts. Starting a new run for the issue
shows it again. Saved plans, evidence, and run history remain available through
the CLI/MCP. The standalone `unwatch_session` tool still only unlinks a watcher.
