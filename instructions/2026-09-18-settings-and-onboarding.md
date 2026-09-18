# Settings, notification diagnostics, and guided setup

## Prompt for Claude

### Outcome

Give Tracker Trapper a usable Settings window and resumable setup checklist. Users must be able to understand why notifications are missing, enable them, test them without altering real work, and verify that an agent is reporting to the application. This is a proposed implementation plan, not implemented behavior.

### Current system and evidence

- `Sources/TrackerTrapperMenuBar/main.swift:12` declares an empty Settings scene. The app is an accessory/menu-bar application, with a fixed Command-Shift-T shortcut and no built-in login-item control.
- `AppDelegate.applicationDidFinishLaunching` requests alert/sound authorization at startup and ignores both the boolean and error. The delegate already enables foreground banners/list/sound and opens the panel on notification clicks.
- `MenuModel.refresh` polls once per second for the app lifetime. It compares visible snapshots using `CompletionNotice.changes`, groups completions by issue, suppresses initial imports/restarts, and deduplicates attention transitions.
- `MenuModel.deliverNotification` submits a local notification but does not report errors or inspect authorization. `attentionKeys` includes waiting-for-user, interrupted, failed, and stale runs, but not blocked todos. The bell contains current notices/errors; it is not a persistent delivery history.
- `Sources/TrackerTrapperCore/CompletionNotice.swift` and its tests are the canonical completion comparison path. Preserve their no-repeat and no-historical-import semantics.
- `docs/mac-guide.md` and `Integrations/README.md` describe manual installation, MCP connection, GitHub authentication, explicit agent reporting, optional session watching, and explicit GitHub write-back. Setup is currently documentation-led. The bundle is locally built and unsigned/unnotarized.
- The local app is running and matches the release executable. Its real notification authorization, successful submission, and visible banner presentation have not been measured. Do not report a confirmed root cause based on these code gaps alone.

### Ownership

Keep user preferences and setup-dismissal/version state in a typed UserDefaults-backed preferences object. Do not put them in issue todos or run status. Query macOS for notification authorization and presentation settings; never persist a boolean that claims to override system permission. Keep notification submission/error diagnostics bounded and local, excluding task descriptions and session transcripts from exported diagnostics by default. TrackerStore remains the authority for issues, runs and progress. Connection health must derive from actual observations, not the existence of configuration text.

### First slice

Add an accessible gear button to the panel that opens a real Settings window, with General, Notifications, Connections & Setup, and About & Diagnostics sections. Make the settings window work on macOS 13 and later; do not assume newer SwiftUI settings-opening APIs are available. Provide a discoverable Quit action.

Notifications is the first implementation priority. Show system authorization, alert and sound settings, app-level notification enablement, last submission outcome and timestamp. Provide Enable Notifications when authorization is not determined, Open macOS Notification Settings, and Send Test Notification. Refresh settings on window activation and after permission requests. If an app-specific Settings deep link is unsupported, fall back to System Settings with plain-English navigation instructions. Do not rely on an undocumented URL without checking it on the supported OS.

Use one injectable notification service for normal events and tests. Handle authorization and submission errors explicitly. A test sends a clearly labeled local notification through the real path; it must not create an issue, finish a todo, write to GitHub, or fabricate an agent run. Say Submitted to macOS after successful submission, not Delivered or Seen. Explain that Focus, presentation style and screen-sharing settings may suppress a visible banner; do not claim to detect those causes without an appropriate supported API.

Preserve current notification defaults for existing users. Add individual controls for task completions, needs-attention events, stale activity, and sound. Show in-app notices even when native notifications are disabled. Include blocked-todo transitions in needs-attention events with stable deduplication, and use actionable issue/task context. Do not alert again every polling tick, after restart, on unchanged blocked items, or in a catch-up storm after enabling alerts. Keep full-issue completion and celebration behavior from duplicating completion banners. A celebration preference must not inadvertently change task status or issue-dismissal semantics.

General should initially offer Launch at Login using supported macOS service management, the existing shortcut as visible help, and a celebration preference. Handle registration/approval/errors honestly. Investigate the permanent app-installation path before enabling launch at login for a development bundle. Editable global shortcuts can follow later if conflict detection and safe re-registration materially expand this slice.

