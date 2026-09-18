# TT-04 / TT-05 / TT-10 / TT-14 / TT-15 corrective acceptance

The previous acceptance record overstated end-to-end verification. Tool discovery did not validate tool-call response envelopes; a popover opened after fixture creation did not establish live refresh; multiple runs in one actor did not establish separate-process safety.

Root causes reproduced in the release binary:

- Registration persisted successfully but returned raw plan JSON instead of MCP content.
- Store reads returned an in-memory snapshot indefinitely, including menu-bar Refresh.
- Two long-lived processes loaded an empty store; after A registered one issue and B registered another, only B's issue remained.

Repairs:

- Standard MCP content and structuredContent for successful calls; tool errors use content plus isError.
- Sidecar file lock across reload, validation, mutation and atomic persistence for every store operation. Failed operations roll back the cached state; corrupt disk input is surfaced and never overwritten.
- Re-registration preserves status, evidence and task revisions while updating descriptions.
- Popover polls every second, reloads on manual Refresh/open, and keeps its last snapshot with an error if reload fails.

Verification:

- Nine Swift tests passed, including independent store instances and corrupt-file recovery.
- Four real MCP processes passed concurrent registration, shared reads, concurrent task updates, duplicate retry, re-registration and error-envelope checks in isolated storage.
- Official Python MCP client initialized, listed eight tools and validated a successful register_plan result.
- Release build succeeded in `/tmp/tracker-trapper-repair-build`; the old build cache references Downloads and cannot be reused after relocation without cleaning/rebuilding.
- Packaged app opened on an empty isolated store; registration through another process appeared in the already-open popover without clicking Refresh. Screenshot: `/tmp/tracker-trapper-ui-repair/after.png` (local diagnostic artifact).

Deployment requires replacing configured binaries and restarting old MCP processes as well as the app. The existing JSON format and default data path are preserved. A backup of live data must precede replacement. Public signing/notarization remains outside this correction.

Deployment completed locally: rebuilt all release products at the configured `.build/release` paths after cleaning the relocated cache; repackaged and launched `dist/TrackerTrapper.app`. Stopped the three old MCP server processes so they cannot overwrite the store. Clients must reconnect to launch the repaired server. The installed release passed the four-process integration test again. The live popover visibly shows `shelbyklein/newton #87`, `0/16`, and the in-progress first todo. The store is byte-for-byte identical to its pre-deployment backup at `/Users/shelbyklein/Library/Application Support/TrackerTrapper/repair-backup.XaYOrW/store.json`. Screenshot: `/tmp/tracker-trapper-ui-repair/live-issue-87.png`.
