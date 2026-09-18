# Tracker Trapper

A macOS menu-bar companion for GitHub-issue-linked development checklists and live agent progress.

The first vertical slice provides a durable local plan store, an explicit CLI/MCP-shaped JSON interface, and a native SwiftUI menu-bar app. The [implementation plan](instructions/2026-09-17-menu-bar-progress-tracker.md) remains the source for the full adapter and GitHub synchronization roadmap; [issue #1](https://github.com/shelbyklein/tracker-trapper/issues/1) is the execution checklist.

## Build and run

```sh
swift test
swift run tracker-trapper --help
swift run tracker-trapper-mcp
swift run tracker-trapper register-plan --input plan.json
swift run tracker-trapper import-issue --repo owner/name --issue 123
swift run tracker-trapper create-issue --repo owner/name --title "Title" --body-file plan.md
swift run tracker-trapper retry-registrations
swift run tracker-trapper get-plan --plan-id <id>
swift run TrackerTrapperMenuBar
swift build -c release --product TrackerTrapperMenuBar
scripts/package-app.sh
```

The store defaults to `~/Library/Application Support/TrackerTrapper/store.json`. Override it with `TRACKER_TRAPPER_STORE` for tests or separate environments. The CLI and stdio MCP server use the same actor-backed service and do not place credentials in the store.

All processes coordinate through a `store.json.lock` sidecar: each operation locks, reloads the current file, and commits changes atomically. Keep the lock file in place while the app or connectors are running. The popover reloads once per second and on Refresh; read failures retain the last visible state and display an error. MCP tool calls return standard text content plus structured results.

After upgrading, reconnect/restart existing MCP clients so they launch the new binary. Older running servers do not participate in file locking and must not continue writing alongside the updated version. Restart the menu-bar app as well.

Regression checks: `swift test` and `python3 scripts/test-mcp-integration.py .build/release/tracker-trapper-mcp` after a release build. The integration check uses temporary storage and four separate MCP processes.

`create-issue` is explicit: it creates the GitHub issue, imports its stable `TT-xx` checklist, and registers it locally. If GitHub succeeds but local registration fails, the attempt is retained in the store and can be retried with `retry-registrations` or the printed `import-issue` command. Repeating registration for the same repository and issue is idempotent.

To synchronize the tracker-owned checklist block for an issue, set `TT_TRACKER_TRAPPER_BIN` to the built CLI and run `Integrations/sync-github-issue.sh --repo owner/name --issue 123 --plan-id <id> --dry-run` first. The script uses `gh` authentication, changes only its marked block, preserves unrelated issue content, and refuses to overwrite a changed tracker block unless `--force` is supplied.

The menu-bar executable is a manual-login utility in this first release. Launch-at-login registration and a global summon shortcut remain open acceptance work; the normal menu-bar click is available once the app is running.

## Local release handoff

`scripts/package-app.sh` creates `dist/TrackerTrapper.app` with `LSUIElement=true`; open it from Finder or with `open dist/TrackerTrapper.app`. This local bundle is unsigned and unnotarized. Distribution signing, notarization, and a login-item installer are separate release work.

The store lives at `~/Library/Application Support/TrackerTrapper/store.json`. Back it up by copying that file while the app is stopped, and restore it before relaunching. Removing or disabling the app does not remove the store; delete that file separately only when the user intends to erase local history. GitHub credentials are supplied by `gh` and are never written into plan files, the event store, or hook output.
