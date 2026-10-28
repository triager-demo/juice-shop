# Juice Shop on ECS Fargate

This deployment builds the repository's root Dockerfile and serves
`https://juice-shop.stuartmehrens.com` in `us-east-2`. The fixtures under `infrastructure/` are not deployment templates.

## Architecture

`ci.yml` runs lint, builds the frontend and backend, runs frontend/server/API
tests and RSN, and validates deployment templates on pull requests.
`deploy.yml` reuses the same CI workflow on pushes to `main` and manual
releases before publishing an ARM64 image to a private ECR repository. The `demo` GitHub environment obtains
temporary AWS credentials using OIDC and deploys an immutable image digest through
the service CloudFormation stack. No long-lived AWS keys are stored in GitHub.

CI runs separate lint, build, frontend/server/API test, RSN, deployment-template,
and Docker-build jobs. Backend and frontend dependencies are installed from
committed lockfiles using `npm ci`, with npm downloads cached by lockfile hash.
All eight checks are required on pull requests to `main`, including for admins.
The branch must be up to date before merging; force pushes and deletion are blocked.

The platform stack creates a dedicated VPC, two public subnets, an HTTPS
Application Load Balancer, ECR, CloudWatch logs, and the Fargate execution role.
Tasks use public IPs for outbound image pulls without a NAT gateway; their security
group accepts port 3000 only from the load balancer. The application has no AWS
task role. HTTPS and its HTTP redirect accept only the public IPv4 address supplied
as `AllowedClientCidr` (a single address with `/32`). The load balancer uses IPv4.
Anyone sharing that public IP can connect; update the parameter when changing networks
or when the ISP changes the address.

Juice Shop uses local SQLite and resets its database at startup. Keep one task and
no autoscaling. Releases stop the old task before starting its replacement, causing
a short outage and resetting application state. ECS's deployment circuit breaker and
CloudFormation rollback restore the previous release when a deployment fails.
Neither mechanism restores old application data.

## Initial setup

Use AWS CLI profile `juice-shop-demo`. GitHub OIDC requires IAM identity-provider
access; the new AWS experience may restrict this until advanced features are
activated. Activation and billing changes are owner-managed prerequisites.

1. Request an ACM DNS-validated certificate for the application domain in `us-east-2`.
   Add its validation CNAME in Squarespace and wait for `ISSUED`.
2. Validate all three templates with `cfn-lint` and CloudFormation Guard, then
   review a CloudFormation change set for `platform.yml`.
3. Deploy `platform.yml` as `juice-shop-demo-platform`, supplying `CertificateArn`
   and `AllowedClientCidr`
   and allowing IAM resource creation. Add a Squarespace CNAME with host
   `juice-shop` and value from the `LoadBalancerDns` stack output.
4. Ensure the ECS service-linked role exists. Deploy `github.yml` as
   `juice-shop-demo-github`, supplying `RepositoryArn` and `ExecutionRoleArn`
   from the platform outputs. If the GitHub OIDC provider already exists, supply
   `ExistingProviderArn` instead of creating a duplicate.
5. Create GitHub environment `demo`, restrict deployments to branch `main`, and
   set its `AWS_DEPLOY_ROLE_ARN` variable to the GitHub stack's `DeployRoleArn`.
   The trust policy's `GitHubSubject` must match the repository's actual OIDC
   configuration, including immutable owner/repository IDs where enabled.
6. Merge the deployment workflow to `main` and run **Deploy**.

The `platform.yml` and `github.yml` stacks are administrator-managed. The pipeline
can only publish images and change `juice-shop-demo-service`; it cannot edit its
own trust policy or the platform network. `service.yml` remains the source of truth
for every release, avoiding direct ECS updates that drift from CloudFormation.

## Release and rollback

Push or merge a change to `main` to run checks, build, deploy, and verify ECS stability
and load-balancer target health. The target health check calls the product API.
GitHub runners do not receive application ingress access. The workflow summary records both the previous image and the new
digest. Immutable ECR tags contain the commit SHA, run ID, and attempt number.

To roll back, run **Deploy** manually from `main` and enter the
previous image's `sha256:...` digest in `image_digest`. This reuses the existing
image instead of rebuilding it. The current service template still applies.

For an operator-driven release using the same deployment script:

```bash
AWS_PROFILE=juice-shop-demo AWS_REGION=us-east-2 \
  bash deploy/aws/release.sh '<repository-uri>@sha256:<digest>'
```

## Verification and operation

- From the allowed network, the homepage, JavaScript bundle, challenges API, and
  product API must work. Connections from other public IPs must be blocked.
- CloudFormation must report a completed deployment and ECS must have one healthy
  running task using the requested image digest.
- Application logs are retained for seven days in the platform's CloudWatch log
  group. ECR images and the log group are retained when the platform stack is
  deleted; remove them separately only when no longer needed.
- Keep the certificate-validation CNAME for renewal.
- The load balancer, task, public IP addresses, logs, and images incur usage charges.
  Stopping the task alone does not stop load-balancer charges.
- CloudTrail event history provides 90-day management-event visibility. No durable
  audit trail is provisioned by these templates.
- Blockchain and AI challenges need separately configured external services; they
  are not part of this deployment.

To decommission the deployment, delete the service stack before the platform stack to release the
compute and load balancer. Then remove the GitHub stack, retained images/logs,
certificate, and DNS records if they are no longer required. Review dependencies
and obtain owner approval before deleting resources.
