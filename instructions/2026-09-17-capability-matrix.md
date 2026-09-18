# Client capability matrix

Recorded 2026-09-17 on macOS arm64 with Xcode 26.2 and Swift 6.2.3.

| Client | Installed version | Confirmed entry points | Tracker Trapper path | Current limitation |
| --- | --- | --- | --- | --- |
| Codex CLI | 0.154.0 | `codex exec`, JSON event output, local MCP configuration, hook documentation for `PostToolUse`/`Stop` | `Integrations/codex-hooks.json` plus explicit CLI/MCP-shaped updates | A disposable authenticated session on 2026-09-17 produced a real `Codex live hook` activity event. Native plan update mapping and resume correlation remain TT-07 acceptance work |
| Claude Code | 2.1.275 | `-p`, `--output-format stream-json`, `--include-hook-events`, hook configuration, native task lifecycle documented | `Integrations/claude-settings.json` plus explicit CLI updates | A disposable authenticated session on 2026-09-17 produced a real `Claude turn stopped` activity event. Native task event mapping and resume correlation remain TT-08 acceptance work |
| Tracker Trapper | source build | Swift package, CLI, durable store, native `MenuBarExtra` target | shared `TrackerTrapperCore` actor | GitHub synchronization, MCP wire server and global hotkey are not yet implemented |

The installed client binaries, help output, and disposable authenticated sessions were inspected directly. The sessions verify lifecycle hook delivery into the collector; they did not yet exercise native multi-step plans, task completion evidence, or resume across separate agent sessions. TT-02, TT-07, TT-08 and TT-15 must retain those stronger runtime checks separately.
