# Submission checklist

Use this to track actual evidence; do not mark a cloud step complete from local mocks.

- [x] Python service: root, health and Prometheus metrics endpoints.
- [x] Environment configuration, JSON stdout logs, graceful SIGTERM shutdown.
- [x] Endpoint tests and at least 90% application coverage.
- [x] Multi-stage digest-pinned non-root image, HEALTHCHECK, labels and dockerignore.
- [x] Compose app with health check, restart policy and resource limits.
- [x] PR CI with Python/Dockerfile/Bash checks, coverage and CRITICAL vulnerability gate.
- [x] Main release workflow with caching, multi-architecture build, SHA/SemVer tags and GHCR publication configuration.
- [x] OIDC + SSM deployment automation, candidate smoke test and automatic rollback control flow.
- [x] Terraform EC2, scoped IAM, security group, bootstrap and retained CloudWatch log configuration.
- [x] Versioned/encrypted/private S3 backend bootstrap and native state locking configuration.
- [x] Staging/production inputs and separate state-key instructions.
- [x] Local Kubernetes: two replicas, probes, resources, Service, ConfigMap, generated Secret and hardening.
- [x] Metrics-server and working CPU-based HPA.
- [x] Real zero-failure rolling update and `rollout undo` evidence.
- [x] All six required observability components, explicit retention, internal monitoring network and pinned images.
- [x] Provisioned data sources and three JSON dashboards, including logs next to application metrics.
- [x] Four alert rules with threshold/duration explanations.
- [x] Three actual dashboard screenshots and error-investigation walkthrough.
- [x] Bash health collector: JSON, thresholds, exit codes, rotation, help, ShellCheck and timer.
- [x] Architecture, design decisions, deployment/rollback, security, costs, improvements and AI-use note.
- [x] Push the commits and obtain a successful GitHub Actions release/image-publication run.
- [x] Verify public GHCR package access and anonymous image pull.
- [x] Confirm active AWS Free plan, available credits, and zero out-of-pocket budget compatibility.
- [x] Run a real Terraform plan and apply; save sanitized evidence.
- [x] Obtain a successful GitHub Actions EC2 deployment run (restricted SSH for this account; OIDC/SSM supported for standard accounts).
- [x] Exercise cloud smoke-test and automatic rollback behavior against actual containers; save evidence.
- [x] Destroy the 9 application resources, verify absence and empty state, remove test credentials/targets, and retain the existing S3 bucket; save sanitized evidence.
- [ ] Review all code and rehearse the explanations before submitting the public repository URL.

The account's AWS-managed policy blocks IAM identity-provider operations. The SSH alternative preserves the Free plan; the default OIDC/SSM implementation remains available for standard accounts. See the evidence index for actual results.
