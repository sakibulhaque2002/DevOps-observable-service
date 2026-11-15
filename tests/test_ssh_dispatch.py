"""The SSH key cannot select a shell command or mutable image tag."""

import json
import os
import subprocess
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/ssh-dispatch.sh"
IMAGE = "ghcr.io/example/app@sha256:" + "a" * 64


def test_ssh_dispatch_passes_one_digest_to_fixed_sudo_command(tmp_path):
    sudo = tmp_path / "sudo"
    sudo.write_text("#!/usr/bin/env python3\nimport json,sys\nprint(json.dumps(sys.argv[1:]))\n")
    sudo.chmod(0o755)
    result = subprocess.run(
        [str(SCRIPT)],
        text=True,
        capture_output=True,
        check=False,
        env={
            **os.environ,
            "PATH": f"{tmp_path}:{os.environ['PATH']}",
            "SSH_ORIGINAL_COMMAND": IMAGE,
        },
    )
    assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout) == ["-n", "/opt/devops/deploy-container.sh", IMAGE]


@pytest.mark.parametrize(
    "command", ["", "id", "ghcr.io/example/app:latest", IMAGE + ";id", IMAGE + " /bin/sh"]
)
def test_ssh_dispatch_rejects_other_commands(command):
    result = subprocess.run(
        [str(SCRIPT)],
        text=True,
        capture_output=True,
        check=False,
        env={**os.environ, "SSH_ORIGINAL_COMMAND": command},
    )
    assert result.returncode == 2
    assert "Only a digest-pinned" in result.stderr
    assert result.stdout == ""
