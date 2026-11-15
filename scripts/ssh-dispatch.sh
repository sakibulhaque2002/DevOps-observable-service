#!/usr/bin/env bash
# OpenSSH forced command: accept a digest only, never evaluate a remote shell command.
set -euo pipefail
image=${SSH_ORIGINAL_COMMAND:-}
if [[ ! $image =~ ^ghcr\.io/[a-z0-9._/-]+@sha256:[a-f0-9]{64}$ ]]; then
  echo "Only a digest-pinned GHCR application deployment is allowed." >&2
  exit 2
fi
exec sudo -n /opt/devops/deploy-container.sh "$image"
