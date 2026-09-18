# Tracker Trapper implementation plan

<!-- tracker-trapper:menu-bar-progress:v1 -->

Date: 2026-09-17
Repository: https://github.com/shelbyklein/tracker-trapper
Tracking issue: https://github.com/shelbyklein/tracker-trapper/issues/1
Status: implementation in progress; local core and menu-bar shell built, agent/GitHub runtime acceptance remains.

## Outcome

Build a small macOS menu-bar application that displays persistent, GitHub-issue-linked development plans as agents work. Creating a plan through the integrated planning workflow registers the issue and todos automatically. Clicking the menu-bar icon or a configurable keyboard shortcut reveals active issues, the current task, completed/remaining tasks, blockers, evidence, and update freshness. A later agent session can resume the same plan.

The immediate problem is that plans and issue checklists are created but lose continuity during implementation. A visible checklist alone will not solve this: registration, updates, reconciliation, and persistence must be part of the agent workflow.

## Evidence

On 2026-09-17, GitHub reported an empty default branch and no existing issues for this repository. The supplied local directory was empty and was cloned from the requested repository. There is no existing application source, architecture, or test suite to extend.

Documentation reviewed during the preceding research supports the following integration candidates; the installed-client matrix is recorded in `instructions/2026-09-17-capability-matrix.md` and still distinguishes executable discovery from authenticated runtime acceptance:

- Apple SwiftUI `MenuBarExtra` supports a persistent menu-bar control and window-style content: https://developer.apple.com/documentation/swiftui/menubarextra
- Codex hooks document lifecycle events and observation of local function tools such as `update_plan`. Specialized paths may bypass hooks; transcripts are not a stable interface: https://learn.chatgpt.com/docs/hooks
- Codex supports local MCP servers: https://learn.chatgpt.com/docs/extend/mcp?surface=cli
- Codex App Server emits `turn/plan/updated`. This does not establish permission or ability to observe arbitrary existing desktop sessions: https://learn.chatgpt.com/docs/app-server
- Claude Code documents task and tool lifecycle hooks. Native task events require use of the corresponding task tools: https://code.claude.com/docs/en/hooks
- GitHub supports issue/comment reads and updates: https://docs.github.com/en/rest/issues/issues and https://docs.github.com/en/rest/issues/comments

## Scope and architecture

Working baseline: macOS first; SwiftUI menu-bar UI, local background service, SQLite persistence, and a small CLI/MCP bridge. The exact packaging and minimum OS version must be established against the available toolchain in TT-01/TT-03. No model API is required merely to store or display progress.

Data flow: planning workflow or agent adapter -> local service -> durable events and current state -> menu-bar UI. A GitHub synchronization worker exchanges deliberate plan/checklist updates with GitHub. Start with polling/reconciliation for registered issues; do not require an internet-facing webhook receiver.

The service owns local writes and event ordering. Agents send structured updates through MCP or the CLI; they do not edit SQLite directly. Use an authenticated loopback endpoint or a user-restricted local socket. Keep GitHub credentials in the OS credential store or an explicitly supported existing credential provider, never in plan files or logs.

Core records:

- Plan: stable plan ID, canonical GitHub host/repository/issue identity, title, revision, source location and source revision.
- Todo: stable ID, parent ID if applicable, description, status, acceptance check, dependencies, evidence and revision. Renames and reordering retain identity.
- Run: agent/client version, session ID, repository/worktree, linked plan, start/end state, activity timestamp and task-update timestamp.
- Event: unique event ID, run ID, todo ID where applicable, source, timestamp and expected revision. Duplicate retries must not duplicate changes.

Persistent issue todos and temporary per-turn agent plans are distinct. A native plan update maps to stable todos explicitly; an unmatched or rewritten step must not silently replace the issue plan or reopen completed work.

### Ownership, lifecycle and recovery

- Todo states: pending, in_progress, blocked, completed, skipped. Skipping requires a reason and does not count as completed.
- Run states: active, waiting_for_user, paused, interrupted, finished, failed. Display stale/unknown freshness separately; silence alone cannot prove failure or a blocker.
- Agent-reported completion and independently observed verification are separate fields. Shell activity, a successful tool call, or a closed GitHub issue cannot by itself verify a todo's acceptance criteria.
- Session/turn completion triggers reconciliation, not automatic checklist completion. Report unresolved todos and permit legitimate pause/interruption without an endless continuation loop.
- Registration is idempotent. If GitHub creation succeeds but local registration fails, retry registration using the existing issue; never create another issue blindly.
- A durable outbox retains updates across UI closure, service restart, network failure and sleep/wake. Retry transient failures with bounded exponential backoff; expose authentication or persistent failures and a manual retry action.
- Concurrent updates use revisions and explicit conflict reporting. Preserve human edits to GitHub content; reread before writing and confine automated updates to a designated section or tracker-owned comment. GitHub and SQLite do not form an atomic transaction; avoid claims of conflict-free two-way editing.
- Uninstalling/disabling integrations must leave plans readable and preserve user data. Remote/cloud agents require a separate transport design and are deferred.

