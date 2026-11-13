"""Deploy a digest-pinned image through SSM; print command output and preserve failure status."""

import json
import os
import re
import subprocess
import time


def aws(*args):
    return json.loads(subprocess.check_output(["aws", *args, "--output", "json"], text=True))


def main():
    instance = os.environ["EC2_INSTANCE_ID"]
    image = os.environ["DEPLOY_IMAGE"]
    if not re.fullmatch(r"ghcr\.io/[a-z0-9._/-]+@sha256:[a-f0-9]{64}", image):
        raise SystemExit("DEPLOY_IMAGE must be a digest-pinned GHCR image")
    command = aws(
        "ssm",
        "send-command",
        "--instance-ids",
        instance,
        "--document-name",
        "AWS-RunShellScript",
        "--timeout-seconds",
        "600",
        "--parameters",
        json.dumps(
            {
                "commands": [f"/opt/devops/deploy-container.sh {image}"],
                "executionTimeout": ["600"],
            }
        ),
        "--comment",
        "GitHub Actions application deployment with health check and rollback",
    )["Command"]["CommandId"]
    print(f"SSM command: {command}", flush=True)
    for _ in range(140):
        time.sleep(5)
        try:
            result = aws(
                "ssm", "get-command-invocation", "--command-id", command, "--instance-id", instance
            )
        except subprocess.CalledProcessError:
            continue  # SSM invocation information is eventually consistent.
        status = result["Status"]
        if status in {"Pending", "InProgress", "Delayed", "Cancelling"}:
            continue
        print(result.get("StandardOutputContent", ""))
        print(result.get("StandardErrorContent", ""))
        print(f"SSM status: {status}")
        raise SystemExit(0 if status == "Success" else 1)
    raise SystemExit("Timed out waiting for SSM; inspect the command before deploying again")


if __name__ == "__main__":
    main()
