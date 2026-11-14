# Rook — Deployment & Development Guide

This document covers how to build, deploy, and run Rook (web, iOS, and backend). For a product overview, see [README.md](README.md).

---

## Tech Stack

| Layer | Technology |
|-------|------------|
| **Backend** | Node.js 20.x, TypeScript, AWS Lambda, API Gateway (HTTP API), DynamoDB, Cognito |
| **AI** | AWS Bedrock (Converse API; Nova and Claude models, chosen in the admin builder config), SSE via a Lambda Function URL |
| **Frontend** | React 18, TypeScript, Vite, Tailwind CSS, React Router, Zustand, TanStack Query, AWS Amplify (Cognito); native iOS via Capacitor |
| **Infrastructure** | AWS CDK (TypeScript), single stack `RepwiseStack`; deployed manually (no CI/CD yet) |
| **Monitoring** | CloudWatch Logs only today; alarms/dashboard are specced in `specs/monitoring-spec.md` but not built |
| **Package manager** | pnpm |

---

## Repository structure

The project is a **pnpm monorepo**:

```
/
├── packages/
│   ├── cdk/                    # AWS CDK infrastructure (tables, auth, API, monitoring)
│   ├── lambdas/
│   │   ├── shared/             # Shared types, DDB client, utilities (source of truth for models)
│   │   ├── user/               # User + follow endpoints
│   │   ├── gyms/               # User gyms (equipment sets)
│   │   ├── feed/               # Feed endpoint
│   │   ├── exercise/           # Exercise catalog endpoints
│   │   ├── workout/            # Workout instance CRUD + AI invoke
│   │   ├── metrics/            # Metrics read endpoints
│   │   ├── goals/              # Goals CRUD endpoints
│   │   ├── goals-ai/           # AI goal suggestions
│   │   ├── metrics-processor/  # DynamoDB Streams → update metrics & goals (no API route)
│   │   ├── ai/                 # AI workout generation (SSE via Function URL) + admin builder config
│   │   ├── cleanup-user-data/  # Account deletion (DELETE /users/me)
│   │   └── cognito-post-confirm/
│   ├── capacitor-workout-live-activity/  # Local Capacitor plugin for Live Activity / Dynamic Island
│   ├── web/                    # React frontend + Capacitor iOS project (web/ios)
│   └── integration-tests/     # Vitest integration tests (run against deployed API)
├── specs/                      # Implementation specs, plans, polishing ideas, bug tracker
│   ├── backend-spec.md         # Backend & infrastructure
│   ├── frontend-spec.md        # Web app
│   └── monitoring-spec.md      # CloudWatch alarms & dashboard
├── pnpm-workspace.yaml
└── tsconfig.base.json
```

- **Backend** and **frontend** types are shared: `packages/lambdas/shared` is the single source of truth; `packages/web` re-exports from it.
- **Specs** in `specs/` define phases and implementation order; build the stack by following them in sequence.

---

## Specs and build order

Implementation is specified in the `specs/` directory. Use them in this order:

1. **Backend & infrastructure** — [specs/backend-spec.md](specs/backend-spec.md)  
   Project scaffold, shared package, CDK (tables, Cognito, API Gateway, Lambdas), user, exercise, workout, metrics processor, metrics read, goals, feed, AI Lambda, route wiring, CI/CD.

2. **Frontend** — [specs/frontend-spec.md](specs/frontend-spec.md)  
   Scaffold, API client, auth (Cognito/Amplify), stores, design system, dashboard, workout builder, workout execution, catalog, metrics & exercise detail, goals, feed, profile & settings, routing, desktop layout.

3. **Monitoring** _(not yet implemented)_ — [specs/monitoring-spec.md](specs/monitoring-spec.md)  
   CloudWatch dashboard, alarms, log groups, optional SNS email alerts. Designed for free-tier-first and minimal custom metrics.

4. **Integration tests** — [specs/integration-test-spec.md](specs/integration-test-spec.md)  
   Vitest suite in `packages/integration-tests/` that runs against the deployed API (auth, profile, exercises, workouts, metrics, goals, social). Requires `.env.test` with API URL and Cognito test user credentials.

---

## Prerequisites

