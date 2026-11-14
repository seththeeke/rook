/**
 * One-off correction for workouts where the wrong exercise was logged.
 *
 * For the user's completed workouts on the given local dates that contain --from, it replaces that
 * exercise with --to (ID + name), optionally subtracts a fixed weight and forces sets/reps, recomputes
 * each workout's totalVolume (same rule as lambdas/workout), then rebuilds the per-exercise metrics for
 * BOTH exercises by replaying all of the user's completed workouts (same rules as metrics-processor),
 * and adjusts the global totalVolumeAllTime by the volume difference.
 *
 * Dry run by default: prints every change and writes nothing. Pass --apply to write. Before writing it
 * saves the original items to a backup folder (printed) so the change can be reverted.
 *
 * Usage (from packages/lambdas/exercise):
 *   node scripts/correct-logged-exercise.cjs --email you@example.com \
 *     --dates 2026-11-02,2026-11-04 --tz America/Chicago \
 *     --from quads-barbell-back-squat --to quads-hack-squat \
 *     [--subtract-weight 125] [--sets 3] [--reps 8] [--apply]
 *
 * Omit --from to list the exercises found on those dates (discovery mode).
 */
const { mkdirSync, writeFileSync } = require('fs');
const { join } = require('path');
const { tmpdir } = require('os');
const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const {
  DynamoDBDocumentClient, GetCommand, PutCommand, DeleteCommand, QueryCommand, ScanCommand,
} = require('@aws-sdk/lib-dynamodb');

const REGION = process.env.AWS_REGION || 'us-east-1';
const USERS_TABLE = process.env.USERS_TABLE || 'repwise-users';
const WORKOUTS_TABLE = process.env.WORKOUTS_TABLE || 'repwise-workouts';
const METRICS_TABLE = process.env.METRICS_TABLE || 'repwise-metrics';

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({ region: REGION }), {
  marshallOptions: { removeUndefinedValues: true },
});

// ---------- args ----------
function parseArgs(argv) {
  const out = { apply: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--apply') out.apply = true;
    else if (a.startsWith('--')) out[a.slice(2)] = argv[++i];
  }
  return out;
}
const args = parseArgs(process.argv.slice(2));
const fail = (msg) => { console.error(`\nerror: ${msg}`); process.exit(1); };
if (!args.email) fail('--email is required');
if (!args.dates) fail('--dates is required (comma-separated YYYY-MM-DD, local dates)');
const dates = new Set(args.dates.split(',').map((d) => d.trim()));
const tz = args.tz || 'America/Chicago';
const subtract = args['subtract-weight'] != null ? Number(args['subtract-weight']) : 0;
const forceSets = args.sets != null ? Number(args.sets) : undefined;
const forceReps = args.reps != null ? Number(args.reps) : undefined;

const localDate = (iso) =>
  new Intl.DateTimeFormat('en-CA', { timeZone: tz, year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date(iso));
const utcDay = (iso) => new Date(iso).toISOString().split('T')[0];

// ---------- server rules (mirrors lambdas/workout and lambdas/metrics-processor) ----------
function workoutVolume(exercises) {
  let total = 0;
  for (const ex of exercises) {
    if (ex.skipped) continue;
    if (ex.modality === 'sets_reps' && ex.weight != null && ex.sets != null && ex.reps != null) {
      total += ex.weight * ex.sets * ex.reps;
    }
  }
  return total;
}

function avgWeightInWindow(trendData, days) {
  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - days);
  const cutoffStr = cutoff.toISOString().split('T')[0];
  const inWindow = trendData.filter((p) => p.date >= cutoffStr);
  if (inWindow.length === 0) return undefined;
  const sum = inWindow.reduce((a, p) => a + p.avgWeight, 0);
  return Math.round((sum / inWindow.length) * 100) / 100;
}

/** Rebuilds one exercise's metrics item by replaying completed workouts in order. Null if never done. */
function rebuildExerciseMetrics(userId, exerciseId, completedWorkouts) {
  let em = null;
  for (const w of completedWorkouts) {
    for (const ex of w.exercises || []) {
      if (ex.skipped || ex.exerciseId !== exerciseId) continue;
      const day = utcDay(w.completedAt);
      const weight = ex.weight ?? 0;
      const weightUnit = ex.weightUnit ?? 'LBS';
      const prev = em;
      let maxWeight = prev?.maxWeight ?? 0;
      let maxWeightDate = prev?.maxWeightDate ?? day;
      let personalRecordHistory = prev?.personalRecordHistory ?? [];
      if (weight > maxWeight) {
        maxWeight = weight;
        maxWeightDate = day;
        personalRecordHistory = [...personalRecordHistory, { weight, weightUnit, achievedAt: w.completedAt, workoutInstanceId: w.workoutInstanceId }];
      }
      const trendData = [...(prev?.trendData ?? []), { date: day, avgWeight: weight, weightUnit, totalVolume: (ex.sets ?? 0) * (ex.reps ?? 0) * weight }];
      em = {
        PK: `USER#${userId}`, SK: `METRIC#EXERCISE#${exerciseId}`, userId, exerciseId,
        exerciseName: ex.exerciseName ?? exerciseId,
        totalSessions: (prev?.totalSessions ?? 0) + 1,
        maxWeight, maxWeightUnit: weightUnit, maxWeightDate,
        lastPerformedDate: day, lastUsedWeight: weight, lastUsedWeightUnit: weightUnit,
        personalRecordHistory, trendData,
      };
    }
  }
  if (!em) return null;
  em.avgWeightLast30 = avgWeightInWindow(em.trendData, 30);
  em.avgWeightLast90 = avgWeightInWindow(em.trendData, 90);
  em.avgWeightLast180 = avgWeightInWindow(em.trendData, 180);
  em.updatedAt = new Date().toISOString();
  return em;
}

