# Assessment evidence

Local evidence was generated on November 14, 2026; AWS evidence on November 16, 2026 (Asia/Dhaka). Raw AWS and GitHub timestamps use UTC, so the cloud logs show November 15.

- `dashboard-application.png`, `dashboard-host.png`, `dashboard-containers.png`: real Grafana screenshots of the provisioned dashboards and collected data.
- `kubernetes-rollout.txt`: actual rollout, `kubectl rollout undo`, HPA, and Pod output.
- `kubernetes-requests.txt`: 320 actual requests through the Kubernetes Service, zero failures, versions 1.0.0 and 1.0.1 observed.
- `github-release.txt`: successful PR CI, merged PR, multi-architecture publication/scans, exact digest, and explicit cloud-deployment skip.
- `local-verification.txt`: final local checks and measured image size, recorded after the final image rebuild.
- `aws-plan.txt`, `aws-apply.txt`: actual Sydney plan and successful apply creating 9 resources. The existing private, encrypted, versioned S3 bucket uses a separate application state key with native locking.
- `aws-rollback.txt`: the real EC2 deployment script switched real Docker containers, encountered 30 injected post-switch probe failures, restored the previous image, and verified its health. The injection simulates a failing health probe/transport; the app itself was not changed to return errors.
- `cloudwatch-logs.txt`: actual structured application logs retrieved from CloudWatch before deletion.
- `ssh-restrictions.txt`: real SSH attempts to execute an arbitrary command and deploy another repository were rejected.
- `bootstrap-restart.txt`: real upgrade followed by a bootstrap-unit restart preserved the newer image. The initial instance was patched through authenticated SSM with the same guard subsequently committed in PR #5; future Terraform applies install it directly.
- `github-deployment.txt`: [successful owner-approved GitHub Actions deployment](https://github.com/sakibulhaque2002/DevOps-observable-service/actions/runs/43756516444), including CI, multi-architecture publication and both CRITICAL scans. The SSH job ran; the alternative SSM job was intentionally skipped.
- `ec2-runtime.txt`: authenticated verification of the exact deployed digest, version `1.0.0-build.5`, healthy non-root/read-only container, metrics, logging driver and SSH restrictions.
- `aws-cleanup.txt`: actual destruction of all 9 resources, followed by independent AWS API verification of termination and resource absence, empty Terraform state, retained existing S3 bucket and active Free plan.
- `credential-cleanup.txt`: successful SSM revocation, deleted environment secret, cleared deployment target variables and removed generated local private key.

The required cloud apply, successful GitHub Actions deployment, actual-container rollback and cleanup evidence are recorded. Later documentation-only release runs intentionally skip deployment after the target variables are cleared. A skipped job is distinct from the successful deployment run linked above.

The account remained on the active Free plan with $100 credits reported before testing. Its AWS-managed policy denied IAM identity-provider operations, so the permitted SSH deployment alternative avoids an account upgrade. No static AWS access keys were used.

HTTP port 8080 stayed restricted to the approved client IPv4 `/32`. The operator's ISP rotated its outbound NAT address across connections, and direct public HTTP checks timed out. Successful smoke tests ran on EC2 against `localhost` over authenticated administration; these results do not assert successful public HTTP access from that client. SSH port 22 used the separately approved internet ingress rule with a dedicated forced-command key and authenticated host-key pinning.

Do not commit AWS credentials, `.env`, Kubernetes secret data, Terraform state/plans, account recovery details, or unreviewed raw cloud output. Infrastructure identifiers may be redacted consistently without changing the result.
