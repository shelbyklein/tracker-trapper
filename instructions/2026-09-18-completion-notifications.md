# TT-17 — Todo completion notifications

Requested behavior: show a macOS banner when a tracked todo transitions to completed, with its description and issue identity, even with the popover closed.

Implemented a one-second app-lifetime refresh timer and completion comparisons using stable plan/todo IDs. Initial loads, completed imports and unchanged snapshots do not notify. Several completions in one refresh are grouped per issue. Generic plan-complete notifications are suppressed to avoid duplicate banners. A notification-center delegate allows foreground banners; authorization is requested at app launch.

Validation: 11 Swift tests passed, including completion transitions, no-repeat/restart/import behavior, skipped tasks and grouping. Release build and packaging passed; the app was relaunched from `dist/TrackerTrapper.app`. Native banner presentation remains subject to user notification permission and Focus settings; a displayed completion banner has not been visually verified in this session. No live todo was changed to fabricate a completion.
