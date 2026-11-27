# Exercise Trends

**Status:** In progress · **Created:** 2026-11-27 · **Owner:** seththeeke

See how each exercise has progressed over time. Three ways in:

1. **Recent Exercises** dashboard card: the 10 exercises performed most recently. Tap one to open its trend.
2. **Workout detail** (from Recent Workouts or History): tap any exercise in the workout to open its trend.
3. **Personal Records** card: each row gets a sparkline of its last 10 sessions under the weight, without making the row taller. Rows are also tappable.

There is no exercise search.

## 1. What exists today, and why it isn't enough

`metrics-processor` (the DynamoDB stream consumer on `repwise-workouts`) keeps one row per user per exercise in `repwise-metrics`:
`PK = USER#<userId>`, `SK = METRIC#EXERCISE#<exerciseId>`. That row has a `trendData` array, and every completed workout appends one point to it (`{date, avgWeight, weightUnit, totalVolume}`).

Problems with using it for this feature:

| Problem | Effect |
|---|---|
| `trendData` grows without limit inside the summary row | `GET /metrics/me/exercises`, which the dashboard calls on every load, reads **every point for every exercise** just to return a few summary fields. DynamoDB charges for the whole item size even with a projection. The handler also doesn't paginate, so once the rows add up to more than 1 MB the list is silently cut short. Long term, a single row could approach the 400 KB item limit. |
| A point's `date` is the day the processor ran, in UTC | Late-evening workouts land on the next day, and nothing links a point to its workout. |
| Appending isn't idempotent | If a stream batch is retried, the point is appended twice. |
| No timestamp precision | There's no reliable way to order "most recent" exercises within a day. |

## 2. Data changes (table `repwise-metrics`, no new tables, no new GSIs)

### 2.1 New item: one per exercise per completed workout

```
PK  = USER#<userId>
SK  = SESSION#<exerciseId>#<completedAt ISO-8601>
exerciseId, workoutInstanceId, completedAt,
weight, weightUnit, sets?, reps?, durationSeconds?, modality
```

- **Written by** `metrics-processor` in the same transaction as the summary rows, using the workout's real `completedAt`.
- **Idempotent:** the key is fully determined by the workout, so a retried stream record writes the same item again instead of adding a duplicate.
- **Read pattern:** one `Query` with `PK = USER#<id> AND SK BETWEEN SESSION#<exerciseId>#<from> AND SESSION#<exerciseId>#~`. This returns just one exercise's points, already sorted by time, and uses no index. The trailing `#` means `bench-press` can't match `bench-press-incline`.
- **Size:** about 200 bytes per item. Three years of 3×/week on a single lift is about 450 items (about 90 KB, or about 12 RCU eventually consistent) for an all-time chart, and that is the worst case.
- If an exercise appears twice in one workout, the session with the heavier weight is kept.
- Skipped exercises don't produce a session (same as today).
- **Account deletion** already wipes the whole `USER#<id>` partition in this table (`deleteAllItemsWithPk`), so it needs no change. Nothing else queries this partition without an SK prefix, so these items can't leak into other reads. The goals code reads `GOAL#…` and `METRIC#…` by key or prefix.

### 2.2 Changes to the summary row `METRIC#EXERCISE#<exerciseId>`

| Field | Change | Why |
|---|---|---|
| `lastPerformedAt` | **new**, the ISO `completedAt` of the latest session | Exact ordering for "10 most recent exercises" |
| `recentSessions` | **new**, the last 10 sessions `{completedAt, weight, weightUnit, reps?, durationSeconds?}`, oldest first, capped at 10 | Sparklines and the "change since last session" figure come from the dashboard call the app already makes, so no extra requests |
| `trendData` | **trimmed to the last 180 days** on each write, instead of growing forever | Keeps the row a fixed size. 180 days is the longest window used by `avgWeightLast30/90/180`, the only remaining readers. Full history now lives in the session items |

Together these keep `GET /metrics/me/exercises` at one small, bounded query per dashboard load, no matter how long someone has used the app.

### 2.3 Backfill (one time)

