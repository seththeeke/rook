import type { ExerciseModality, WeightUnit } from './enums';
import type { WorkoutExercise, WorkoutInstance } from './models';

/**
 * Per-session exercise history (specs/exercise-trends.md §2.1).
 *
 * One item per exercise per completed workout in `repwise-metrics`:
 * `PK = USER#<userId>`, `SK = SESSION#<exerciseId>#<completedAt>`. A single key-range Query returns one
 * exercise's history in time order without an index.
 */
export const SESSION_PREFIX = 'SESSION#';
/** How many recent sessions the `METRIC#EXERCISE#` summary row keeps for sparklines. */
export const RECENT_SESSIONS_LIMIT = 10;
/** `trendData` on the summary row is trimmed to this window (longest avg window it serves). */
export const TREND_DATA_RETENTION_DAYS = 180;

export interface ExerciseSessionItem {
  PK: string;
  SK: string;
  userId: string;
  exerciseId: string;
  workoutInstanceId: string;
  completedAt: string;
  modality: ExerciseModality;
  weight: number;
  weightUnit: WeightUnit;
  sets?: number;
  reps?: number;
  durationSeconds?: number;
}

/** Compact session kept on the summary row (`recentSessions`). */
export interface RecentSession {
  completedAt: string;
  weight: number;
  weightUnit: WeightUnit;
  reps?: number;
  durationSeconds?: number;
}

/** `SESSION#<exerciseId>#` — the trailing `#` stops `bench-press` matching `bench-press-incline`. */
export function sessionSkPrefix(exerciseId: string): string {
  return `${SESSION_PREFIX}${exerciseId}#`;
}

export function sessionSk(exerciseId: string, completedAt: string): string {
  return `${sessionSkPrefix(exerciseId)}${completedAt}`;
}

/**
 * The logged (non-skipped) exercises of a completed workout, one per exerciseId. When an exercise
 * appears more than once, the entry with the heavier weight wins.
 */
export function loggedExercisesById(workout: WorkoutInstance): WorkoutExercise[] {
  const byId = new Map<string, WorkoutExercise>();
  for (const ex of workout.exercises ?? []) {
    if (ex.skipped || !ex.exerciseId) continue;
    const existing = byId.get(ex.exerciseId);
    if (!existing || (ex.weight ?? 0) > (existing.weight ?? 0)) byId.set(ex.exerciseId, ex);
  }
  return [...byId.values()];
}

export function toSessionItem(
  workout: WorkoutInstance,
  ex: WorkoutExercise,
  defaultUnit: WeightUnit
): ExerciseSessionItem {
  const completedAt = workout.completedAt ?? new Date().toISOString();
  const item: ExerciseSessionItem = {
    PK: `USER#${workout.userId}`,
    SK: sessionSk(ex.exerciseId, completedAt),
    userId: workout.userId,
    exerciseId: ex.exerciseId,
    workoutInstanceId: workout.workoutInstanceId,
    completedAt,
    modality: ex.modality,
    weight: ex.weight ?? 0,
    weightUnit: ex.weightUnit ?? defaultUnit,
  };
  if (ex.sets != null) item.sets = ex.sets;
  if (ex.reps != null) item.reps = ex.reps;
  if (ex.durationSeconds != null) item.durationSeconds = ex.durationSeconds;
  return item;
}

export function toRecentSession(item: ExerciseSessionItem): RecentSession {
  const s: RecentSession = {
    completedAt: item.completedAt,
    weight: item.weight,
    weightUnit: item.weightUnit,
  };
  if (item.reps != null) s.reps = item.reps;
  if (item.durationSeconds != null) s.durationSeconds = item.durationSeconds;
  return s;
}

/** Adds `session` to `existing`, de-duplicated by `completedAt`, sorted oldest first, capped. */
export function mergeRecentSessions(
  existing: RecentSession[] | undefined,
  session: RecentSession
): RecentSession[] {
  const merged = (existing ?? []).filter((s) => s.completedAt !== session.completedAt);
  merged.push(session);
  merged.sort((a, b) => a.completedAt.localeCompare(b.completedAt));
  return merged.slice(-RECENT_SESSIONS_LIMIT);
}