### Guided setup

Offer a small skippable checklist on first use or from Settings; retain access for established installations without interrupting existing tracking. Use plain language:

1. Find Tracker Trapper: explain menu-bar operation, the shortcut, keeping the app running, and optional login launch.
2. Enable and test notifications: explain why before requesting permission; permit skipping. A submitted test is not proof that the user saw it.
3. Connect an agent: select Codex or Claude Code, show copyable setup instructions using discovered absolute executable paths, then verify a real MCP request. Distinguish tool availability from the agent actually reporting. Provide the concise reporting instruction from the guide. Check current provider CLI documentation at implementation time; do not overwrite existing config or request broad permissions by default.
4. Track an issue: check GitHub CLI availability/authentication, paste an issue URL, validate its stable-ID checklist and preview recognized todos, import explicitly, then show observed agent activity. Reuse importer/store logic instead of building a competing parser. Handle unavailable gh, expired auth, invalid URLs, inaccessible repositories and zero recognized todos with corrective guidance. Do not silently rewrite GitHub issue bodies.

Separate the states Configured, Connection verified, and Progress received. No active session does not mean disconnected. Session watching is optional enrichment with explicit session identity/path selection, not a prerequisite for direct MCP reports. Explain that tracking does not launch agents and that local updates do not automatically write back to GitHub. Any demo must use isolated fixture data, never the live store.

### Implementation sequence

1. Read repository instructions and existing notification, watcher, and integration tests. Preserve unrelated uncommitted changes. Register agreed implementation todos with stable IDs through the normal Tracker Trapper workflow before implementing.
2. Introduce typed preferences and a notification-service boundary around the existing delivery path. Capture current settings and errors first.
3. Build the Settings window and Notifications section; verify a real test banner from the actual installed bundle.
4. Route existing completion/attention events through the service, add blocked-todo transitions, and preserve deduplication/grouping.
5. Add setup checklist and Connections health, reusing canonical import and reporting paths. Retain accurate manual fallback instructions.
6. Add login-item handling and About/Diagnostics: app version, running bundle path, store location, last refresh, connection/watch errors, Open Data Folder and explicit redacted diagnostic copying.
7. Update the Mac guide and integration docs to match the actual UI and support boundaries.

### Acceptance and regression checks

- Settings opens from the accessory panel, supports keyboard/VoiceOver navigation, and refreshes OS permission after returning from System Settings.
- Test not-determined, authorized, denied, alerts-disabled, sounds-disabled and submission-error states using an injected system boundary. Test notifications never mutate the live progress store.
- Preferences survive relaunch. App-level opt-out suppresses submission without clearing in-app notices or marking work complete.
- Exercise real completion and blocked transitions, no initial-import/restart duplicates, rapid grouping, hidden/dismissed issues, and repeated refreshes. Explicitly test current visibility filtering and final-todo completion around celebration dismissal before changing their semantics.
- Setup tolerates missing clients, old MCP capabilities, bad executable paths, missing or unauthenticated gh, no active session and failed imports. Configuration detection alone never displays Verified.
- Login enable/disable and approval-required states reflect system state; unavailable registration leaves the app usable.
- Run focused tests, then `swift test`, `swift build -c release`, `scripts/package-app.sh`, and installed-app checks. Retain dated evidence for permission state, submission result, observed banner with panel open/closed, notification click handling and relaunch. Automated submission checks are not visible-banner proof.

### Follow-ons and exclusions

Later: per-issue notification overrides, editable global shortcut, richer notification history, issue-specific notification click navigation, automatic updates and a signed/notarized installer. Do not add custom quiet hours that duplicate Focus in this first slice. Do not request Accessibility, Screen Recording or Full Disk Access just to deliver local notifications. Do not add remote push infrastructure, accounts, automatic agent launching, automatic GitHub writes, or automatic client-config rewrites.

### Platform references

- https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications
- https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/getnotificationsettings(completionhandler:)
- https://support.apple.com/en-ph/guide/mac-help/mchl205da693/mac
- https://support.apple.com/en-lamr/guide/mac-help/mchl613dc43f/mac
