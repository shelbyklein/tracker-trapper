# Client capability matrix

Recorded 2026-09-17 on macOS arm64 with Xcode 26.2 and Swift 6.2.3.

| Client | Installed version | Confirmed entry points | Tracker Trapper path | Current limitation |
| --- | --- | --- | --- | --- |
| Codex CLI | 0.154.0 | `codex exec`, JSON event output, local MCP configuration, app-server JSON-RPC, and native `turn/plan/updated` schema | `Integrations/codex-hooks.json`, `Integrations/report-codex-plan.sh`, plus explicit CLI/MCP-shaped updates | A disposable authenticated session on 2026-09-17 produced a real `Codex live hook` activity event. The installed app-server schema confirms native plan notifications and the adapter fixture maps them; a live interactive plan notification and resume correlation remain TT-07 acceptance work |
| Claude Code | 2.1.275 | `-p`, `--output-format stream-json`, `--include-hook-events`, hook configuration, native task lifecycle documented | `Integrations/claude-settings.json` plus `Integrations/report-hook.sh` | A real Claude session on 2026-09-17 emitted `TaskCreated` and `TaskCompleted` for `[TT-01]`, and the adapter mapped them to the linked todo with completion evidence. Separate run IDs remain scoped independently; prose-only plans still use explicit CLI/MCP updates |
| Tracker Trapper | source build | Swift package, CLI, durable store, native `MenuBarExtra` target | shared `TrackerTrapperCore` actor | GitHub synchronization, MCP wire server and global hotkey are not yet implemented |

The installed client binaries, help output, app-server schema, and disposable authenticated sessions were inspected directly. Codex lifecycle delivery is verified and the app-server plan adapter is fixture-tested, but a live interactive native plan notification was not observed. Claude native task creation/completion and evidence delivery are verified; explicit registration remains the fallback for prose-only plans. TT-02, TT-07 and TT-15 retain their stronger runtime checks separately.
