# Completion celebrations

Task completions request native macOS notifications with issue identity. Clicking
the notification opens the progress panel. Banner delivery remains subject to
macOS notification settings.

When an observed issue transitions from unfinished to all completed/skipped
(with at least one completed task), queue a celebration in
`store.celebrations.json`. Already-completed imports and all-skipped plans do not
celebrate. The queue persists across app restarts and closing the panel early.

Opening the panel plays queued issues sequentially at the top: confetti and a
party icon over blurred task rows, with repository/issue number and issue title.
After three seconds the card fades/slides out and remains dismissed; history is
retained. Reduced Motion removes confetti/movement. New unfinished work makes the
issue eligible again. Closed or manually dismissed issues are excluded.

Validation: 23 Swift tests passed. Native hosting-view fixture verified per-task
notification requests, pending queue persistence, interruption/replay, automatic
card dismissal, no replay on refresh, and original store history preservation.
Visual fixture inspected at `/tmp/tt-celebration-preview.png`; runtime harness at
`/tmp/tt-celebration-ui-check.swift`. Native OS banner delivery and notification
click activation were implemented but not exercised by the fixture.
