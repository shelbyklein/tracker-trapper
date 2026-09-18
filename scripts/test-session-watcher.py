#!/usr/bin/env python3
"""CLI/MCP watcher smoke test in temporary storage, including process restarts."""
import datetime
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

cli, mcp = sys.argv[1:3]
with tempfile.TemporaryDirectory(prefix="tracker-watch-integration-") as directory:
    env = dict(os.environ, TRACKER_TRAPPER_STORE=directory + "/store.json")
    source = Path(directory) / "session.jsonl"
    source.write_text(json.dumps(dict(type="session_meta", payload=dict(id="fixture-session"))) + "\n")

    def command(*args, stdin=None):
        result = subprocess.run([cli, *args], input=stdin, text=True, capture_output=True, env=env, check=True)
        return json.loads(result.stdout)

    plan = command("register-plan", stdin=json.dumps(dict(repository="test/watcher", issueNumber=1,
        issueURL="https://github.com/test/watcher/issues/1", title="Watcher integration",
        todos=[dict(id="TT-87-01", description="Verify completion")])) )
    run = command("start-run", "--plan-id", plan["id"], "--agent", "fixture", "--session-id", "fixture-session")
    request = dict(jsonrpc="2.0", id=1, method="tools/call", params=dict(name="watch_session",
        arguments=dict(runID=run["id"], sourcePath=str(source), format="codex")))
    result = subprocess.run([mcp], input=json.dumps(request) + "\n", text=True, capture_output=True, env=env, check=True)
    response = json.loads(result.stdout)["result"]
    assert response["isError"] is False, response
    assert response["structuredContent"]["sessionID"] == "fixture-session"
    baseline = command("snapshot")

    def append(text, role="assistant"):
        with source.open("a") as file:
            file.write(json.dumps(dict(timestamp=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                type="response_item", payload=dict(type="message", role=role,
                content=[dict(type="output_text", text=text)]))) + "\n")

    append("Please mark TT-87-01 complete", role="user")
    command("watch-once")
    assert command("snapshot") == baseline
    append("Running the acceptance checks")
    report = command("watch-once")
    assert report[0]["lastSummary"] == "Running the acceptance checks"
    active = command("snapshot")
    assert active["plans"][0]["todos"][0]["status"] == "pending"
    assert "lastTaskUpdateAt" not in active["runs"][0]
    append("TT-87-01: completed — acceptance checks passed")
    command("watch-once")
    completed = command("snapshot")
    assert completed["plans"][0]["todos"][0]["status"] == "completed"
    command("watch-once")
    assert command("snapshot") == completed
    subprocess.run([cli, "unwatch-session", "--run-id", run["id"]], env=env, capture_output=True, check=True)
    assert command("watch-status") == []
    print("PASS: MCP linking, session identity, activity without completion, explicit completion, durable cursor, silent idle polling, unlink")
