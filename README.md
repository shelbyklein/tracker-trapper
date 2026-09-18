# Tracker Trapper

A macOS menu-bar app for following GitHub issue checklists and agent progress.
The app, command-line tool, and local MCP server share one persistent store.

**[Install and use Tracker Trapper on your Mac →](docs/mac-guide.md)**

The guide covers building the app, connecting Codex or Claude Code, importing an
issue, reporting progress, updating, backups, and troubleshooting.

## Quick start

You need macOS 13 or later, a Swift 6 toolchain, and Git. GitHub operations also
need the GitHub CLI (`gh`) authenticated to an account with repository access.
The guide's examples and sync script use `jq`. Apple Silicon has been tested;
Intel Macs have not been runtime-verified. There is no published installer or
signed/notarized release bundle yet; installation is from source.

```sh
git clone https://github.com/shelbyklein/tracker-trapper.git
cd tracker-trapper
swift test
swift build -c release
scripts/package-app.sh "$(swift build -c release --show-bin-path)/TrackerTrapperMenuBar"
open dist/TrackerTrapper.app
```

Click the checklist icon in the menu bar, or press **⌘⇧T**, to show or hide the
panel. Keep the app running to refresh progress. There is no automatic login
service; see the guide for starting it at login yourself.

## What is available?

The published source provides the menu-bar panel, stable issue/todo IDs,
CLI and stdio MCP reporting, durable local progress, hook adapters, and an
explicit GitHub synchronization script.

The content-sized panel, remaining-only cards, notification bell, background
session watcher, explicit next-task blue dot, completion celebrations, GitHub
checklist refresh, and **Stop watching** card removal are included in source.
See the guide's [panel and session features](docs/mac-guide.md#panel-and-session-features).

## More information

- [Mac installation and usage guide](docs/mac-guide.md)
- [Agent integrations and hook adapters](Integrations/README.md)
- [Implementation plan](instructions/2026-09-17-menu-bar-progress-tracker.md)
- [Tracking issue #1](https://github.com/shelbyklein/tracker-trapper/issues/1)

Local data lives at `~/Library/Application Support/TrackerTrapper/store.json`.
`TRACKER_TRAPPER_STORE` selects a different store for tests or separate setups.
GitHub authentication stays with `gh`; no GitHub token belongs in a plan file.
