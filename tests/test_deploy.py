"""Run the real deployment script against deterministic Docker/curl stand-ins."""

import json
import os
import subprocess
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/deploy-container.sh"

FAKE_TOOL = """#!/usr/bin/env python3
import json, os, pathlib, sys
p = pathlib.Path(os.environ["FAKE_STATE"])
state = json.loads(p.read_text())
args = sys.argv[1:]
tool = pathlib.Path(sys.argv[0]).name
if tool == "curl":
    candidate = "18080" in args[-1]
    failing = (candidate and state["scenario"] == "candidate-fail") or (
        not candidate and state["scenario"] == "promote-fail" and
        state.get("app", {}).get("image") == "ghcr.io/example/app:new")
    sys.exit(1 if failing else 0)
if tool == "sleep":
    sys.exit(0)
if args[0] == "container" and args[1] == "inspect":
    sys.exit(0 if args[2] in state else 1)
if args[0] == "run":
    name = args[args.index("--name") + 1]
    state[name] = {"image": args[-1], "running": True}
elif args[0] == "rm":
    state.pop(args[-1], None)
elif args[0] == "stop":
    state[args[-1]]["running"] = False
elif args[0] == "rename":
    state[args[2]] = state.pop(args[1])
elif args[0] == "start":
    state[args[1]]["running"] = True
p.write_text(json.dumps(state))
"""


@pytest.mark.parametrize(
    "scenario,exit_code,image",
    [
        ("success", 0, "ghcr.io/example/app:new"),
        ("candidate-fail", 1, "ghcr.io/example/app:old"),
        ("promote-fail", 1, "ghcr.io/example/app:old"),
    ],
)
def test_deployment_restores_previous_release(tmp_path, scenario, exit_code, image):
    state = tmp_path / "state.json"
    state.write_text(
        json.dumps(
            {
                "scenario": scenario,
                "app": {"image": "ghcr.io/example/app:old", "running": True},
            }
        )
    )
    config = tmp_path / "service.env"
    config.write_text("AWS_REGION=us-east-1\nLOG_GROUP=test\nAPP_ENVIRONMENT=staging\n")
    for name in ["docker", "curl", "sleep"]:
        tool = tmp_path / name
        tool.write_text(FAKE_TOOL)
        tool.chmod(0o755)
    result = subprocess.run(
        [str(SCRIPT), "ghcr.io/example/app:new"],
        text=True,
        capture_output=True,
        env={
            **os.environ,
            "PATH": f"{tmp_path}:{os.environ['PATH']}",
            "FAKE_STATE": str(state),
            "DEPLOY_CONFIG_FILE": str(config),
            "DEPLOY_LOCK_FILE": str(tmp_path / "deploy.lock"),
        },
        check=False,
    )
    assert result.returncode == exit_code, result.stderr
    final = json.loads(state.read_text())
    assert final["app"] == {"image": image, "running": True}
    assert "app-candidate" not in final
    if scenario == "promote-fail":
        assert "Rollback completed" in result.stderr
