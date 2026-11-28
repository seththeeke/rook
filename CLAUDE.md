# Rook

Fitness app for building (manually or with AI), executing, and tracking workouts, with goals and a social feed. Native iOS app (SwiftUI in `ios-app/`) on an AWS serverless backend, plus a static marketing website at `rookjournal.com`. The app was formerly called Repwise: the stack ID `RepwiseStack`, the `repwise-*` DynamoDB tables and the `repwise-user-pool` Cognito pool keep the old name on purpose because they are stateful (renaming replaces them and loses data). Use Rook everywhere else. Product overview: [README.md](README.md). Human setup guide: [DEPLOYMENT.md](DEPLOYMENT.md).

## Layout (pnpm monorepo, `packages/**`)

| Path | What |
|------|------|
| `packages/cdk` | Single CDK stack `RepwiseStack` (`lib/rook-stack.ts` wires everything; `tables.ts`, `auth.ts`, `api.ts`, `website.ts` are constructs) |
| `packages/lambdas/shared` | `@rook/shared` — models, enums, DDB client, response helpers, goal evaluation, feed fan-out. **Source of truth for backend types** |
| `packages/lambdas/<name>` | One Lambda per domain: `user`, `gyms`, `exercise`, `workout`, `metrics`, `metrics-processor` (DDB stream consumer), `goals`, `goals-ai`, `feed`, `ai` (SSE workout builder + admin config), `cognito-post-confirm`, `cleanup-user-data` (DELETE /users/me) |
| `packages/web` | Marketing website only (React 18 + Vite + Tailwind + framer-motion). No sign-in, no API calls, no env vars. Sections in `src/sections/*`, shared bits in `src/site/*` |
| `packages/integration-tests` | Vitest suite that runs against the **deployed** API (no unit tests exist in the repo) |
| `specs/` | Design specs/plans. `specs/bug-tracker.md` is the running bug list; `specs/polishing/` holds polish ideas (`completed/`, `deferred/`) |
| `ios-app/` | The app: native Swift/SwiftUI, branded **Rook**. Plan and phase status: `specs/ios-native-rebuild-plan.md`. Backend code must not change for it |
| `scripts/` | `clear-user-data.sh`, `clear-test-user-data.sh` (DynamoDB resets for a single user) |

## Commands

```bash
pnpm install
pnpm build                                   # pnpm -r build: tsc for lambdas/cdk, vite build for web
pnpm --filter web dev                        # local marketing site
pnpm --filter web typecheck                  # web type check (vite build does NOT type check)
pnpm --filter @rook/<lambda> build           # type check a single lambda
pnpm --filter @rook/integration-tests test [file-filter]      # hits the deployed API; needs .env.test
cd packages/cdk && pnpm run cdk diff         # preview infra changes
```

Always use the project's CDK (`pnpm run cdk …` / `pnpm --filter cdk …`), never a global `cdk` — schema version mismatches. Deploying: use the `/deploy-stack` skill.

## Architecture essentials

- **API**: API Gateway HTTP API at `https://api.rookjournal.com`, Cognito JWT authorizer. All routes are declared in `rook-stack.ts` via `api.addRoute(method, path, lambda, requiresAuth)` — adding an endpoint means a handler branch in the Lambda **and** a route there. Lambdas are `NodejsFunction` (esbuild bundles from `src/index.ts`, Node 20).
- **AI workout builder**: `lambdas/ai` `streamHandler` is exposed as a **Lambda Function URL** with response streaming (SSE), not via API Gateway (avoids 30s timeout). It verifies the Cognito JWT itself (`aws-jwt-verify`). Uses **Bedrock** `Converse` (default `amazon.nova-micro-v1:0`); allowed model IDs are listed in both `rook-stack.ts` (IAM) and `ai/src/index.ts` — keep them in sync. Prompt templates and model choice live in the `repwise-workout-builder-ai-config` table (the `/admin/builder-ai-config` API endpoints still exist for Cognito group `builder-admin`; the web admin page that used them was removed).
- **Tables** (all `PK`/`SK` single-table style, fixed names): `repwise-users` (profiles `USER#id`/`PROFILE`, gyms, follows, feed; GSI `username-index`), `repwise-workouts` (exercise catalog + workout instances `WORKOUT#…`; GSIs `muscleGroup-index`, `equipment-index`, `userId-completedAt-index`; **stream enabled**), `repwise-metrics` (`METRIC#GLOBAL`, `METRIC#EXERCISE#…`, per-session exercise history `SESSION#<exerciseId>#<completedAt>`, goals), `repwise-workout-builder-sessions`, `repwise-workout-builder-ai-config`.
- **Metrics & goals are derived, not computed on read**: `metrics-processor` consumes the workouts table stream on workout completion, updates metrics/PRs/streaks and evaluates goals (`evaluateGoals` in shared). Changing metric shape means changing the processor; existing rows won't backfill.
- **Feed** is fan-out on write (`shared/src/feedFanout.ts`, called from the workout Lambda).
- **Workouts are instance-only** — no templates; `source` (manual/AI) is stored on each instance.
- **Web** is a single marketing page (`packages/web/src/App.tsx` composes `src/sections/*`). The old React web app and Capacitor iOS shell were removed on 2026-11-15. Every CTA is a `mailto:` from `src/site/config.ts`.
- **Hosting**: S3 + CloudFront for `rookjournal.com`; the CDK `BucketDeployment` uploads `packages/web/dist`, so **web must be built before deploy**.
- **CORS is `*`** on purpose: native clients (including the legacy Capacitor build still installed on devices, which sends `capacitor://` origins) can't be allow-listed. Auth is JWT, not cookies.

## Gotchas

- `packages/lambdas/shared/src/` contains committed compiled `.js`/`.d.ts` files for some modules — edit the `.ts`, never these.
- Route53 hosted zone `rookjournal.com` is looked up at synth time, so synth/deploy needs AWS credentials for the real account.
- Not implemented despite older docs: CloudWatch alarms/dashboard (`specs/monitoring-spec.md`) and GitHub Actions CI. No linter is configured for the workspace.

## Working agreements

- Verify changes with the narrowest build/typecheck for what you touched (`pnpm --filter web typecheck`, `pnpm --filter @rook/<pkg> build`, `pnpm --filter cdk build`).
- Integration tests and the `scripts/clear-*` scripts operate on **real deployed data** — ask before running them.
- Never commit `.env*` files (only `*.example`), `cdk-outputs.json`, or `deploy-outputs.json`.
- New features usually start as a spec in `specs/`; update the relevant spec when behavior changes.
