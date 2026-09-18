#!/usr/bin/env python3
"""Exercise actual MCP processes against an isolated store; no live data writes."""
import concurrent.futures
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

binary = sys.argv[1]


def rpc(process, method, params):
    process.stdin.write(json.dumps(dict(jsonrpc="2.0", id=1, method=method, params=params)) + "\n")
    process.stdin.flush()
    response = json.loads(process.stdout.readline())
    assert "error" not in response, response
    result = response["result"]
    if method == "tools/call":
        assert isinstance(result["content"], list), result
        assert result["content"][0]["type"] == "text", result
        if not result.get("isError"):
            assert json.loads(result["content"][0]["text"]) == result["structuredContent"]
    return result


def call(process, name, **arguments):
    result = rpc(process, "tools/call", dict(name=name, arguments=arguments))
    assert not result.get("isError"), result
    return result["structuredContent"]


with tempfile.TemporaryDirectory(prefix="tracker-mcp-test-") as directory:
    store = Path(directory) / "store.json"
    processes = [subprocess.Popen([binary], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                 text=True, env=dict(os.environ, TRACKER_TRAPPER_STORE=str(store))) for _ in range(4)]
    try:
        for process in processes:
            rpc(process, "initialize", {})
        def register(pair):
            index, process = pair
            return call(process, "register_plan", repository="test/isolated", issueNumber=index + 1,
                        issueURL=f"https://github.com/test/isolated/issues/{index + 1}", title="Integration test",
                        todos=[dict(id="TT-01", description="First"), dict(id="TT-02", description="Second")])
        with concurrent.futures.ThreadPoolExecutor() as executor:
            plans = list(executor.map(register, enumerate(processes)))
        assert len(json.loads(store.read_text())["plans"]) == 4
        plan_id = plans[0]["id"]
        for process in processes:
            assert call(process, "get_plan", planID=plan_id)["id"] == plan_id
        run = call(processes[0], "start_run", planID=plan_id, agent="test", sessionID="session", repositoryPath=directory)
        schema = rpc(processes[0], "tools/list", {})["tools"]
        assert "nextTodoID" in next(t for t in schema if t["name"] == "complete_task")["inputSchema"]["properties"]
        assert any(t["name"] == "register_local_plan" for t in schema)
        assert call(processes[0], "set_tracking_settings", askAtSessionStart=True)["askAtSessionStart"] is True
        assert call(processes[1], "get_tracking_settings")["askAtSessionStart"] is True
        local = call(processes[0], "register_local_plan", title="Local integration", workspacePath=directory,
                     creationRequestKey="mcp-local", todos=[dict(id="TT-LOCAL-MCP-01", description="Verify local MCP")])
        local_retry = call(processes[1], "register_local_plan", title="Local integration", workspacePath=directory,
                           creationRequestKey="mcp-local", todos=[dict(id="TT-LOCAL-MCP-01", description="Verify local MCP")])
        assert local["id"] == local_retry["id"]
        local_run = call(processes[0], "start_run", planID=local["id"], agent="test", sessionID="local-session", repositoryPath=directory)
        call(processes[0], "set_session_tracking", client="codex", sessionID="local-session", decision="accepted",
             planID=local["id"], runID=local_run["id"], creationRequestKey="mcp-local")
        assert call(processes[1], "get_session_tracking", client="codex", sessionID="local-session")["session"]["runID"] == local_run["id"]
        call(processes[0], "set_next_task", runID=run["id"], nextTodoID="TT-02")
        assert call(processes[1], "get_plan", planID=plan_id)["nextTodoID"] == "TT-02"
        call(processes[0], "report_activity", runID=run["id"], nextTodoID="")
        assert call(processes[1], "get_plan", planID=plan_id).get("nextTodoID") is None
        call(processes[0], "start_task", runID=run["id"], todoID="TT-01", nextTodoID="TT-02")
        bad = rpc(processes[0], "tools/call", dict(name="complete_task", arguments=dict(runID=run["id"], todoID="TT-01", nextTodoID="missing")))
        assert bad["isError"]
        assert call(processes[1], "get_plan", planID=plan_id)["todos"][0]["status"] == "in_progress"
        def complete(pair):
            index, process = pair
            return call(process, "complete_task", runID=run["id"], todoID=f"TT-0{index + 1}",
                        evidence=["integration test"], eventID=f"event-{index}")
        with concurrent.futures.ThreadPoolExecutor() as executor:
            list(executor.map(complete, enumerate(processes[:2])))
        complete((0, processes[2]))  # Retry through a different long-lived process.
        register((0, processes[3]))  # Re-registration must preserve completion/evidence.
        saved = call(processes[1], "get_plan", planID=plan_id)
        assert saved.get("nextTodoID") is None
        assert all(todo["status"] == "completed" for todo in saved["todos"])
        assert all(todo["evidence"] == ["integration test"] for todo in saved["todos"])
        error = rpc(processes[0], "tools/call", dict(name="get_plan", arguments=dict(planID="missing")))
        assert error["isError"] is True
        saved_store = json.loads(store.read_text())
        assert len(saved_store["plans"]) == 5
        assert all(event["planID"] != local["id"] for event in saved_store["outbox"])
        print("PASS: MCP envelopes, concurrent processes, local/GitHub plans, persistent settings/session binding, outbox isolation, retries, next-task updates, and tool errors")
    finally:
        for process in processes:
            process.stdin.close()
            process.wait(timeout=10)
