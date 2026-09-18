# Stale checklist repair

Newton issue #86's store still contained two completed investigation items while
GitHub had a new seven-item implementation checklist. Session activity was fresh.
The status-only GitHub checker never reconciled checklist changes, and the CLI
importer did not accept the newer bold-ID-only checkbox format.

GitHub checks now fetch state/title/body. The shared parser accepts both supported
bold-ID formats and excludes code examples and the generated sync block. Store
reconciliation adds missing IDs, updates text, preserves historical IDs/evidence,
and does not reset local completion from unchecked remote boxes. Checked remote
items complete pending rows with attributed GitHub evidence. Duplicate IDs fail
without mutation. Pulls are local events, not new GitHub outbox writes.

Validation: 25 tests and release build passed. After launching the updated app,
issue #86 contained all seven implementation IDs; live GitHub and local reads
agreed on TT-86-01 through TT-86-06 completed and TT-86-07 pending. The two original
investigation items and their evidence remained intact. These counts are a
point-in-time validation, not a promise of future issue state.
