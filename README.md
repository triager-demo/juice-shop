# Juice Shop

Juice Shop is a storefront application with an Angular frontend and a
Node.js/Express backend. It includes a product catalog, customer accounts,
shopping baskets, and order management.

## Local development

Use Node.js 24 (the project supports Node.js 22–26).

```bash
npm ci
npm run build
NODE_ENV=storefront npm start
```

Open http://localhost:3000. After source changes, run `npm run build`, or use `NODE_ENV=storefront npm run serve:dev`
for development with automatic rebuilds.

## Docker

Build this fork using the root Dockerfile:

```bash
docker build -t juice-shop .
docker run --rm -p 127.0.0.1:3001:3000 -e NODE_ENV=storefront juice-shop
```

Open http://localhost:3001. Application data resets on startup.

## Deployment

The deployment targets `https://juice-shop.stuartmehrens.com` on ECS Fargate in
`us-east-2`. GitHub Actions checks changes, publishes an image to ECR, and deploys
by immutable digest using OIDC credentials.

See [AWS deployment instructions](deploy/aws/README.md) for setup, DNS, releases,
rollback, and cleanup. The files under `infrastructure/` are challenge fixtures
and must never be used to provision actual infrastructure.

## Checks

```bash
npm run lint
npm test
npm run rsn
npm run build
```

Cypress end-to-end tests run with `npm run test:e2e` against a running application.

## License

Based on [OWASP Juice Shop](https://github.com/juice-shop/juice-shop).
Copyright © 2014–2026 Bjoern Kimminich & the OWASP Juice Shop contributors.
Distributed under the [MIT license](LICENSE).
