# Client capability matrix

Recorded 2026-09-17 on macOS arm64 with Xcode 26.2 and Swift 6.2.3.

| Client | Installed version | Confirmed entry points | Tracker Trapper path | Current limitation |
| --- | --- | --- | --- | --- |
| Codex CLI | 0.154.0 / Luna (`gpt-5.6-luna`) | `codex exec`, JSON event output, local MCP configuration, app-server JSON-RPC, legacy `turn/plan/updated`, and native v2 `item/plan/delta` / `item/completed` plan items | `Integrations/codex-hooks.json`, `Integrations/report-codex-plan.sh`, plus explicit CLI/MCP-shaped updates | Native plan events were captured live under Luna on thread `01a0b213-784f-7690-95c9-aed077f889fa` / turn `01a0b213-78a3-7c51-a2d1-6554b6d5faac`; a separate live thread `01a0b217-a965-7c12-a0b0-617a0d33570a` proved interruption (`01a0b217-a9b7-7f40-a4f1-577586799c02`, `interrupted`) and resumption (`01a0b219-095e-7f93-9299-c8fd6ccb0ffa`) in native plan mode. |
| Claude Code | 2.1.275 | `-p`, `--output-format stream-json`, `--include-hook-events`, hook configuration, native task lifecycle documented | `Integrations/claude-settings.json` plus `Integrations/report-hook.sh` | A real Claude session on 2026-09-17 emitted `TaskCreated` and `TaskCompleted` for `[TT-01]`, and the adapter mapped them to the linked todo with completion evidence. Separate run IDs remain scoped independently; prose-only plans still use explicit CLI/MCP updates |
| Tracker Trapper | source build | Swift package, CLI, durable store, native `MenuBarExtra` target | shared `TrackerTrapperCore` actor | GitHub synchronization, MCP wire server and global hotkey are not yet implemented |

The installed client binaries, help output, app-server schema, and disposable authenticated sessions were inspected directly. Codex lifecycle delivery, live app-server turn execution, native plan deltas, and interruption/resumption are verified. Claude native task creation/completion and evidence delivery are verified; explicit registration remains the fallback for prose-only plans. TT-02, TT-07 and TT-15 retain their stronger runtime checks separately.
