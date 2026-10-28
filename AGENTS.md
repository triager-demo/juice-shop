# Repository guidance

This repository contains the Juice Shop storefront: an Angular frontend, an
Express API, and SQLite-backed application data. Deployment uses ECS Fargate
and GitHub Actions.

## Working conventions

- Inspect adjacent code and follow existing TypeScript, Angular, and JS Standard
  Style conventions. Keep changes focused and preserve work already in progress.
- Use `config/default.yml` and `lib/config.schema.ts` for configuration facts, and
  `models/challenge.ts` and `data/static/challenges.yml` for challenge identifiers.
- Keep behavior changes scoped to the requested task. Files under `ftp/`,
  `.well-known/`, `encryptionkeys/`, and `infrastructure/` may be required at
  runtime; check their consumers before changing or removing them.
- Do not edit `i18n/*.json` translations directly.
- Preserve license and copyright notices. Avoid redundant comments and generated
  documentation that does not help maintain the application.

## Build and verification

Use Node.js 24. `npm ci` installs locked backend and frontend dependencies. Run `npm run build`
to build the application.
Run `NODE_ENV=storefront npm start` for the storefront configuration, or
`NODE_ENV=storefront npm run serve:dev` during development.

- Run `npm run lint` before committing.
- Run `npm test` for application code changes, and `npm run build` to verify builds.
- Run Cypress (`npm run test:e2e` against a running app) for changed challenge flows.
- Run `npm run rsn` when changing code used by coding challenges. Keep corresponding
  `data/static/codefixes/` files consistent; do not refresh the RSN cache merely to
  hide a failure.
- Report failing or blocked checks accurately. Documentation-only changes need
  link/reference checks rather than the full application test suite.

## Deployment

- Build the root `Dockerfile`. Real deployment templates and the release script
  live in `deploy/aws/`; operational instructions are in `deploy/aws/README.md`.
- Never provision the fixtures in `infrastructure/`; use `deploy/aws/`.
- AWS CLI profile: `juice-shop-demo`; selected Region: `us-east-2`.
- Domain: `juice-shop.stuartmehrens.com`; DNS is managed in Squarespace.
- GitHub Actions uses the `demo` environment and AWS OIDC. Keep credentials out of
  source control and logs. Deploy immutable ECR image digests.
- Keep one ECS task: SQLite data is local and resets on startup. Releases can cause
  a brief outage and reset application data.

## Git workflow

Use focused feature branches from `main` and review changes through pull
requests. Sign off commits with `git commit -s`. The deployment workflow runs on
`main`; preserve its verification and rollback steps.
