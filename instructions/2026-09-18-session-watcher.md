# TT-18 — External session observation

Build an observer in the menu-bar app that watches only session files explicitly linked to registered runs. It should update activity from new assistant messages/tool activity and accept explicit completion assertions tied to exact todo IDs. Monitor wakeups are not agent activity.

Current implementation choices:

- The installed Codex `app-server proxy` cannot connect: the shared control socket is absent. Do not start/resume another agent to observe the existing one.
- Use explicitly linked local Codex and Claude JSONL files as compatibility adapters. Their private formats can change; unsupported headers and read failures must be visible. Structured app-server subscriptions remain a future source adapter.
- Preserve provider session identity separately from the run's friendly session label. Start at EOF when linking; persist read offsets, file identity, tail fingerprints and source status separately in `store.watchers.json`.
- Read bounded chunks and wait for newline-terminated records. After replacement/truncation, verify identity and baseline at EOF rather than replay history. Preserve cursors across restarts; deterministic event IDs protect retries after a crash.
- Treat assistant prose/tool names as activity; ignore reasoning and user content. Never infer completion from tool output or a tool call's arguments. Standalone assistant assertions such as `TT-87-04: completed — tests passed` or `- [x] TT-87-04 — tests passed` are agent-reported completion evidence, not independent verification. Ignore code-fenced/quoted examples and unknown IDs.
- Source timestamps update activity; polling itself never changes agent timestamps. Completed/skipped todos, later explicit updates, and inactive runs are not overwritten by older observations.
- Provide CLI/MCP linking, status and unlinking, plus Link session / Stop watching controls and a source-status/activity summary in the app. MCP updates remain the direct reporting path.

## Implementation and verification

- [x] TT-18-01: Codex and Claude session adapters, strict completion markers, bounded incremental reads and durable checkpoints.
- [x] TT-18-02: Transactional activity/completion ingestion, source timestamps, deduplication and inactive-run protection.
- [x] TT-18-03: CLI/MCP link, unlink and status commands; menu-bar background polling and session controls.
- [x] TT-18-04: Regression tests: `swift test` passes all 17 tests with no failures. Separate-process MCP integration and watcher smoke checks pass. `git diff --check` passes.
- [x] TT-18-05: Release binaries built; packaged `dist/TrackerTrapper.app` relaunched from the Vibes checkout. Global Codex and Claude instructions include explicit session linking and fallback completion assertions.
- [x] TT-18-06: Explicitly linked verified Codex sessions for Newton #87 and #86. The running app automatically ingested #86 tool activity at 02:36:47, 02:37:03 and 02:37:05 UTC on September 18, with source offsets advancing. No polling-based activity was fabricated.
- [x] TT-18-07: #87 remained waiting for user; #86 subsequently finished through its agent. Both watchers now stop consuming because their runs are inactive. Packaged popover visually shows #87 waiting and #86 finished, 2/2.

Remaining acceptance boundaries: Claude is fixture-tested, not live-session verified. Active-run watcher controls were implemented and built but were not visually checked before #86 finished. Explicit completion ingestion passed the isolated CLI/MCP smoke test; no artificial completion was injected into real issues to demonstrate a toast. JSONL schemas are private compatibility adapters, not guaranteed provider APIs. Observation runs only while the app is open, and new MCP tools require clients to reconnect. No source commit or push performed in this implementation turn.
