# Tracker Trapper acceptance record

Recorded 2026-09-17 on the target Mac (macOS arm64, Xcode 26.2, Swift 6.2.3).

## Versioned implementation

- Repository: `shelbyklein/tracker-trapper`
- Latest completed implementation before this acceptance pass: `b80cd9b`
- Working-tree changes in this pass: native Codex v2 plan adapter documentation and capability evidence; these remain to be committed after review.
- Codex CLI: `0.154.0`, model `gpt-5.6-luna`
- Claude Code: `2.1.275`

## Acceptance evidence

- Fixture/persistence: `swift test` passed 7/7, including restart persistence, duplicate-event idempotency, changed-ID conflict rejection, unresolved-run reconciliation, and registration retry recovery.
- Build: release products `tracker-trapper`, `tracker-trapper-mcp`, and `TrackerTrapperMenuBar` built successfully. Integration shell syntax and JSON configuration validation passed.
- Claude adapter: a real Claude session emitted `TaskCreated` and `TaskCompleted` for `[TT-01]`; `report-hook.sh` mapped both events to the linked todo with evidence.
- Codex adapter: Luna app-server emitted native `item/plan/delta` and `item/completed` events in thread `01a0b213-784f-7690-95c9-aed077f889fa`, turn `01a0b213-78a3-7c51-a2d1-6554b6d5faac`. The adapter consumes completed native plan text, matches stable IDs, and leaves status-free items as activity.
- Interruption/resumption: thread `01a0b217-a965-7c12-a0b0-617a0d33570a` turn `01a0b217-a9b7-7f40-a4f1-577586799c02` completed with `status: interrupted`; a subsequent turn `01a0b219-095e-7f93-9299-c8fd6ccb0ffa` resumed on the same thread and emitted native plan deltas.
- Packaged runtime: `scripts/package-app.sh` produced and launched the `LSUIElement` app against a temporary store. The live popover showed two concurrent plans, a long title, accurate counts, blocker, agent/run status, issue link, attention state, and separate activity/task freshness; `⌘⇧T` opened it.
- GitHub synchronization: issue #1 was imported with 16 stable IDs; synchronization updated only the owned checklist block, preserved unrelated body text, recorded the sync hash, and refused a deliberate remote block conflict before forced recovery. Outbox/retry behavior was verified with a fake `gh` integration.

## State classification

- Implemented and tested: core store, CLI/MCP surface, Claude/Codex adapters, menu-bar UI, GitHub import/sync, retry and conflict handling.
- Runtime-verified: packaged unsigned app, global hotkey, popover rendering, native agent event capture, interruption/resumption.
- User acceptance: technical acceptance is complete; final product sign-off and public distribution are still a user decision.
- Distribution: bundle is unsigned and unnotarized. Login-item registration, remote agents, webhooks, network listeners, and public distribution remain deferred.
