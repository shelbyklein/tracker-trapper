# Using Tracker Trapper on your Mac

Tracker Trapper keeps GitHub issue checklists visible in your menu bar. An agent
or the CLI reports which tasks are running, blocked, or complete. Installing the
app alone does not automatically import every issue or follow every agent session.

## 1. Install from source

Requirements:

- macOS 13 or later and a Swift 6 toolchain with the macOS SDK.
- Git and access to this repository.
- [GitHub CLI](https://cli.github.com/) for importing or updating GitHub issues.
- `jq` for the commands below and the GitHub sync script.
- A local Codex or Claude Code installation if you want that agent to report progress.

Check your tools in Terminal:

```sh
xcode-select -p
swift --version
git --version
gh --version
jq --version
```

If Swift is missing or older than 6, install/select a compatible Xcode toolchain
before continuing. Apple Silicon has been tested. Intel support is not yet
runtime-verified, so these instructions discover the build directory instead
of hard-coding an architecture.

Clone into a permanent folder of your choice, then build all three executables:

```sh
git clone https://github.com/shelbyklein/tracker-trapper.git
cd tracker-trapper
swift test
swift build -c release
scripts/package-app.sh "$(swift build -c release --show-bin-path)/TrackerTrapperMenuBar"
open dist/TrackerTrapper.app
```

If you already have a clone, use it rather than creating a second installation.
The resulting app is `dist/TrackerTrapper.app`. This is a local, unsigned and
unnotarized bundle; there is no published download installer yet.

Optionally copy the app to your user Applications folder:

```sh
mkdir -p "$HOME/Applications"
ditto dist/TrackerTrapper.app "$HOME/Applications/TrackerTrapper.app"
open "$HOME/Applications/TrackerTrapper.app"
```

Quit the earlier copy before opening another. Keep the source checkout in place:
agent MCP connections use executables inside its `.build/release` directory,
not the app bundle.

### Find it with Spotlight

For a shortcut that follows rebuilds, locate `dist/TrackerTrapper.app` in Finder,
choose **File → Make Alias**, rename the alias **Tracker Trapper**, and move it
to your home folder's `Applications` folder. Keep the original app in place.
This avoids maintaining a separate copied app. Press **Command–Space** and search
**Tracker Trapper**. Spotlight may take a moment to index the shortcut.
Once launched, use the menu-bar icon or **Command–Shift–T** to reveal the panel.

## 2. Open the panel

Click the checklist icon in the macOS menu bar or press **Command–Shift–T**.
Click the icon or use the shortcut again to close it. **Refresh** reads watched session updates and forces a GitHub state/checklist
check, with a spinner and result feedback. Local observation also runs once per second.

The panel displays issue cards, task statuses, and progress counts. See
[Panel and session features](#panel-and-session-features) for the compact controls.

Tracker Trapper has no normal Dock window. To quit, use Activity Monitor to
quit the process named `TrackerTrapper`. It does not install a login service.
For automatic launch, add your chosen app copy to **Open at Login** in macOS
System Settings (search Settings for “Login Items”); menu wording varies by
macOS version.

## 3. Track an existing GitHub issue

Authenticate GitHub CLI, then set these shell variables from the repository root.
Replace the example repository and issue number with your own:

```sh
gh auth login
gh auth status
export TT_TRACKER_TRAPPER_BIN="$PWD/.build/release/tracker-trapper"
TT_REPOSITORY='owner/repository'
TT_ISSUE_NUMBER='123'
```

The importer recognizes checklist lines with bold stable IDs and an em dash:

```markdown
- [ ] **TT-01 — Implement the change.** Check: the requested behavior works.
- [ ] **TT-02 — Verify the result.** Check: relevant checks pass with evidence.
```

Use ordinary spaces around the em dash. IDs must begin with `TT-` and remain
stable when descriptions change. Plain bullets or checkboxes without this format
will not become imported tasks. Checked items import as completed.

```sh
TT_PLAN_ID="$("$TT_TRACKER_TRAPPER_BIN" import-issue --repo "$TT_REPOSITORY" --issue "$TT_ISSUE_NUMBER" | jq -r .id)"
"$TT_TRACKER_TRAPPER_BIN" get-plan --plan-id "$TT_PLAN_ID"
```

Use the returned plan ID, not the issue URL. Inspect the returned `todos` before
starting work. Registration of the same repository/issue is idempotent and
preserves existing statuses and evidence. The current store rejects a changed
set of todo IDs on re-registration; don't casually remove or replace IDs in an
already-tracked plan.

For an issue whose body you cannot reformat, create a local JSON registration
with `repository`, `issueNumber`, `issueURL`, `title`, and a `todos` array of
`id`, `description`, and optional `acceptance`, then run
`"$TT_TRACKER_TRAPPER_BIN" register-plan --input /absolute/path/to/plan.json`.
Use the existing issue's identity; registration does not create a GitHub issue.

## 4. Report work from Terminal

Start a run for the current session. For agent work, use that agent session's
actual ID. The example below intentionally creates a separate manual run:

```sh
TT_RUN_ID="$("$TT_TRACKER_TRAPPER_BIN" start-run \
  --plan-id "$TT_PLAN_ID" \
  --agent manual \
  --session-id "manual-$(uuidgen)" \
  --repo-path "$PWD" | jq -r .id)"

"$TT_TRACKER_TRAPPER_BIN" start-task --run-id "$TT_RUN_ID" --todo-id TT-01
"$TT_TRACKER_TRAPPER_BIN" activity --run-id "$TT_RUN_ID" --message 'Checking the result'
```

Only after the task's acceptance check passes:

```sh
"$TT_TRACKER_TRAPPER_BIN" complete-task --run-id "$TT_RUN_ID" --todo-id TT-01 \
  --evidence 'Describe the actual passing check and result here'
```

If blocked, report the reason instead:

```sh
"$TT_TRACKER_TRAPPER_BIN" update-task --run-id "$TT_RUN_ID" --todo-id TT-02 \
  --status blocked --message 'Describe the dependency or decision needed'
```

Finish your own run before stopping:

```sh
"$TT_TRACKER_TRAPPER_BIN" finish-run --run-id "$TT_RUN_ID" --status paused
```

Use `finished` when the session's work is done, `waiting_for_user` when awaiting
input, or `interrupted`/`failed` when appropriate. Finishing a run does not complete
its tasks or close the GitHub issue. Start a new run when resuming; do not take
over another session's active run.

## 5. Connect Codex or Claude Code

The MCP server runs locally over stdio. There is no server URL, port, or separate
web service to deploy. Configure its **absolute executable path** after building.
From the Tracker Trapper checkout:

### Codex

```sh
codex mcp add tracker-trapper -- "$PWD/.build/release/tracker-trapper-mcp"
codex mcp list
```

If that server name already exists, inspect its configuration and update its path
instead of adding a duplicate. This setup uses Codex's local MCP configuration;
see the [official OpenAI MCP documentation](https://learn.chatgpt.com/docs/extend/mcp?surface=cli).
Restart the client or reconnect the server, then verify `get_plan` is available
in a new session. Listing a configured server alone does not prove a successful
tool call. This local executable is not a remote connector for a web-only client.

### Claude Code

```sh
claude mcp add --transport stdio --scope user tracker-trapper -- "$PWD/.build/release/tracker-trapper-mcp"
```

This makes the server available at user scope. Use your intended project/local
scope instead when appropriate. Restart/reconnect Claude Code and verify a real
`get_plan` call. Check `claude mcp add --help` for your installed version.

### Tell your agent how to report

Give the agent the issue URL and this instruction:

> Use Tracker Trapper for this issue. Retrieve its plan and stable todo IDs;
> register the agreed checklist if it is absent. Start your own session run.
> Call start_task before each todo, report activity at milestones, and call
> complete_task only after its acceptance check passes, with concrete evidence.
> Report blockers explicitly. Finish your own run with the actual status before
> stopping. Do not close the issue without the required acceptance.

The core tools are `register_plan`, `get_plan`, `start_run`, `start_task`,
`complete_task`, `update_task`, `report_activity`, and `finish_run`.
Installing MCP exposes tools; it does not make agents use them automatically.
See [Agent integrations](../Integrations/README.md) for optional hook adapters.

## 6. Synchronize progress to GitHub

Local reporting updates the app immediately. A “GitHub sync pending” count is
not proof that updates have reached GitHub. Review the proposed issue body first:

```sh
Integrations/sync-github-issue.sh --repo "$TT_REPOSITORY" \
  --issue "$TT_ISSUE_NUMBER" --plan-id "$TT_PLAN_ID" --dry-run
```

When the output is correct, run the same command without `--dry-run` to write it.
This needs `gh`, `jq`, and `TT_TRACKER_TRAPPER_BIN`. The script writes its marked
progress block, preserves unrelated issue text, and detects changes to a
previously synchronized block. Review conflicts; do not routinely use `--force`.

The current script acknowledges the shared outbox after a successful write;
therefore, an empty pending count is not per-issue proof that every issue is
synchronized. Verify each issue on GitHub when syncing multiple tracked issues.

## 7. Update, back up, or uninstall

Before replacing binaries or backing up, quit the app and stop/disconnect MCP
servers and reporting hooks that write to its store. A running MCP process keeps
using its old executable until it reconnects.

In a clean checkout, update and rebuild:

```sh
git status --short
git pull --ff-only
swift test
swift build -c release
scripts/package-app.sh "$(swift build -c release --show-bin-path)/TrackerTrapperMenuBar"
```

Preserve/reconcile local changes before pulling; don't reset them to force an
update. If you installed to `~/Applications`, copy the new bundle there again.
Open your chosen app copy and reconnect agent clients. Builds predating the
store-locking fix must not keep writing alongside current processes.

Back up the entire `~/Library/Application Support/TrackerTrapper` directory
while all writers are stopped. It contains `store.json`, lock files, and, in
session watching, `store.watchers.json`. Restore to the same location
before restarting. `TRACKER_TRAPPER_STORE` overrides the path separately for
each process; a Finder-launched app does not inherit a Terminal-only override.

To uninstall, quit the app, remove its login item if you added one, disconnect
its MCP configuration/hooks, and remove the app bundle. Keep the data directory
unless you intentionally want to erase local plan history. GitHub issues are
not deleted by uninstalling.

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| No app window or Dock icon | Look for the checklist icon in the menu bar; press ⌘⇧T. Verify the app is running in Activity Monitor. |
| Shortcut does nothing | Click the menu-bar icon; another app may own the shortcut. |
| Swift build fails immediately | Confirm Swift 6+ and the selected macOS SDK/toolchain. |
| An imported issue has no tasks | Check the exact stable-ID checklist format above and inspect `get-plan`. |
| MCP server unavailable | Check the absolute binary path, rebuild all products, and reconnect the client. Test `get_plan`. |
| The stdio server seems to hang in Terminal | It waits for JSON-RPC input; an agent MCP client normally starts it. Use the CLI for manual commands. |
| The app and CLI show different plans | Check `TRACKER_TRAPPER_STORE`, the logged-in macOS user, and whether an old app copy is running. |
| A task stays stale or incomplete | The agent must report progress; running commands alone does not prove task completion. |
| Errors or many notices | Click the bell icon for grouped notices and dismissal controls. |
| Missing `watch_session` or `nextTodoID` | Update your checkout, rebuild, and reconnect the MCP client. |
| No notification banners | Check Tracker Trapper's macOS notification permission and Focus settings. Keep the app running. |

<a id="local-development-preview"></a>

## Panel and session features

These features are included in the current source. Rebuild an older installation
and reconnect its MCP clients after updating.

- The panel fits its content and scrolls only at the available-height limit.
- Every reveal starts issue cards in remaining-only mode. Click an issue name
  to toggle all tasks; completed and skipped tasks are hidden in minimized mode.
- Click outside the panel to dismiss it. Moving the pointer outside keeps it open.
- A bell icon shows grouped notices. Click it for details and dismissal controls.
- Beside the task count, the GitHub icon opens the issue and the red **×**
  (**Stop watching**) stops its watchers and removes its card persistently.
  Starting a new run for that issue brings it back; stored history is retained.
- An explicitly selected next task gets a filled blue dot. The selection is not
  inferred from checklist order.

- Closed GitHub issues are removed from tracking automatically; history is kept.
- Newly completed tasks request a macOS notification. When an entire issue's
  checklist finishes, opening the panel plays a celebration over its blurred
  task card, then dismisses it. Existing completed imports do not trigger a party.
- GitHub refresh imports missing stable checklist IDs and checked pending tasks,
  preserving historical evidence and local completed work.

### Select the next immediate task

Use a real unfinished todo ID on the current issue:

```sh
"$TT_TRACKER_TRAPPER_BIN" set-next-task --run-id "$TT_RUN_ID" --next-todo-id TT-02
```

MCP uses `set_next_task` with `runID` and `nextTodoID`. The optional parameter is
also accepted on task and activity reports, so completing one task and nominating
the next can happen atomically. Empty string clears it; omission preserves it.
Completed/skipped/unknown next-task IDs are rejected. Completing or skipping the
selected task clears the selection. Reconnect older MCP processes to expose the
new tool and parameter.

### Link a session for background observation

Start the agent's own run, then click **Link session…** and select that session's
JSONL file, or report it explicitly:

```sh
"$TT_TRACKER_TRAPPER_BIN" watch-session --run-id "$TT_RUN_ID" \
  --source /absolute/path/to/this-session.jsonl --format codex
"$TT_TRACKER_TRAPPER_BIN" watch-status
```

Use `--format claude` for Claude logs. Verify the actual session identity before
linking; never pick a log solely because it shares a repository. Observation
starts at the file's current end, persists its cursor, and runs while the app
is open even if the panel is closed. It stops when the app quits or the run is
no longer active. Keep explicit start/completion/blocker reports as the primary
progress contract. See [watcher details](../Integrations/README.md#background-session-watcher)
for supported records, completion markers, and limitations.