// ---------- data access ----------
async function findUserId(email) {
  let lastKey;
  const matches = [];
  do {
    const out = await ddb.send(new ScanCommand({
      TableName: USERS_TABLE, ExclusiveStartKey: lastKey,
      FilterExpression: 'SK = :sk AND email = :e',
      ExpressionAttributeValues: { ':sk': 'PROFILE', ':e': email },
      ProjectionExpression: 'userId, username',
    }));
    matches.push(...(out.Items || []));
    lastKey = out.LastEvaluatedKey;
  } while (lastKey);
  if (matches.length !== 1) fail(`expected exactly one profile for ${email}, found ${matches.length}`);
  return matches[0];
}

async function allWorkouts(userId) {
  const items = [];
  let lastKey;
  do {
    const out = await ddb.send(new QueryCommand({
      TableName: WORKOUTS_TABLE, ExclusiveStartKey: lastKey,
      KeyConditionExpression: 'PK = :pk AND begins_with(SK, :sk)',
      ExpressionAttributeValues: { ':pk': `USER#${userId}`, ':sk': 'WORKOUT#' },
    }));
    items.push(...(out.Items || []));
    lastKey = out.LastEvaluatedKey;
  } while (lastKey);
  return items;
}

async function getCatalogItem(exerciseId) {
  const out = await ddb.send(new GetCommand({ TableName: WORKOUTS_TABLE, Key: { PK: `EXERCISE#${exerciseId}`, SK: 'METADATA' } }));
  return out.Item;
}

const describe = (ex) =>
  `${ex.exerciseName} [${ex.exerciseId}] ${ex.sets ?? '?'}x${ex.reps ?? '?'} @ ${ex.weight ?? '-'} ${ex.weightUnit ?? ''}${ex.skipped ? ' (skipped)' : ''}`;

