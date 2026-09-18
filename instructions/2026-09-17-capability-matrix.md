# Client capability matrix

Recorded 2026-09-17 on macOS arm64 with Xcode 26.2 and Swift 6.2.3.

| Client | Installed version | Confirmed entry points | Tracker Trapper path | Current limitation |
| --- | --- | --- | --- | --- |
| Codex CLI | 0.154.0 | `codex exec`, JSON event output, local MCP configuration, hook documentation for `PostToolUse`/`Stop` | `Integrations/codex-hooks.json` plus explicit CLI/MCP-shaped updates | Hook configuration is not installed globally; actual live hook delivery requires a trusted local hook setup and a real agent run |
| Claude Code | 2.1.275 | `-p`, `--output-format stream-json`, `--include-hook-events`, hook configuration, native task lifecycle documented | `Integrations/claude-settings.json` plus explicit CLI updates | Actual live delivery requires a configured session and credentials; prose plans still require explicit registration |
| Tracker Trapper | source build | Swift package, CLI, durable store, native `MenuBarExtra` target | shared `TrackerTrapperCore` actor | GitHub synchronization, MCP wire server and global hotkey are not yet implemented |

The installed client binaries and their help output were inspected directly. This establishes executable discovery and available entry points; it does not claim an authenticated agent run or live hook delivery. TT-02 and TT-15 must retain that runtime evidence separately.
