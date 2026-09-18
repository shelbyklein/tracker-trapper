# Local checklists and session-scoped tracking commands

## Prompt for Claude

### Outcome and scope

Extend Tracker Trapper so a user can track a task without Git, a repository, GitHub credentials, or a GitHub issue. Tracking defaults off and never adds a startup question. Explicit tracker commands create or resume a persistent checklist for the current session. The `issue-to-work` skill opts its own session into the existing GitHub plan and run instead of creating another local plan.

This file records the implemented scope and its completion checks. The issue and Tracker Trapper evidence remain the execution record. Preserve unrelated uncommitted changes and the stable IDs below.

### Confirmed current system

Inspected 2026-09-18. Line numbers are investigation pointers; locate named functions again before editing.

- `Sources/TrackerTrapperCore/Models.swift:28`: `Plan` requires repository, issue number, and issue URL. `StoreSnapshot` is versioned JSON, currently schema version 1; this is not a SQLite implementation.
- `Sources/TrackerTrapperCore/Store.swift:22`: the default store is `~/Library/Application Support/TrackerTrapper/store.json`. `transaction` uses a cross-process file lock, reloads persisted state, and rolls back failed mutations. Reuse this path.
- `Store.swift:32`: `register` identifies an existing plan by repository and issue number. Empty or invented GitHub fields would cause incorrect identity collisions; they are not a local-plan solution.
- `Store.swift:97`: `startRun` creates a new run on every call. Automatic startup/retry requires explicit idempotency rather than repeated calls to this method.
- `Store.swift:236`: `appendEvent` currently adds events to both history and the GitHub outbox. Local history must remain durable without creating pending GitHub work.
- `Sources/TrackerTrapperCLI/main.swift:25` and `Sources/TrackerTrapperMCP/main.swift:39`: registration requires issue details. CLI/MCP task reporting, next-task selection, run lifecycle, and watcher operations already share the core store. The connected MCP catalog also exposes only GitHub-shaped registration.
- `Sources/TrackerTrapperCore/SessionWatcher.swift:31`: linking accepts an explicit JSONL path, reads its session identity, starts at EOF, and prevents duplicate active watcher ownership. Before automatic linking, verify that the source identity equals the intended run's session identity; reading a valid header alone is insufficient.
- `Sources/TrackerTrapperCore/SessionObservation.swift:63` recognizes stable completion IDs. `Integrations/report-hook.sh` and `report-codex-plan.sh` also map stable IDs; keep generated IDs compatible across adapters.
- `Sources/TrackerTrapperMenuBar/main.swift`: `checkGitHubIssues`, card labels, attention labels, GitHub links, completion/celebration views, and outbox footer assume issues. `CompletionNotice.swift:18` also formats repository/issue labels.
- `Integrations/codex-hooks.json`, `claude-settings.json`, and reporting scripts are activity adapters with configured run IDs. They do not yet implement this startup decision or persistent command preference.
- `Integrations/sync-github-issue.sh` performs explicit synchronization. Gate it before any remote access when given a local plan.
- Existing tests include core persistence, next-task, watcher, GitHub refresh, and completion behavior, plus real CLI/MCP subprocess tests in `scripts/test-mcp-integration.py` and `scripts/test-session-watcher.py`.

There is concurrent/uncommitted settings and notification work, including `Package.swift`, menu-bar source, the Mac guide, and notification service files. Reinspect status and the settings/onboarding plan before implementation. Integrate with the resulting Settings UI rather than replacing it or creating duplicate settings ownership.

### Client capability boundary

Current official documentation supports explicit Codex skill invocation. Claude Code documents `/skill-name` invocation with arguments. Exact `/tracker` support in the Codex desktop app has not been established.

