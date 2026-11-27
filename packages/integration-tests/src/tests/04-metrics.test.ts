import { describe, it, expect, beforeAll } from 'vitest';
import { getTestToken } from '../helpers/auth';
import { makeClient } from '../helpers/client';

describe.skipIf(!process.env.API_BASE_URL)('Metrics', () => {
  let client: ReturnType<typeof makeClient>;

  beforeAll(async () => {
    client = makeClient(await getTestToken());
    const exercises = await client.get('/exercises');
    const exerciseId = exercises.data[0].exerciseId;
    const post = await client.post('/workout-instances', {
      source: 'manual',
      permissionType: 'PRIVATE',
      exercises: [
        {
          exerciseId,
          exerciseName: 'Metrics Test Exercise',
          modality: 'sets_reps',
          sets: 3,
          reps: 10,
          skipped: false,
          orderIndex: 0,
        },
      ],
    });
    const workoutId = post.data.workoutInstanceId;
    await client.patch(`/workout-instances/${workoutId}`, {
      exercises: [{ exerciseId, weight: 95, weightUnit: 'LBS' }],
    });
    await client.patch(`/workout-instances/${workoutId}`, { status: 'completed' });
    for (let i = 0; i < 15; i++) {
      await new Promise((r) => setTimeout(r, 1000));
      const g = await client.get('/metrics/me/global');
      if (g.status === 200 && g.data.totalWorkouts >= 1) break;
    }
  });

  it('GET /metrics/me/global returns valid global metrics', async () => {
    const res = await client.get('/metrics/me/global');
    expect(res.status).toBe(200);
    expect(res.data.totalWorkouts).toBeGreaterThanOrEqual(1);
    expect(typeof res.data.currentStreak).toBe('number');
    expect(Array.isArray(res.data.completedDates)).toBe(true);
  });

  it('GET /metrics/me/exercises returns a list after completed workout', async () => {
    const res = await client.get('/metrics/me/exercises');
    expect(res.status).toBe(200);
    expect(res.data.length).toBeGreaterThanOrEqual(1);
  });

  it('GET /metrics/me/exercises/:id returns exercise trend data', async () => {
    const list = await client.get('/metrics/me/exercises');
    expect(list.status).toBe(200);
    expect(Array.isArray(list.data)).toBe(true);
    expect(list.data.length).toBeGreaterThanOrEqual(1);
    const exerciseId = list.data[0].exerciseId;
    const res = await client.get(`/metrics/me/exercises/${exerciseId}`);
    expect(res.status).toBe(200);
    expect(Array.isArray(res.data.trendData)).toBe(true);
    expect(Array.isArray(res.data.personalRecordHistory)).toBe(true);
  });
  it('GET /metrics/me/exercises items carry recentSessions and lastPerformedAt', async () => {
    const res = await client.get('/metrics/me/exercises');
    expect(res.status).toBe(200);
    const item = res.data.find((e: { recentSessions?: unknown[] }) => (e.recentSessions ?? []).length > 0);
    expect(item).toBeDefined();
    expect(item.recentSessions.length).toBeLessThanOrEqual(10);
    expect(typeof item.lastPerformedAt).toBe('string');
    expect(item.trendData).toBeUndefined();
  });

  it('GET /metrics/me/exercises/:id/sessions returns time-ordered sessions', async () => {
    const list = await client.get('/metrics/me/exercises');
    const exerciseId = list.data[0].exerciseId;
    const res = await client.get(`/metrics/me/exercises/${exerciseId}/sessions`);
    expect(res.status).toBe(200);
    expect(res.data.exerciseId).toBe(exerciseId);
    expect(res.data.sessions.length).toBeGreaterThanOrEqual(1);
    const times = res.data.sessions.map((s: { completedAt: string }) => s.completedAt);
    expect([...times].sort()).toEqual(times);

    const future = await client.get(`/metrics/me/exercises/${exerciseId}/sessions?from=2999-01-01`);
    expect(future.status).toBe(200);
    expect(future.data.sessions).toEqual([]);

    const bad = await client.get(`/metrics/me/exercises/${exerciseId}/sessions?from=yesterday`);
    expect(bad.status).toBe(400);
  });
});
