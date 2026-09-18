---
name: tracker
description: Turn Tracker Trapper local task tracking on or off for the current session, start a local checklist, or inspect current-session status.
---

# Tracker Trapper controls

Interpret `$ARGUMENTS` as one of `on`, `off`, `start`, `decline`, or `status`. Use the Tracker Trapper MCP tools when available and the `tracker-trapper` CLI as fallback. Never reinterpret an unsupported action. Tracking is off unless the user invokes this skill or a workflow such as `issue-to-work` explicitly binds the current session. Never ask about tracking at session startup.

- `on` or `start`: first read `get_session_tracking`. Reuse an accepted plan/run binding for this exact client/session. If none exists, derive a concise checklist from the user's actual task. Use stable IDs in the form `TT-LOCAL-<SHORT>-01` with concrete acceptance checks. Call `register_local_plan` once with a stable creation request key based on the client/session, then `start_run`, then `set_session_tracking` with `decision: accepted` and the returned plan/run IDs. Repeated invocation must reuse the returned plan and active run. Start the first todo and explicitly set `nextTodoID`.
- `off` or `decline`: read the current session binding. If it owns an active run, finish that run as `paused` with a clear message, then call `set_session_tracking` for this client/session with `decision: declined`. Preserve the plan, evidence, and other sessions.
- `status`: call `get_session_tracking` for the current client/session and `watch_status`. Report the decision, plan/run binding, and watcher health without changing state.

For CLI fallback, provide JSON on stdin to `tracker-trapper tracker start` for `on`/`start`, and use `tracker-trapper session-tracking` for current-session status or decline. Use `CODEX_SESSION_ID`/`CODEX_THREAD_ID` for Codex when available and the provider session ID for Claude. Never scan for a recent transcript or infer another session from the current directory.

An `issue-to-work` run already has a GitHub plan and run; reuse that binding instead of creating a local plan.
