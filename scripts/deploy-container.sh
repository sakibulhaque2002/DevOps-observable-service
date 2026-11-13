#!/usr/bin/env bash
# Installed on EC2 by Terraform. Validate a candidate, switch, and restore on failure.
set -euo pipefail

if [[ $# != 1 || ! $1 =~ ^ghcr\.io/[a-z0-9._/-]+(:[a-zA-Z0-9._-]+|@sha256:[a-f0-9]{64})$ ]]; then
  echo "Usage: $0 ghcr.io/owner/image:<immutable-tag-or-digest>" >&2
  exit 2
fi
image=$1
exec 9>"${DEPLOY_LOCK_FILE:-/var/lock/devops-deploy.lock}"
flock -w 300 9
# Root-owned file generated from non-secret Terraform settings.
# shellcheck source=/dev/null
source "${DEPLOY_CONFIG_FILE:-/etc/devops/service.env}"
: "${AWS_REGION:?}" "${LOG_GROUP:?}" "${APP_ENVIRONMENT:?}"

run_container() {
  local name=$1 port=$2
  docker run -d --name "$name" --restart unless-stopped \
    --read-only --tmpfs /tmp:rw,noexec,nosuid,size=16m \
    --cap-drop ALL --security-opt no-new-privileges:true \
    --memory 128m --cpus 0.5 --pids-limit 64 --stop-timeout 30 \
    -e PORT=8080 -e ENVIRONMENT="$APP_ENVIRONMENT" -e LOG_LEVEL=INFO \
    --log-driver awslogs --log-opt awslogs-region="$AWS_REGION" \
    --log-opt awslogs-group="$LOG_GROUP" --log-opt awslogs-stream="$name" \
    -p "$port:8080" "$image"
}

wait_healthy() {
  local url=$1
  for _ in {1..30}; do
    if curl --fail --silent --max-time 2 "$url" >/dev/null; then return 0; fi
    sleep 2
  done
  return 1
}

docker pull "$image"
docker rm -f app-candidate >/dev/null 2>&1 || true
if ! run_container app-candidate 127.0.0.1:18080 || \
   ! wait_healthy http://127.0.0.1:18080/health; then
  docker logs app-candidate >&2 || true
  docker rm -f app-candidate >/dev/null 2>&1 || true
  echo "Candidate failed; active release was not changed." >&2
  exit 1
fi
docker rm -f app-candidate >/dev/null

docker rm -f app-previous >/dev/null 2>&1 || true
had_previous=false
if docker container inspect app >/dev/null 2>&1; then
  docker stop --time 30 app >/dev/null
  docker rename app app-previous
  had_previous=true
fi

if run_container app 8080 && wait_healthy http://127.0.0.1:8080/health; then
  echo "Deployed $image; /health passed. Previous container retained for rollback."
  exit 0
fi

echo "Smoke test failed; restoring previous release." >&2
docker logs app >&2 || true
docker rm -f app >/dev/null 2>&1 || true
if "$had_previous"; then
  docker rename app-previous app
  docker start app >/dev/null
  if ! wait_healthy http://127.0.0.1:8080/health; then
    echo "CRITICAL: previous release also failed its health check." >&2
    exit 2
  fi
  echo "Rollback completed; previous release is healthy." >&2
else
  echo "No previous release exists on this first deployment." >&2
fi
exit 1