## Todos

The GitHub tracking issue is the authoritative execution checklist for this plan. These stable IDs define deliverables and completion checks. Initial unchecked boxes below are the planning baseline; future progress lives in the issue to avoid two competing checklists.

### Phase 1 — Prove the integration

- [ ] **TT-01 — Verify actual client capabilities.** Record installed macOS/toolchain, Codex and Claude Code versions; test lifecycle and native plan/task hooks in disposable sessions. Check: a capability matrix identifies working events, missing events, setup/trust requirements, and fallback behavior for each tested client.
- [ ] **TT-02 — Prove one issue-to-progress round trip.** Register a real test issue and three stable todos using a minimal collector/CLI; send start, complete, interruption and resume events. Check: issue identity and progress survive collector restart and duplicate event delivery; capture actual client evidence separately from fixtures. Use TT-01 results before choosing adapter paths.

### Phase 2 — Durable local core

- [x] **TT-03 — Scaffold the application and service.** Establish source layout, minimum OS, reproducible build/run commands, service lifecycle and launch-at-login choice. Check: a fresh checkout builds and starts a menu-bar shell and local service; closing the popover does not lose collection. Evidence: commit `10f01f81fe585dce92d534e9e0a450ee23adf535`, `swift build --product TrackerTrapperMenuBar`, and `scripts/package-app.sh` produced a valid `LSUIElement` bundle. First release behavior is documented as manual launch; login-item registration is explicitly deferred.
- [x] **TT-04 — Implement the plan/event model and persistence.** Add schema migrations, stable IDs, revisions, task/run state validation, evidence and separate freshness timestamps. Check: restart/replay preserves state; duplicate and out-of-order events do not corrupt progress; simultaneous worktrees remain distinguishable. Evidence: commit `73ac597c75f5ce11c6c3d2e8d803ac40a4fc0098`, `swift test` (3 passing tests), and the CLI round trip using a temporary store on 2026-09-17. The current durable backend is an atomic JSON event/state store; SQLite remains a future migration if query volume requires it.
- [x] **TT-05 — Implement the CLI and MCP interface.** Provide register_plan, get_plan, start_task, complete_task, report_blocker and run lifecycle operations through shared service validation. Check: both interfaces update the same records, reject invalid IDs/revisions, and return useful errors; unauthorized local requests fail. Evidence: commit `88492e2927986642097884bd4d0fe7311edeab8f` provides the CLI and stdio MCP server; a live JSON-RPC initialize/tools-list exchange passed, and the shared store tests cover invalid todo/plan lookup paths. The current local transport is intentionally stdio-scoped; no network listener is exposed.

### Phase 3 — Make reporting part of the workflow

- [ ] **TT-06 — Integrate planning and resumption.** Add an explicitly invoked planning workflow that registers an existing/new issue and its todos, queues retryable failures, and loads the persistent plan when implementation resumes. Check: rerunning registration creates no duplicates and a new session retrieves completed and remaining tasks without chat history. The current `import-issue` path proves existing-issue registration and idempotent reimport; new-issue creation and complete registration retry workflow remain open.
- [ ] **TT-07 — Implement the Codex adapter.** Package documented hooks and MCP/CLI instructions; capture supported plan and lifecycle events with run/issue correlation. Check: the installed target client demonstrates plan updates, interruption and resumption; unsupported paths are surfaced and have an explicit-reporting fallback. Exclude the adapter's own reporting calls from recursive hook forwarding.
- [ ] **TT-08 — Implement the Claude Code adapter.** Map observed native task changes and lifecycle events to the shared model; support explicit registration for prose-only plans. Check: a real session creates/updates linked todos, pauses and resumes without conflating native task IDs across sessions or duplicating completion events.
- [ ] **TT-09 — Implement completion reconciliation.** Compare run outcomes with outstanding todos; require evidence or a clear agent-reported status and expose unresolved work. Check: a session ending with open tasks produces an incomplete-work state; user interruptions remain interruptions, and reconciliation cannot enter an unbounded continuation loop.

### Phase 4 — Menu-bar experience

- [ ] **TT-10 — Build the progress popover.** Show active issues, task counts, current work, blockers, agent identity, evidence and separate activity/task freshness. Add issue links, issue selection and keyboard summon. Check: two concurrent issues are navigable; completed/skipped counts are accurate; keyboard and VoiceOver navigation work; long task titles remain readable.
- [ ] **TT-11 — Add useful attention states.** Show waiting-for-user, interrupted, stale/unknown and completion states; notify only on meaningful transitions with user controls. Check: quiet work produces no repeated notifications, stale work is never labeled complete, and sleep/wake does not generate a notification flood.

