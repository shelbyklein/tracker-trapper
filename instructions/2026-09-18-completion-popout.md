# Automatic completion celebration

Size revision: the automatic popout is now a 44 × 44 point icon with a small
confetti burst, no title or text, and a 1.4-second duration. Clicking the icon
dismisses it. The main panel's inline card is unchanged. The implementation and
runtime record below describes the original larger version; compact follow-up
work is tracked as `TT-LOCAL-POP-04`.

Implemented September 18, 2026. Local tracking plan: `local:941311AA-4146-416B-AE01-728C41E0D446`.
Todos: `TT-LOCAL-POP-01` (investigation), `TT-LOCAL-POP-02` (implementation), `TT-LOCAL-POP-03` (verification).

Completing a tracked checklist or observing an open GitHub issue close shows the
existing celebration card automatically in a 340 × 242 menu-bar popout. It lasts
three seconds, has a dismiss button, and never becomes the key/main window or
activates Tracker Trapper. With the main panel open, the same card plays inline.
If macOS hides/overflows the status icon and supplies no screen anchor, the
popout uses the active display's top-right corner.

The queue and observed GitHub closure state persist across restarts. First-seen
closed/completed imports remain quiet. Repeated polls do not replay a completed
celebration, nor does closing an already-celebrated issue checklist. Reopening an
issue allows a later closure to celebrate again. Issue closure never changes
unfinished todo states. Normal GitHub polling can take up to about a minute;
manual Refresh checks immediately.

Settings → General → Show completion celebrations controls both inline and
automatic presentations. Turning it off quietly acknowledges pending cards.
Reduce Motion keeps the card static, without confetti or scale animation.

## Verification

- `swift test`: 52 tests passed, including six core celebration tests and five
  app presentation tests. After the packaged run exposed the missing-screen
  anchor case, the five app tests passed again with a new offscreen-anchor
  assertion. Tests cover automatic playback and timed dismissal, focus,
  positioning, simultaneous completions, unavailable presentation, settings,
  closure/import/reopen behavior, legacy persistence decoding, and unchanged
  unfinished todos.
- `swift build -c release --product TrackerTrapperMenuBar`: passed.
- Packaged release binary ran with isolated local and GitHub fixtures. A fake
  `gh` response changed from OPEN to CLOSED through the regular polling path;
  no real issue was changed for this check. Both popouts rendered and dismissed
  automatically. Local dismissal was observed at 3.01 seconds. Google Chrome
  remained frontmost before and during both presentations. The closed fixture's
  unfinished todo remained pending. Screenshots were visually inspected.
- Runtime evidence and images: `output/completion-popout/runtime-evidence.json`,
  `local-list.png`, and `github-closed.png`. The packaged run also exercised the
  hidden-icon fallback found on the target Mac.
- Updated `/Users/shelbyklein/Applications/TrackerTrapper.app` and relaunched it.
  Its executable matches the packaged artifact; the live PID and retained old
  bundle backup are in `output/completion-popout/install-evidence.json`.
  The bundle has a verified ad-hoc local signature, not a notarized release.
- Completing this task's actual local checklist then triggered the newly
  installed app's popout. Captured `installed-live-completion.png` and
  `installed-live-evidence.json`; the installed PID displayed it without changing
  the frontmost application. This is live local-list evidence beyond the fixtures.
- `git diff --check`: passed. Existing unrelated checkout changes were preserved.

The GitHub runtime case is a controlled fixture, not a newly closed production
issue. Reduce Motion is implemented through the system SwiftUI environment and
AppKit preference; this run did not change the user's global accessibility
setting. User acceptance remains separate from these implementation checks.
