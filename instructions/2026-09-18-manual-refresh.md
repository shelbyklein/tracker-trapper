# Manual refresh

The Refresh button joins existing work, forces a fresh GitHub issue-state check,
reads new records from currently watched active session logs, and reapplies the
local snapshot. Automatic polling retains its normal GitHub cache. Concurrent
clicks are coalesced. The button shows a spinner during the operation, then
Updated, Up to date, or Check notices for three seconds. Its tooltip records the
last manual refresh time. Session read failures now appear in the notification
bell rather than being swallowed inside watcher status.

This consumes new log records from persisted cursors; it does not replay old
session history or infer acceptance from arbitrary prose. GitHub refresh now also reconciles issue titles and stable-ID checklist items.
Both **TT-ID — description** and **TT-ID** — description formats are supported.
New IDs are added; existing local evidence and historical IDs are retained.
Remote unchecked boxes do not reset local completion; checked GitHub items can
complete pending rows with explicitly attributed GitHub evidence.

Validation: native model fixture at /tmp/tt-refresh-ui-check.swift passed busy
state, duplicate clicks, GitHub cache bypass, real JSONL completion consumption,
unchanged feedback, and errors for missing logs/network failures. Release build
and diff checks passed. One currently linked active session was read successfully
with zero read failures before installation.