### Phase 5 — GitHub synchronization

- [ ] **TT-12 — Import and synchronize registered issue plans.** Support checklist import with persistent ID mapping, scoped credentials, a designated synchronization section/comment, and queued updates. Check: completed tasks persist to GitHub; human edits elsewhere survive; simultaneous remote edits produce reconciliation/conflict handling instead of blind whole-body overwrite; comments are updated rather than posted for every event.
- [ ] **TT-13 — Expose sync and recovery status.** Add outbox retry/backoff, offline state, credential-expiry handling and manual retry. Check: offline updates survive restart and sync once on reconnection; auth failures stop retry storms; UI distinguishes saved locally from synchronized to GitHub.

### Phase 6 — Acceptance and handoff

- [ ] **TT-14 — Validate failure and concurrency paths.** Exercise real CLI/MCP entry points for duplicate delivery, revision conflicts, task rename/reorder, two sessions on one issue, crash/restart and corrupted/invalid input. Check: targeted automated tests protect observable behavior; storage migrations and recovery are documented.
- [ ] **TT-15 — Complete real end-to-end acceptance.** Run a real issue through planning, both supported agent adapters, progress display, interruption/resumption and GitHub synchronization. Check: retain a dated evidence record with exact versions and observed outcomes; distinguish fixture tests, build success, installed runtime and user acceptance.
- [ ] **TT-16 — Package and document the first release.** Provide installation/build instructions, adapter setup and removal, credential handling, local data location, export/backup and recovery guidance. Check: install/launch the packaged app on the target Mac and exercise the checklist; record signing/notarization status honestly and verify disable/uninstall preserves data. Public distribution is a separate decision.

Sequence: TT-01 -> TT-02 -> TT-03/04/05 -> TT-06/07/08/09 -> TT-10/11 -> TT-12/13 -> TT-14/15/16. Schema and UI work can overlap once the event contract is stable. Do not claim adapter compatibility before TT-01 and actual adapter acceptance.

## Progress reporting rules

For each implementation session:

1. Read this plan, the linked issue and repository instructions. Identify the todo IDs being worked on and retain the previous completed state.
2. Record a session-start update on the issue with the selected IDs and any blockers. Until the app exists, maintain one progress comment per session instead of commenting on every tool call.
3. Keep checkboxes unchecked while work is in progress or blocked. Update the progress comment with current IDs, evidence and next steps at meaningful milestones.
4. Check a todo only when its stated completion check has passed. Include the relevant commit/PR and test/runtime evidence in the progress comment. “Implemented but untested” remains unchecked.
5. On stopping, state completed IDs, remaining/in-progress IDs, blockers and exact resumption steps. A paused session is not a completed issue.
6. If scope changes, preserve existing IDs and history; add new IDs and explain superseded work. Close the issue only after delivery/acceptance gates pass or after an explicit cancellation decision.

Suggested progress comment fields: Session/date; agent/version; current todo IDs; completed IDs; evidence; blockers; next action. Once Tracker Trapper is operational, use its reporting interface for this same workflow.

## Acceptance and delivery gates

- A plan created through the integrated workflow appears without manual retyping, with the correct issue link and stable todos.
- Accepted local events appear in an open widget within a target of two seconds under normal local conditions; measure this rather than assume it.
- Closing/reopening the popover, restarting the service, interrupting an agent and resuming in another session preserve the plan.
- Two projects and two runs on one issue never overwrite each other's identity or silently lose conflicting updates.
- An ended or silent agent cannot falsely complete remaining work. Agent claims, test evidence and GitHub sync state are distinguishable.
- GitHub outages do not lose local progress or block coding; eventual synchronization preserves unrelated human edits.
- Report build, automated tests, installed runtime, real-agent acceptance and packaging/signing as separate gates.

Rollout: prove the collector on disposable work, then enable one repository, then a second concurrent project. Disable adapters and login service to roll back; retain/export the database and GitHub plan. Back up the database before schema migrations and document recovery before release.

## Open questions and deferred work

Working assumptions are macOS first, local agents first, one user, and an explicit integrated planning command/skill as the registration trigger. Arbitrary plans written in any chat are not automatically discoverable. Verify preferred installed clients and credential workflow during TT-01.

Before consequential implementation choices, resolve: minimum supported macOS; distribution outside the user's Mac; which issue section/comment owns synchronized progress; whether future users need cross-platform support. Tauri is an alternative if cross-platform distribution becomes a requirement; it is not part of this baseline.

Deferred: remote/cloud agent relay, team accounts, public webhook hosting, autonomous issue dispatch, building a replacement agent chat client, parsing private transcript formats as the primary integration, inferred completion from file activity, and automatic production deployment.