// ---------- main ----------
async function main() {
  const user = await findUserId(args.email);
  const userId = user.userId;
  console.log(`User: ${user.username} (${args.email})`);
  console.log(`Dates (${tz}): ${[...dates].sort().join(', ')}`);

  const workouts = await allWorkouts(userId);
  const completed = workouts
    .filter((w) => w.status === 'completed' && w.completedAt)
    .sort((a, b) => a.completedAt.localeCompare(b.completedAt));
  const onDates = completed.filter((w) => dates.has(localDate(w.completedAt)));
  const missingDates = [...dates].filter((d) => !onDates.some((w) => localDate(w.completedAt) === d));

  console.log(`\nCompleted workouts on those dates: ${onDates.length}`);
  for (const w of onDates) {
    console.log(`\n  ${localDate(w.completedAt)}  ${w.workoutInstanceId}`);
    for (const ex of w.exercises || []) console.log(`    - ${describe(ex)}`);
  }
  if (missingDates.length) console.log(`\nWARNING: no completed workout found on: ${missingDates.join(', ')}`);

  if (!args.from || !args.to) {
    console.log('\nDiscovery mode: pass --from <exerciseId> --to <exerciseId> to plan the correction.');
    return;
  }

  const target = await getCatalogItem(args.to);
  if (!target || target.isActive === false) fail(`--to ${args.to} is not an active catalog exercise`);
  const fromName = (onDates.flatMap((w) => w.exercises || []).find((e) => e.exerciseId === args.from) || {}).exerciseName;

  // ---- plan workout changes ----
  const changes = [];
  for (const w of onDates) {
    const idx = (w.exercises || []).findIndex((e) => e.exerciseId === args.from);
    if (idx === -1) { console.log(`\n  skip ${localDate(w.completedAt)}: no ${args.from}`); continue; }
    if ((w.exercises || []).filter((e) => e.exerciseId === args.from).length > 1) fail(`${w.workoutInstanceId} contains ${args.from} more than once`);
    if ((w.exercises || []).some((e) => e.exerciseId === args.to)) fail(`${w.workoutInstanceId} already contains ${args.to}`);
    const before = w.exercises[idx];
    if (subtract && (before.weightUnit ?? 'LBS') !== 'LBS') fail(`${w.workoutInstanceId}: weight is in ${before.weightUnit}, expected LBS for --subtract-weight`);
    let newWeight = before.weight;
    if (subtract) {
      if (before.weight == null) fail(`${w.workoutInstanceId}: no weight logged to subtract from`);
      newWeight = before.weight - subtract;
      if (newWeight < 0) fail(`${w.workoutInstanceId}: ${before.weight} - ${subtract} would be negative`);
    }
    const after = {
      ...before,
      exerciseId: target.exerciseId,
      exerciseName: target.name,
      modality: target.modality,
      weight: newWeight,
      sets: forceSets ?? before.sets,
      reps: forceReps ?? before.reps,
    };
    // These were snapshots of the old exercise's history at creation time; they no longer apply.
    delete after.lastUsedWeight;
    delete after.lastUsedWeightUnit;
    delete after.lastPerformedDate;
    const exercises = w.exercises.map((e, i) => (i === idx ? after : e));
    const updated = { ...w, exercises, totalVolume: workoutVolume(exercises) };
    changes.push({ original: w, updated, before, after });
  }
  if (!changes.length) fail('nothing to change');

  console.log(`\n================ PLAN: ${fromName || args.from} -> ${target.name} ================`);
  for (const c of changes) {
    console.log(`\n  ${localDate(c.original.completedAt)}  ${c.original.workoutInstanceId}`);
    console.log(`    before: ${describe(c.before)}`);
    console.log(`    after:  ${describe(c.after)}`);
    console.log(`    workout totalVolume: ${c.original.totalVolume ?? 0} -> ${c.updated.totalVolume}`);
  }

  // ---- rebuild metrics from the corrected history ----
  const changedById = new Map(changes.map((c) => [c.original.workoutInstanceId, c.updated]));
  const correctedHistory = completed.map((w) => changedById.get(w.workoutInstanceId) || w);
  const metricsPlan = [];
  for (const exerciseId of [args.from, args.to]) {
    const key = { PK: `USER#${userId}`, SK: `METRIC#EXERCISE#${exerciseId}` };
    const current = (await ddb.send(new GetCommand({ TableName: METRICS_TABLE, Key: key }))).Item;
    const rebuilt = rebuildExerciseMetrics(userId, exerciseId, correctedHistory);
    metricsPlan.push({ exerciseId, key, current, rebuilt });
    const fmt = (m) => (m ? `${m.totalSessions} sessions, max ${m.maxWeight} ${m.maxWeightUnit}, last ${m.lastUsedWeight} on ${m.lastPerformedDate}` : '(none)');
    console.log(`\n  metrics ${exerciseId}:`);
    console.log(`    before: ${fmt(current)}`);
    console.log(`    after:  ${rebuilt ? fmt(rebuilt) : '(deleted: no remaining sessions)'}`);
  }

  const globalKey = { PK: `USER#${userId}`, SK: 'METRIC#GLOBAL' };
  const global = (await ddb.send(new GetCommand({ TableName: METRICS_TABLE, Key: globalKey }))).Item;
  const volumeDelta = changes.reduce((a, c) => a + (c.updated.totalVolume - (c.original.totalVolume ?? 0)), 0);
  if (global) {
    console.log(`\n  global totalVolumeAllTime: ${global.totalVolumeAllTime} -> ${global.totalVolumeAllTime + volumeDelta}`);
  }

  if (!args.apply) {
    console.log('\nDRY RUN: nothing was written. Re-run with --apply to make these changes.');
    return;
  }

  // ---- backup, then write ----
  const backupDir = join(tmpdir(), 'rook-corrections', new Date().toISOString().replace(/[:.]/g, '-'));
  mkdirSync(backupDir, { recursive: true });
  writeFileSync(join(backupDir, 'backup.json'), JSON.stringify({
    workouts: changes.map((c) => c.original),
    metrics: metricsPlan.map((m) => ({ key: m.key, item: m.current ?? null })),
    global: global ?? null,
  }, null, 2));
  console.log(`\nBackup of original items: ${join(backupDir, 'backup.json')}`);

  for (const c of changes) {
    await ddb.send(new PutCommand({
      TableName: WORKOUTS_TABLE, Item: c.updated,
      // Only overwrite the exact completed item we read.
      ConditionExpression: 'attribute_exists(PK) AND #s = :completed',
      ExpressionAttributeNames: { '#s': 'status' },
      ExpressionAttributeValues: { ':completed': 'completed' },
    }));
    console.log(`  wrote workout ${c.original.workoutInstanceId}`);
  }
  for (const m of metricsPlan) {
    if (m.rebuilt) {
      await ddb.send(new PutCommand({ TableName: METRICS_TABLE, Item: m.rebuilt }));
      console.log(`  wrote metrics ${m.exerciseId}`);
    } else if (m.current) {
      await ddb.send(new DeleteCommand({ TableName: METRICS_TABLE, Key: m.key }));
      console.log(`  deleted metrics ${m.exerciseId}`);
    }
  }
  if (global && volumeDelta !== 0) {
    await ddb.send(new PutCommand({
      TableName: METRICS_TABLE,
      Item: { ...global, totalVolumeAllTime: global.totalVolumeAllTime + volumeDelta, updatedAt: new Date().toISOString() },
    }));
    console.log('  wrote global metrics');
  }
  console.log('\nDone.');
}

main().catch((e) => { console.error(e); process.exit(1); });