Existing rows don't backfill themselves. `packages/lambdas/metrics-processor/scripts/backfill-exercise-sessions.mjs` reads every completed workout (the workouts table is the source of truth, and its rows have the real `completedAt` and `workoutInstanceId`), then:

- puts the `SESSION#` items, which is idempotent and safe to re-run, and
- sets `recentSessions` and `lastPerformedAt` on each summary row with an `UpdateItem` that touches only those two attributes.

It can be limited to one user with `--user <userId>`, and `--dry-run` prints the plan without writing. Run it after the backend deploy.

## 3. Endpoints

### Changed: `GET /metrics/me/exercises`
- Each item now also includes `lastPerformedAt` and `recentSessions` (both additive, so older clients are unaffected).
- The handler now paginates the query and uses a `ProjectionExpression` that leaves out `trendData` and `personalRecordHistory` from what is sent over the wire.

### New: `GET /metrics/me/exercises/{exerciseId}/sessions[?from=YYYY-MM-DD]`
```json
{ "exerciseId": "chest-barbell-bench-press",
  "sessions": [ { "completedAt": "2026-11-02T15:18:00.000Z", "workoutInstanceId": "…",
                  "weight": 95, "weightUnit": "LBS", "sets": 3, "reps": 8, "modality": "sets_reps" } ] }
```
- Sorted oldest first. `from` is optional and inclusive, and it limits the query by key range, not with a filter.
- Served by the existing `metrics` Lambda. The route is added in `repwise-stack.ts`.
- Returns an empty `sessions` array, not a 404, when there's no history.

### Unchanged
`GET /metrics/me/exercises/{exerciseId}` keeps working, but its `trendData` now covers at most 180 days. No client uses it.

## 4. How the app fetches data

- **Dashboard:** no new requests. Recent Exercises and the PR sparklines both come from the existing `GET /metrics/me/exercises` response.
- **Trend screen:** one `…/sessions` call per exercise with **no `from`** (all time). The 30d / 90d / YTD / All filters are applied in the app, so switching filters is instant and the chart can animate between ranges instead of waiting on a request. Responses are cached in memory per exercise until the next dashboard refresh. Even the all-time response is bounded (see §2.1).

## 5. Frontend brief (Rook, SwiftUI)

- **Metric plotted:** the session's working weight, converted to the profile's unit. If an exercise has never had any weight logged (bodyweight), reps are plotted instead. Duration exercises plot minutes. Sauna is left out of Recent Exercises.
- **Relative progression:** each chart sets its Y axis from the minimum and maximum of the points in view, with padding, and never starts at zero. Flat series get a small minimum span so a 2 lb change still shows up. The header shows the latest value and the change over the selected range (for example `+20 lb · +17%`), so a 7.5 → 9 lb lateral raise reads as +20% next to bench's +17%.
- **Range filters:** a segmented control for Past 30 days / Past 90 days / YTD / All Time. Every series is always plotted, and the X and Y domains animate to the new range (plot clipped), so the line zooms smoothly rather than redrawing. If a range has no sessions, an empty state is shown.
- **Recent Exercises card:** up to 10 rows, sorted by `lastPerformedAt` (falling back to `lastPerformedDate`). Each row shows the name, the relative day, the last weight, and the change since the previous session. Tapping a row opens the trend screen.
- **Personal Records card:** a roughly 60×14 pt sparkline sits under the weight text (no axes or labels), drawn from `recentSessions`. It's green when trending up and neutral otherwise. Rows open the trend screen.
- **Workout detail:** each exercise row becomes a navigation link to the trend screen, except for Sauna.
- **Code:** `ExerciseTrendModel` (filtering, Y domain, change calculation) and the model or API additions go in RookKit with tests. Views go in `Rook/Features/Trends/`. There's a new `AppRoute.exerciseTrend(id:name:)`.

## 6. Rollout

1. Deploy the backend: the processor writes sessions and trims `trendData`, plus the metrics endpoints and the route.
2. Run the backfill.
3. Ship the app. An older backend just means no sparklines, and the trend screen shows its error state.

## 7. Out of scope / known gaps

- Deleting or editing a completed workout still doesn't update metrics (true today too), so session items can't go stale through a path that didn't already exist.
- No per-set data: the workout model stores one weight per exercise per workout.
