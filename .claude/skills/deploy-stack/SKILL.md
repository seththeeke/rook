---
name: deploy-stack
description: Build and deploy the Repwise CDK stack (API, Lambdas, tables, Cognito, website) to AWS production. Use when the user asks to deploy, ship, push changes live, or update the live stack/website.
disable-model-invocation: true
---

# Deploy Stack

Deploys `RepwiseStack` (single CloudFormation stack, us-east-1 by default) to the production account. This is **production** — there is no staging stack.

## 1. Preflight

Run these from the repo root and stop on any failure:

```bash
aws sts get-caller-identity          # credentials present? (deploy needs the account that owns repwisefit.com in Route 53)
git status --short                   # tell the user if they're deploying uncommitted changes
```

- Optional Sign in with Apple: deploy reads `APPLE_SERVICES_ID`, `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY` from the environment. If they're unset, the Apple IdP is left out. Mention this only if the user cares about Apple sign-in.

## 2. Build

```bash
pnpm build
```

This builds every package, including `vite build` of the static marketing site into `packages/web/dist` (it needs no env vars). The CDK `BucketDeployment` uploads that folder, so a stale or missing `dist` means a stale website. Lambdas are re-bundled by esbuild during deploy, but `pnpm build` still type checks them.

## 3. Review (recommended)

```bash
cd packages/cdk && pnpm run cdk diff
```

Summarize the diff for the user. Call out anything **destructive**: table replacement, Cognito user pool or client replacement, or removed routes. Get explicit confirmation before going further if you see any.

## 4. Deploy

```bash
cd packages/cdk && pnpm run deploy -- --require-approval never
```

Use the project-local CDK through the pnpm script, never a global `cdk`. The first deploy on a new account can sit on ACM DNS validation for several minutes.

## 5. After deploy

- Report the stack outputs: `WebsiteUrl`, `ApiUrl`, `AiWorkoutStreamUrl`, `UserPoolId`, `UserPoolClientId`, `CognitoOAuthDomain`, `CloudFrontDistributionId`.
- If `AiWorkoutStreamUrl`, `UserPoolId`, `UserPoolClientId`, or `CognitoOAuthDomain` changed, tell the user: the native app reads these from `ios-app/Config/Base.xcconfig`, which needs updating and a new build.
- BucketDeployment invalidates CloudFront. If the site still looks stale: `aws cloudfront create-invalidation --distribution-id <CloudFrontDistributionId> --paths "/*"`.
- New environment and empty catalog only: seed exercises with `WORKOUTS_TABLE=repwise-workouts pnpm --filter @repwise/exercise seed full-exercise-database.json`. The default file is `catalog-minimal.json`.
- Offer to run the integration tests (`pnpm --filter @repwise/integration-tests test`). They hit production data with the test users.

## Synth only

```bash
cd packages/cdk && pnpm run synth
```
