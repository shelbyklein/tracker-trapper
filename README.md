# Tracker Trapper

A macOS menu-bar companion for GitHub-issue-linked development checklists and live agent progress.

The first vertical slice provides a durable local plan store, an explicit CLI/MCP-shaped JSON interface, and a native SwiftUI menu-bar app. The [implementation plan](instructions/2026-09-17-menu-bar-progress-tracker.md) remains the source for the full adapter and GitHub synchronization roadmap; [issue #1](https://github.com/shelbyklein/tracker-trapper/issues/1) is the execution checklist.

## Build and run

```sh
swift test
swift run tracker-trapper --help
swift run tracker-trapper register-plan --input plan.json
swift run tracker-trapper get-plan --plan-id <id>
swift run TrackerTrapperMenuBar
```

The store defaults to `~/Library/Application Support/TrackerTrapper/store.json`. Override it with `TRACKER_TRAPPER_STORE` for tests or separate environments. The CLI uses a local JSON protocol on stdin/stdout for automation and does not place credentials in the store.
