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
        def complete(pair):
            index, process = pair
            return call(process, "complete_task", runID=run["id"], todoID=f"TT-0{index + 1}",
                        evidence=["integration test"], eventID=f"event-{index}")
        with concurrent.futures.ThreadPoolExecutor() as executor:
            list(executor.map(complete, enumerate(processes[:2])))
        complete((0, processes[2]))  # Retry through a different long-lived process.
        register((0, processes[3]))  # Re-registration must preserve completion/evidence.
        saved = call(processes[1], "get_plan", planID=plan_id)
        assert all(todo["status"] == "completed" for todo in saved["todos"])
        assert all(todo["evidence"] == ["integration test"] for todo in saved["todos"])
        error = rpc(processes[0], "tools/call", dict(name="get_plan", arguments=dict(planID="missing")))
        assert error["isError"] is True
        assert len(json.loads(store.read_text())["plans"]) == 4
        print("PASS: MCP envelopes, four concurrent processes, fresh reads, concurrent task updates, retries, re-registration, tool errors")
    finally:
        for process in processes:
            process.stdin.close()
            process.wait(timeout=10)
