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
The HTTPS host rule additionally requires an invited Cognito account and authenticator-app
MFA before forwarding any path, including API requests. Update the IP parameter when
changing networks or when the ISP changes the address. The ALB can make outbound HTTPS
requests to Cognito; application ingress remains ALB-only.

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

## Operator authentication

The platform provisions an Essentials Cognito user pool with self-registration disabled,
required TOTP MFA, and a Cognito-provided classic hosted login domain. The ALB uses a
secret-bearing authorization-code client scoped to `openid`; no secret is exported or
passed to Juice Shop. Cognito login is separate from Juice Shop challenge accounts.
The callback is exactly `https://juice-shop.stuartmehrens.com/oauth2/idpresponse`
(or the configured `DomainName`). No additional DNS record is required.

For an existing deployment, update only `juice-shop-demo-platform` from a reviewed
CloudFormation change set using profile `juice-shop-demo` in `us-east-2`. Reuse all
existing parameter values, use the default `AuthDomainPrefix=juice-shop-demo`, and allow IAM capabilities.
For another environment in the same account and Region, choose a distinct lowercase prefix. The administrator needs Cognito
resource-management permissions and `cognito-idp:DescribeUserPoolClient` for ALB
configuration. Expect three new Cognito resources, an updated HTTPS host rule, ALB
outbound TCP 443, and new authentication outputs. No ECS service or task replacement
is needed. All visitors will need an invitation once the update completes.

Read `AuthUserPoolId` from the platform stack outputs. In the Cognito console, select
that pool and create each approved user with their email address, send an email invitation,
and let Cognito generate the temporary password. Do not put passwords in CLI arguments
or source control. Invitations expire after three days; resend an invitation if needed.
On first login, users choose a permanent password and enroll an authenticator app.
After login, Cognito redirects back to the application through the ALB callback.

To remove access, disable the user in Cognito and perform an administrator global sign-out.
Existing ALB sessions are separate and can remain usable until their one-hour expiry;
do not treat account disablement as immediate cookie revocation. For urgent shutdown,
block ingress through the administrator-managed security group while investigating.
Juice Shop logout only ends its own application session, not the outer Cognito/ALB session.
Use a private browser session and close it after use on shared devices. Expiring the ALB
session can still allow login through a valid Cognito browser session without another MFA
prompt; the one-hour ALB timeout does not force hourly MFA.

The user pool is retained on stack deletion or replacement to preserve operator accounts.
Review retained pools separately during decommissioning. Do not roll back to a template
without authentication merely to troubleshoot login: that would restore IP-only access.

Cognito Essentials includes a shared allowance of 10,000 direct monthly active users;
a small invited audience should stay within it. Authenticator MFA avoids SMS charges.
See [Cognito pricing](https://aws.amazon.com/cognito/pricing/) for current allowances
and email costs.

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

- From the allowed network in a fresh private browser, both the homepage and a direct
  `/rest/products/search` request must redirect to Cognito before returning application data.
  Confirm there is no public signup, an invited user must enroll MFA, and the homepage,
  JavaScript bundle, challenges API, and product API work after login. Use another fresh
  session to check an incorrect password is rejected. Connections from other public IPs
  must remain blocked. An unrelated Host header must still receive the default 404.
- Target-group health checks must remain healthy: they reach tasks directly from the ALB
  and do not use the browser authentication rule.
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
