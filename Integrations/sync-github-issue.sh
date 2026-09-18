#!/bin/sh
set -eu

# Synchronize only the Tracker Trapper-owned block in an issue body. GitHub
# authentication is delegated to `gh`'s credential store; no token is read or
# written by this script.
REPO=""; ISSUE=""; PLAN=""; DRY_RUN=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2;;
    --issue) ISSUE="$2"; shift 2;;
    --plan-id) PLAN="$2"; shift 2;;
    --dry-run) DRY_RUN=1; shift;;
    *) echo "unknown argument: $1" >&2; exit 2;;
  esac
done
[ -n "$REPO" ] && [ -n "$ISSUE" ] && [ -n "$PLAN" ] || { echo "usage: sync-github-issue.sh --repo owner/name --issue number --plan-id id [--dry-run]" >&2; exit 2; }

STORE="${TRACKER_TRAPPER_STORE:-$HOME/Library/Application Support/TrackerTrapper/store.json}"
BODY_FILE="$(mktemp -t tracker-trapper-body.XXXXXX)"
NEW_FILE="$(mktemp -t tracker-trapper-new.XXXXXX)"
trap 'rm -f "$BODY_FILE" "$NEW_FILE"' EXIT
gh issue view "$ISSUE" --repo "$REPO" --json body --jq .body > "$BODY_FILE"

BLOCK="<!-- tracker-trapper:progress:start -->"
END="<!-- tracker-trapper:progress:end -->"
PROGRESS="$(TRACKER_TRAPPER_STORE="$STORE" "$TT_TRACKER_TRAPPER_BIN" snapshot | jq -r --arg plan "$PLAN" --arg start "$BLOCK" --arg end "$END" '
  .plans[] | select(.id == $plan) |
  ($start + "\n### Tracker Trapper progress\n" +
   ([.todos[] | "- [" + (if .status == "completed" then "x" else " " end) + "] " + .id + " — " + .description + (if (.evidence|length) > 0 then " _(evidence: " + (.evidence|join(", ")) + ")_" else "" end)] | join("\n")) + "\n" + $end)')"

if grep -qF "$BLOCK" "$BODY_FILE"; then
  awk -v start="$BLOCK" -v end="$END" -v replacement="$PROGRESS" '
    $0 == start { print replacement; inside=1; next }
    $0 == end { inside=0; next }
    !inside { print }
  ' "$BODY_FILE" > "$NEW_FILE"
else
  cat "$BODY_FILE" > "$NEW_FILE"
  printf '\n\n%s\n' "$PROGRESS" >> "$NEW_FILE"
fi

if [ "$DRY_RUN" -eq 1 ]; then cat "$NEW_FILE"; exit 0; fi
gh issue edit "$ISSUE" --repo "$REPO" --body-file "$NEW_FILE"
