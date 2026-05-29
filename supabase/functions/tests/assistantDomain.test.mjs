import test from "node:test";
import assert from "node:assert/strict";

import {
  adherence,
  buildCompletionResponse,
  buildHabitResponse,
  currentStreak,
  isHabitDueOnDate,
} from "../_shared/assistantDomain.js";

const readingHabit = {
  id: "habit-1",
  name: "Read",
  emoji_or_icon: "📚",
  color: "teal",
  archived_at: null,
  created_at: "2026-05-01T00:00:00.000Z",
  schedule_type: "weekdays",
  schedule_weekdays: [2, 4, 6],
  target_type: "count",
  target_count: 2,
  target_period: "week",
  reminder_hour: 8,
  reminder_minute: 30,
};

const completions = [
  {
    id: "completion-1",
    habit_id: "habit-1",
    date: "2026-05-27T00:00:00.000Z",
    count: 1,
    note: "Morning session",
    created_at: "2026-05-27T01:00:00.000Z",
  },
  {
    id: "completion-2",
    habit_id: "habit-1",
    date: "2026-05-25T00:00:00.000Z",
    count: 1,
    note: "",
    created_at: "2026-05-25T01:00:00.000Z",
  },
  {
    id: "completion-3",
    habit_id: "habit-1",
    date: "2026-05-22T00:00:00.000Z",
    count: 1,
    note: "",
    created_at: "2026-05-22T01:00:00.000Z",
  },
];

test("isHabitDueOnDate respects custom weekday schedules", () => {
  assert.equal(isHabitDueOnDate(readingHabit, new Date("2026-05-27T12:00:00.000Z")), true);
  assert.equal(isHabitDueOnDate(readingHabit, new Date("2026-05-28T12:00:00.000Z")), false);
});

test("currentStreak stops when a due day is incomplete", () => {
  const streak = currentStreak(
    readingHabit,
    completions,
    new Date("2026-05-27T12:00:00.000Z")
  );

  assert.equal(streak, 1);
});

test("adherence counts only due days for the rolling window", () => {
  const summary = adherence(
    readingHabit,
    completions,
    new Date("2026-05-27T12:00:00.000Z"),
    7
  );

  assert.deepEqual(summary, {
    completed_days: 2,
    due_days: 2,
    ratio: 1,
  });
});

test("buildHabitResponse returns planning-friendly derived fields", () => {
  const response = buildHabitResponse(readingHabit, completions, {
    referenceDate: new Date("2026-05-27T12:00:00.000Z"),
    timeZone: "UTC",
  });

  assert.equal(response.schedule.type, "weekdays");
  assert.deepEqual(response.schedule.weekdays, ["monday", "wednesday", "friday"]);
  assert.equal(response.target.period, "week");
  assert.equal(response.reminder.enabled, true);
  assert.equal(response.derived.due_today, true);
  assert.equal(response.derived.current_streak, 1);
  assert.equal(response.recent_completions.length, 3);
});

test("buildCompletionResponse derives completion status from habit targets", () => {
  const complete = buildCompletionResponse(completions[0], readingHabit, completions, {
    referenceDate: new Date("2026-05-27T12:00:00.000Z"),
    timeZone: "UTC",
  });
  const incomplete = buildCompletionResponse(completions[2], readingHabit, completions, {
    referenceDate: new Date("2026-05-22T12:00:00.000Z"),
    timeZone: "UTC",
  });

  assert.equal(complete.is_complete, true);
  assert.equal(incomplete.is_complete, false);
});