- [Codex skills](https://learn.chatgpt.com/docs/build-skills): explicit `$skill` invocation provides a possible command fallback.
- [Codex developer commands](https://learn.chatgpt.com/docs/developer-commands?surface=cli): inspect the applicable client surface before claiming custom slash-command support.
- [Claude Code hooks](https://code.claude.com/docs/en/hooks) and [skills](https://code.claude.com/docs/en/skills): use supported lifecycle and command mechanisms, with installed-version checks.

First verify Codex desktop, Codex CLI, and Claude Code separately. Record exact versions, interaction mechanism, command spelling, setup, restart requirements, and headless behavior. Existing capability notes are historical, not proof of this interaction. Do not use startup hooks, Accessibility automation, transcript editing, or global keyboard interception to manufacture command support. Skill invocations are agent-mediated workflows, not proof of a native command handler.

### User-facing behavior

| Proposed command | Result |
| --- | --- |
| `/tracker on` | Create or resume tracking for the current task and bind this session. Repeating it must not duplicate a plan/run. |
| `/tracker off` | Pause this session's active run and mark this session declined. Preserve plans, evidence, and other sessions. |
| `/tracker start` | Alias of `on` for explicit current-session tracking. |
| `/tracker status` | Read-only display of current session decision, linked plan/run, and watcher/reporting health. |

These are desired command spellings. Expose them where supported. A namespaced plugin command, explicit Codex skill such as `$tracker on`, or a CLI equivalent must be described using its actual syntax. Preserve identical semantics through a single core implementation. Do not treat plain text that resembles an unsupported slash command as a guaranteed command dispatch.

Tracking remains off in every new session unless the user invokes a tracker command or an explicitly selected workflow such as `issue-to-work` opts that session in. A new fork/session never inherits another run's ownership. If the session already tracks an explicit GitHub plan, reuse that binding and do not create a local plan. Local mode does not override repository requirements to track a particular implementation issue.

For an existing local checklist in a different session, require explicit plan selection or a supplied plan ID. Never infer ownership from directory alone. If multiple candidates exist, offer a compact selection with titles and unfinished counts. An empty task, cancellation, or invalid selection leaves state unchanged.

### Data ownership and compatibility

1. **Plan source:** introduce a typed source discriminator, `local` or `github`, with GitHub identity present only for GitHub plans. Local plans have a stable opaque ID such as `local:<UUID>`, title, optional workspace path, and the existing todos/evidence/revisions. Keep source-specific display logic centralized.
2. **Migration:** decode existing records as GitHub plans, preserving every plan/run/todo/event ID, watcher linkage, next selection, progress state, and outbox entry. Back up before migration. Validate schema versions and reject unsupported future versions before mutation. Old binaries do not currently enforce this protection: require coordinated app/CLI/MCP updates and reconnection, and test that incompatible old processes cannot silently drop new fields. If that cannot be guaranteed with the current file format, choose a versioned store path with a controlled one-time migration and an explicit rollback procedure.
3. **Registration:** local identity is the explicit plan ID or a persisted creation-request key; GitHub identity retains canonical issue matching. Two local plans in the same directory are distinct. Registration retry must preserve statuses/evidence. Reject duplicate todo IDs and empty descriptions. Use compatible IDs such as `TT-LOCAL-<short-plan-token>-01`, preserving them through renames/reordering.
4. **Compatibility:** decode the retired startup preference for schema compatibility, but leave it off and do not expose a startup-question control.
5. **Session decisions:** persist a minimal binding keyed by client plus session ID: declined/accepted, optional plan/run ID, and stable creation request key. Do not store full user prompts in binding records. Serialize transitions through core transactions; competing commands must not create two plans or runs.
6. **Runs:** reuse only this session's active run. Starting a later run after pause/finish is explicit and preserves prior history. Keep workspace path metadata usable for non-Git folders; do not run `git rev-parse` to obtain required identity.
7. **Events:** local plans retain history, evidence, freshness, notifications, and watcher observation. Only GitHub plan events enter the sync outbox. Preferences and session decisions are local control state. Never clear unrelated GitHub outbox entries while processing a local plan.

### First useful slice and interfaces

First deliver a complete manual path: create a local plan from a session, update it through existing reporting calls, see it in the menu bar, and resume it without Git installed. Then add session-scoped command adapters over the same core.

Proposed new interfaces, with final names documented consistently:

- `register_local_plan` / `register-local-plan`: title, todos with acceptance checks, optional workspace path, and required stable creation request key; return the canonical plan ID. Keep existing GitHub registration backward compatible.
- `get_session_tracking`, `set_session_tracking` / `session-tracking`: inspect and record the session's decision and binding. Validate client/session identity and make retries idempotent.
- A bounded local-plan listing/filter operation for explicit resumption. Existing `get_plan`, `start_task`, `complete_task`, `report_activity`, `set_next_task`, and `finish_run` remain the reporting contract.

CLI equivalents must work without a running menu-bar UI or an MCP connection. If MCP is not ready, unavailable tooling must produce a concise, truthful diagnostic without pretending registration succeeded.

Watcher linking is optional enrichment. Use a provider-supplied transcript path and validated matching session identity; never scan for the newest file in a repository. Watcher absence does not prevent direct reporting. Reporting callbacks must exclude their own operations to prevent recursive hooks.

### Implementation checklist and completion checks

- [x] **TT-LOCAL-01 — Prove the client interaction.** Update a dated capability matrix using disposable sessions for each target client. Check command syntax/arguments, current-session binding, resume behavior, and installed skill discovery. Record unsupported slash behavior explicitly, including the usable fallback. No configuration changes to unrelated hooks.
- [x] **TT-LOCAL-02 — Add local identity and migration.** Implement source-aware models, backward decoding, safe migration/rollback, validation, and idempotent local registration. Check two plans in one non-Git folder, registration retry, retained old IDs/evidence, and incompatible-writer handling.
- [x] **TT-LOCAL-03 — Expose local reporting and isolate GitHub.** Add CLI/MCP entry points and source-aware outbox/sync behavior. Check create/start/complete/pause/resume through real subprocesses with Git and gh unavailable; mixed stores retain GitHub synchronization behavior without remote access for local plans.
- [x] **TT-LOCAL-04 — Display local plans.** Update cards, headers, links, notifications, accessibility, celebrations, empty states, and footer. Check local plans show a Local label and optional folder, no fabricated issue number/link, no pending-sync warning; existing GitHub cards and completion behavior still work.
- [x] **TT-LOCAL-05 — Persist session choices.** Implement binding APIs through the canonical core authority. Check restart persistence, simultaneous clients, accepted/declined choices, idempotent run ownership, and explicit plan selection on cross-session resume.
- [x] **TT-LOCAL-06 — Add session command adapters.** Package manually invoked command/skill workflows and update `issue-to-work` to opt in its current session. Check on/off/start/status, no startup question, and no duplicate plan/run on repeated start. Demonstrate supported command syntax per client.
- [x] **TT-LOCAL-07 — Verify reporting lifecycle and recovery.** Check acceptance then registration failure/retry, interrupted sessions, restarted MCP, matched and mismatched watcher identity, no recursive reporting, and accurate unfinished todos after session end. No completion inferred from silence, files changing, or successful hook execution.
- [x] **TT-LOCAL-08 — Complete installed-client acceptance and documentation.** Test the real packaged app and each supported client in a non-Git directory. Document setup, session scope, exact commands, data location, backup/rollback, disable/uninstall, and remaining limitations. Report build, automated checks, installed runtime, client acceptance, and user acceptance separately.

Dependency order: 01 establishes integration feasibility; 02 → 03 → 04 delivers the manual local path; 05 → 06 adds explicit session opt-in; 07 → 08 completes acceptance. Keep unresolved client requirements visible even if core work passes.

### Regression tests and verification

Use real core/CLI/MCP entry points with isolated fixture stores. Never run migration or destructive fixture checks against live data.

- Round-trip a legacy mixed-state fixture through migration/restart; compare identifiers, progress/evidence, next-task choice, runs, watcher references, and queued GitHub work.
- Race duplicate acceptance/registration requests across processes. Assert one decision, one intended plan, and one active session run. Different sessions in the same folder remain distinct.
- Exercise on, off, repeated start, resumed session, new fork, and explicit GitHub binding. Status is read-only. On/off changes do not complete tasks or delete plans.
- Spy on process launches/network boundaries: local registration, reporting, refresh, and sync rejection invoke neither Git nor gh. Local events never inflate the outbox. Test mixed stores.
- Test exact source-to-run session identity during watcher linking and preserve EOF/no-history behavior. Keep direct reporting available with no transcript.
- Verify a declined session creates no plan or watcher. Tooling errors leave an actionable retry state, not false success.
- Retain GitHub registration/refresh/sync, next-task, notification deduplication, and completion/celebration regression coverage. Check local labels with keyboard and VoiceOver.

Run focused tests as changes land, then:

```sh
swift test
swift build -c release
/usr/bin/python3 scripts/test-mcp-integration.py .build/release/tracker-trapper-mcp
/usr/bin/python3 scripts/test-session-watcher.py .build/release/tracker-trapper .build/release/tracker-trapper-mcp
```

After authorized packaging/install, use `scripts/package-app.sh` with the built menu-bar executable and exercise both local and GitHub cards. Capture dated, redacted evidence of each command, persistence across relaunch, and progress received from each claimed supported client. Script fixtures and documentation availability do not count as installed-client proof.

### Follow-ons and exclusions

Later: explicit conversion of a local plan to a GitHub issue and additional clients. Retain the existing Stop watching controls separately from session opt-out.

Do not add cloud sync, accounts, public collectors, auto-created GitHub issues, arbitrary transcript discovery, inferred completion, or a replacement chat client. Disabling/uninstalling the integration preserves local plans and evidence. Installing from source may require development tools; using installed local tracking must not require a Git repository or GitHub account.
