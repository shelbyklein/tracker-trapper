# Client capability matrix

Recorded 2026-09-17 on macOS arm64 with Xcode 26.2 and Swift 6.2.3.

| Client | Installed version | Confirmed entry points | Tracker Trapper path | Current limitation |
| --- | --- | --- | --- | --- |
| Codex CLI | 0.154.0 | `codex exec`, JSON event output, local MCP configuration, hook documentation for `PostToolUse`/`Stop` and `update_plan` matching | `Integrations/codex-hooks.json` plus explicit CLI/MCP-shaped updates | A disposable authenticated session on 2026-09-17 produced a real `Codex live hook` activity event. A later plan-request probe produced only the stop event; native `update_plan` capture and resume correlation remain TT-07 acceptance work |
| Claude Code | 2.1.275 | `-p`, `--output-format stream-json`, `--include-hook-events`, hook configuration, native task lifecycle documented | `Integrations/claude-settings.json` plus `Integrations/report-hook.sh` | A real Claude session on 2026-09-17 emitted `TaskCreated` and `TaskCompleted` for `[TT-01]`, and the adapter mapped them to the linked todo with completion evidence. Separate run IDs remain scoped independently; prose-only plans still use explicit CLI/MCP updates |
| Tracker Trapper | source build | Swift package, CLI, durable store, native `MenuBarExtra` target | shared `TrackerTrapperCore` actor | GitHub synchronization, MCP wire server and global hotkey are not yet implemented |

The installed client binaries, help output, and disposable authenticated sessions were inspected directly. Codex lifecycle delivery is verified, but native `update_plan` capture was not observed. Claude native task creation/completion and evidence delivery are verified; explicit registration remains the fallback for prose-only plans. TT-02, TT-07 and TT-15 retain their stronger runtime checks separately.
