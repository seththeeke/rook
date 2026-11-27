#!/usr/bin/env node
/**
 * One-time backfill for specs/exercise-trends.md §2.3.
 *
 * From every completed workout (the source of truth) it:
 *   - puts `SESSION#<exerciseId>#<completedAt>` items in repwise-metrics (idempotent; safe to re-run), and
 *   - sets `recentSessions` + `lastPerformedAt` on existing `METRIC#EXERCISE#<id>` rows (UpdateItem of
 *     only those attributes; rows that don't exist are left alone).
 *
 * Mirrors the key/merge logic in packages/lambdas/shared/src/exerciseSessions.ts.
 *
 * Usage (from repo root, with AWS credentials for the account):
 *   node packages/lambdas/metrics-processor/scripts/backfill-exercise-sessions.mjs [--user <userId>] [--dry-run]
 */
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import {
  BatchWriteCommand,
  DynamoDBDocumentClient,
  QueryCommand,
  ScanCommand,
  UpdateCommand,
} from '@aws-sdk/lib-dynamodb';

const WORKOUTS_TABLE = 'repwise-workouts';
const METRICS_TABLE = 'repwise-metrics';
const RECENT_SESSIONS_LIMIT = 10;

const args = process.argv.slice(2);
const dryRun = args.includes('--dry-run');
const userIdx = args.indexOf('--user');
const onlyUser = userIdx >= 0 ? args[userIdx + 1] : undefined;
if (userIdx >= 0 && !onlyUser) {
  console.error('--user needs a userId');
  process.exit(1);
}

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}), {
  marshallOptions: { removeUndefinedValues: true },
});

async function completedWorkouts() {
  const items = [];
  let lastKey;
  do {
    const out = onlyUser
      ? await ddb.send(new QueryCommand({
          TableName: WORKOUTS_TABLE,
          IndexName: 'userId-completedAt-index',
          KeyConditionExpression: 'userId = :u',
          ExpressionAttributeValues: { ':u': onlyUser },
          ExclusiveStartKey: lastKey,
        }))
      : await ddb.send(new ScanCommand({
          TableName: WORKOUTS_TABLE,
          FilterExpression: 'attribute_exists(workoutInstanceId) AND #s = :c',
          ExpressionAttributeNames: { '#s': 'status' },
          ExpressionAttributeValues: { ':c': 'completed' },
          ExclusiveStartKey: lastKey,
        }));
    items.push(...(out.Items ?? []));
    lastKey = out.LastEvaluatedKey;
  } while (lastKey);
  return items.filter((w) => w.status === 'completed' && w.completedAt && w.userId);
}

function loggedExercisesById(workout) {
  const byId = new Map();
  for (const ex of workout.exercises ?? []) {
    if (ex.skipped || !ex.exerciseId) continue;
    const existing = byId.get(ex.exerciseId);
    if (!existing || (ex.weight ?? 0) > (existing.weight ?? 0)) byId.set(ex.exerciseId, ex);
  }
  return [...byId.values()];
}

function sessionItem(workout, ex) {
  return {
    PK: `USER#${workout.userId}`,
    SK: `SESSION#${ex.exerciseId}#${workout.completedAt}`,
    userId: workout.userId,
    exerciseId: ex.exerciseId,
    workoutInstanceId: workout.workoutInstanceId,
    completedAt: workout.completedAt,
    modality: ex.modality,
    weight: ex.weight ?? 0,
    weightUnit: ex.weightUnit ?? 'LBS',
    sets: ex.sets,
    reps: ex.reps,
    durationSeconds: ex.durationSeconds,
  };
}

function recentSession(item) {
  return {
    completedAt: item.completedAt,
    weight: item.weight,
    weightUnit: item.weightUnit,
    reps: item.reps,
    durationSeconds: item.durationSeconds,
  };
}

async function putAll(items) {
  for (let i = 0; i < items.length; i += 25) {
    let request = { [METRICS_TABLE]: items.slice(i, i + 25).map((Item) => ({ PutRequest: { Item } })) };
    for (let attempt = 0; request && Object.keys(request).length > 0; attempt++) {
      if (attempt > 0) await new Promise((r) => setTimeout(r, 100 * 2 ** attempt));
      const out = await ddb.send(new BatchWriteCommand({ RequestItems: request }));
      request = out.UnprocessedItems;
    }
  }
}

async function main() {
  const workouts = await completedWorkouts();
  // userId → exerciseId → session items
  const byUser = new Map();
  for (const w of workouts) {
    for (const ex of loggedExercisesById(w)) {
      const perUser = byUser.get(w.userId) ?? new Map();
      byUser.set(w.userId, perUser);
      const list = perUser.get(ex.exerciseId) ?? [];
      perUser.set(ex.exerciseId, list);
      list.push(sessionItem(w, ex));
    }
  }

  let sessionCount = 0;
  let rowsUpdated = 0;
  for (const [userId, perExercise] of byUser) {
    const all = [...perExercise.values()].flat();
    sessionCount += all.length;
    console.log(`${userId}: ${all.length} sessions across ${perExercise.size} exercises`);
    if (!dryRun) await putAll(all);

    for (const [exerciseId, sessions] of perExercise) {
      sessions.sort((a, b) => a.completedAt.localeCompare(b.completedAt));
      const recent = sessions.slice(-RECENT_SESSIONS_LIMIT).map(recentSession);
      const lastPerformedAt = sessions[sessions.length - 1].completedAt;
      if (dryRun) continue;
      try {
        await ddb.send(new UpdateCommand({
          TableName: METRICS_TABLE,
          Key: { PK: `USER#${userId}`, SK: `METRIC#EXERCISE#${exerciseId}` },
          UpdateExpression: 'SET recentSessions = :r, lastPerformedAt = :l',
          ConditionExpression: 'attribute_exists(PK)',
          ExpressionAttributeValues: { ':r': recent, ':l': lastPerformedAt },
        }));
        rowsUpdated++;
      } catch (err) {
        if (err.name !== 'ConditionalCheckFailedException') throw err;
        console.warn(`  no summary row for ${exerciseId}; skipped recentSessions`);
      }
    }
  }
  console.log(
    `${dryRun ? '[dry run] would write' : 'Wrote'} ${sessionCount} session items for ${byUser.size} users` +
      (dryRun ? '' : `; updated ${rowsUpdated} summary rows`)
  );
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