- **Node.js** 20.x  
- **pnpm**  
- **AWS CLI** configured (for deploy and seed)  
- **AWS CDK** bootstrap in the target account/region (one-time)

---

## Quick start

```bash
pnpm install
pnpm -r build
```

- **Deploy (backend + website):**  
  Create `packages/web/.env.production` from `.env.production.example` (the website is built from it), run `pnpm -r build`, then from `packages/cdk`: `pnpm run deploy -- --require-approval never`.  
  Always use the project's CDK CLI through pnpm. A global `cdk` can cause schema version mismatches. Bedrock model access must be enabled in the account for the AI builder. Seed the exercise catalog once per new environment (see `packages/lambdas/exercise/scripts/`). See [packages/cdk/README.md](packages/cdk/README.md) for domains, OAuth, and Sign in with Apple.

- **Run frontend:**  
  `pnpm --filter web run dev`  
  Copy `packages/web/.env.example` to `packages/web/.env.local` and set `VITE_COGNITO_USER_POOL_ID` and `VITE_COGNITO_CLIENT_ID` (same values as integration tests) so the Amplify login/signup/forgot-password flow works. Set `VITE_API_BASE_URL` when the API is deployed.

- **Build & run iOS app (Capacitor):**  
  Repwise can run natively on iPhone via Capacitor. See [specs/capacitor-ios-plan.md](specs/capacitor-ios-plan.md) for full details. Quick flow: ensure `packages/web/.env.production` (or `.env.ios`) has the same `VITE_*` values as production; then `pnpm build:ios` (builds web + syncs to iOS), and `pnpm --filter web cap:open:ios` to open Xcode. Requires macOS and Xcode.

---

## Auth (Cognito) — manual steps for integration tests

The stack does not create test users. After deploying:

1. **Create a test user** in the User Pool (AWS Console → Cognito → User Pools → your pool → Create user), or via CLI:

   ```bash
   aws cognito-idp admin-create-user --user-pool-id <UserPoolId> \
     --username testuser@repwise-test.com \
     --user-attributes Name=email,Value=testuser@repwise-test.com Name=email_verified,Value=true \
     --temporary-password 'TempPass123!' --message-action SUPPRESS
   aws cognito-idp admin-set-user-password --user-pool-id <UserPoolId> \
     --username testuser@repwise-test.com --password 'TestPass123!' --permanent
   ```
   (Use the same for a second user if you need social tests: `testuser2@repwise-test.com`.)

2. **Copy CDK outputs into** `packages/integration-tests/.env.test`:
   - `API_BASE_URL` = stack output **ApiUrl** (e.g. `https://xxx.execute-api.us-east-1.amazonaws.com`)
   - `COGNITO_USER_POOL_ID` = stack output **UserPoolId**
   - `COGNITO_CLIENT_ID` = stack output **UserPoolClientId**
   - `TEST_USER_EMAIL=testuser@repwise-test.com`
   - `TEST_USER_PASSWORD=TestPass123!`
   - (Optional) `TEST_USER_2_EMAIL`, `TEST_USER_2_PASSWORD` for the second test user.

   **Exercise catalog:** So that `GET /exercises` returns data, run the seed once after deploy (see backend-spec or `packages/lambdas/scripts/seed-catalog.ts`), with `WORKOUTS_TABLE` set to the stack's workouts table name.

3. **Run the Cognito auth integration test:**

   ```bash
   pnpm --filter @repwise/integration-tests test -- src/tests/00-cognito-auth.test.ts
   ```

---

## Design decisions (reference)

| Area | Choice | Reason |
|------|--------|--------|
| Workouts | Instance-only, no "templates" | Simpler model; source (manual/AI) is stored on each instance |
| Metrics | Pre-built via DynamoDB Streams | Fast reads, no ad-hoc aggregation at request time |
| Goals | Stored in metrics table; evaluated in metrics-processor | Single write path, no cron; goals and metrics stay in sync |
| AI | SSE from a Lambda Function URL (response streaming) | Better UX and avoids API Gateway timeout limits |
| Feed | Fan-out at write time | Fast feed reads; follower counts are small |
| Types | Shared package in `lambdas/shared` | One source of truth for API and frontend |

---

## License

Proprietary. All rights reserved.
