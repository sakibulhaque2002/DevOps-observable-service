# Assessment evidence

Evidence was generated locally on November 14, 2026 (Asia/Dhaka).

- `dashboard-application.png`, `dashboard-host.png`, `dashboard-containers.png`: real Grafana screenshots of the provisioned dashboards and collected data.
- `kubernetes-rollout.txt`: actual rollout, `kubectl rollout undo`, HPA, and Pod output.
- `kubernetes-requests.txt`: 320 actual requests through the Kubernetes Service, zero failures, versions 1.0.0 and 1.0.1 observed.
- `github-release.txt`: successful PR CI, merged PR, multi-architecture publication/scans, exact digest, and explicit cloud-deployment skip.
- `local-verification.txt`: final local checks and measured image size, recorded after the final image rebuild.

Pending cloud evidence: a real Terraform plan/apply, a successful GitHub Actions SSM deployment, and resource destruction. Add sanitized output or workflow links after the AWS account is ready. A skipped deploy job, mocked Terraform plan, or stand-in deployment test does not satisfy these requirements.

Do not commit AWS credentials, `.env`, Kubernetes secret data, Terraform state/plans, account recovery details, or unreviewed raw cloud output. Infrastructure identifiers may be redacted consistently without changing the result.
