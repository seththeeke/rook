# Repwise

Fitness app for building (manually or with AI), executing, and tracking workouts, with goals and a social feed. Web SPA + native iOS (Capacitor) on an AWS serverless backend. Product overview: [README.md](README.md). Human setup guide: [DEPLOYMENT.md](DEPLOYMENT.md).

## Layout (pnpm monorepo, `packages/**`)

| Path | What |
|------|------|
| `packages/cdk` | Single CDK stack `RepwiseStack` (`lib/repwise-stack.ts` wires everything; `tables.ts`, `auth.ts`, `api.ts`, `website.ts` are constructs) |
| `packages/lambdas/shared` | `@repwise/shared` — models, enums, DDB client, response helpers, goal evaluation, feed fan-out. **Source of truth for types used by both backend and web** |
| `packages/lambdas/<name>` | One Lambda per domain: `user`, `gyms`, `exercise`, `workout`, `metrics`, `metrics-processor` (DDB stream consumer), `goals`, `goals-ai`, `feed`, `ai` (SSE workout builder + admin config), `cognito-post-confirm`, `cleanup-user-data` (DELETE /users/me) |
| `packages/web` | React 18 + Vite + Tailwind + Zustand + TanStack Query + Amplify auth. Also hosts the Capacitor iOS project in `packages/web/ios` |
| `packages/capacitor-workout-live-activity` | Local Capacitor plugin (Swift) for the workout Live Activity / Dynamic Island |
| `packages/integration-tests` | Vitest suite that runs against the **deployed** API (no unit tests exist in the repo) |
| `specs/` | Design specs/plans. `specs/bug-tracker.md` is the running bug list; `specs/polishing/` holds polish ideas (`completed/`, `deferred/`) |
| `ios-app/` | Native Swift/SwiftUI rebuild of the iOS app, rebranded **Rook**. Plan and phase status: `specs/ios-native-rebuild-plan.md`. Uses the same backend; backend code must not change for it |
| `prototype-app/` | Standalone mock-data React prototype. Not in the pnpm workspace (uses npm) — legacy, rarely touched |
| `scripts/` | `clear-user-data.sh`, `clear-test-user-data.sh` (DynamoDB resets for a single user) |

## Commands

```bash
pnpm install
pnpm build                                   # pnpm -r build: tsc for lambdas/cdk, vite build for web
pnpm --filter web dev                        # local web app (needs packages/web/.env.local, see .env.example)
pnpm --filter web typecheck                  # web type check (vite build does NOT type check)
pnpm --filter @repwise/<lambda> build        # type check a single lambda
pnpm --filter @repwise/integration-tests test [file-filter]   # hits the deployed API; needs .env.test
cd packages/cdk && pnpm run cdk diff         # preview infra changes
pnpm build:ios && pnpm --filter web cap:open:ios   # build web, cap sync, open Xcode
```

Always use the project's CDK (`pnpm run cdk …` / `pnpm --filter cdk …`), never a global `cdk` — schema version mismatches. Deploying: use the `/deploy-stack` skill.

## Architecture essentials

- **API**: API Gateway HTTP API at `https://api.repwisefit.com`, Cognito JWT authorizer. All routes are declared in `repwise-stack.ts` via `api.addRoute(method, path, lambda, requiresAuth)` — adding an endpoint means a handler branch in the Lambda **and** a route there. Lambdas are `NodejsFunction` (esbuild bundles from `src/index.ts`, Node 20).
- **AI workout builder**: `lambdas/ai` `streamHandler` is exposed as a **Lambda Function URL** with response streaming (SSE), not via API Gateway (avoids 30s timeout). It verifies the Cognito JWT itself (`aws-jwt-verify`). Uses **Bedrock** `Converse` (default `amazon.nova-micro-v1:0`); allowed model IDs are listed in both `repwise-stack.ts` (IAM) and `ai/src/index.ts` — keep them in sync. Prompt templates and model choice live in the `repwise-workout-builder-ai-config` table, editable from `/admin/builder-ai` (requires Cognito group `builder-admin`).
- **Tables** (all `PK`/`SK` single-table style, fixed names): `repwise-users` (profiles `USER#id`/`PROFILE`, gyms, follows, feed; GSI `username-index`), `repwise-workouts` (exercise catalog + workout instances `WORKOUT#…`; GSIs `muscleGroup-index`, `equipment-index`, `userId-completedAt-index`; **stream enabled**), `repwise-metrics` (`METRIC#GLOBAL`, `METRIC#EXERCISE#…`, goals), `repwise-workout-builder-sessions`, `repwise-workout-builder-ai-config`.
- **Metrics & goals are derived, not computed on read**: `metrics-processor` consumes the workouts table stream on workout completion, updates metrics/PRs/streaks and evaluates goals (`evaluateGoals` in shared). Changing metric shape means changing the processor; existing rows won't backfill.
- **Feed** is fan-out on write (`shared/src/feedFanout.ts`, called from the workout Lambda).
- **Workouts are instance-only** — no templates; `source` (manual/AI) is stored on each instance.
- **Web**: routes in `packages/web/src/App.tsx`; feature folders under `src/features/*`; API wrappers in `src/api/*` on a shared axios client (`api/client.ts`) that attaches the Cognito ID token and retries 5xx/network errors. Shared UI primitives in `src/components/ui`. Active workout state persists in `stores/workoutSessionStore.ts`.
- **Hosting**: S3 + CloudFront for `repwisefit.com`; the CDK `BucketDeployment` uploads `packages/web/dist`, so **web must be built (with `.env.production`) before deploy**.
- **CORS is `*`** on purpose: Capacitor sends `capacitor://` origins that API Gateway/Function URLs can't allow-list. Auth is JWT, not cookies.

## Gotchas

- `packages/web/src/types/index.ts` re-exports straight from `lambdas/shared/src/*.ts`; `vite.config.ts` aliases `@shared` and rewrites `shared/src/enums.js` → `enums.ts`. Keep shared enums/models free of Node-only imports or the web build breaks.
- `packages/lambdas/shared/src/` contains committed compiled `.js`/`.d.ts` files for some modules — edit the `.ts`, never these.
- `packages/web` has both `vite.config.ts` and a stale `vite.config.js`; the `.ts` one is authoritative.
- `VITE_*` values are baked in at build time. iOS needs `pnpm build:ios` after any env change.
- Route53 hosted zone `repwisefit.com` is looked up at synth time, so synth/deploy needs AWS credentials for the real account.
- `cap:sync` runs two post-sync scripts (`scripts/ios-link-capacitor-workout-live-activity.mjs`, `ios-append-keychain-plugin.mjs`) that patch the Xcode project — always sync through the npm script, not `npx cap sync`.
- Not implemented despite older docs: CloudWatch alarms/dashboard (`specs/monitoring-spec.md`) and GitHub Actions CI. No linter is configured for the workspace.

## Working agreements

- Verify changes with the narrowest build/typecheck for what you touched (`pnpm --filter web typecheck`, `pnpm --filter @repwise/<pkg> build`, `pnpm --filter cdk build`).
- Integration tests and the `scripts/clear-*` scripts operate on **real deployed data** — ask before running them.
- Never commit `.env*` files (only `*.example`), `cdk-outputs.json`, or `deploy-outputs.json`.
- New features usually start as a spec in `specs/`; update the relevant spec when behavior changes.
