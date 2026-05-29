const WEEKDAY_NAMES = {
  1: "sunday",
  2: "monday",
  3: "tuesday",
  4: "wednesday",
  5: "thursday",
  6: "friday",
  7: "saturday",
};

const WEEKDAY_VALUES = Object.entries(WEEKDAY_NAMES).reduce((result, [value, name]) => {
  result[name] = Number(value);
  return result;
}, {});

export function buildProfileResponse(user, habits, completions) {
  const activeHabits = habits.filter((habit) => !habit.archived_at);
  return {
    id: user.id,
    email: user.email ?? null,
    active_habit_count: activeHabits.length,
    archived_habit_count: habits.length - activeHabits.length,
    completion_count: completions.length,
  };
}

export function buildHabitResponse(habit, completions, options = {}) {
  const timeZone = options.timeZone ?? "UTC";
  const referenceDate = options.referenceDate ?? new Date();
  const normalizedCompletions = [...completions].sort((lhs, rhs) =>
    rhs.date.localeCompare(lhs.date) || rhs.created_at.localeCompare(lhs.created_at)
  );
  const recentWindowDays = options.recentWindowDays ?? 14;
  const recentCutoff = Date.now() - recentWindowDays * 24 * 60 * 60 * 1000;
  const reminderEnabled = habit.reminder_hour !== null && habit.reminder_hour !== undefined;

  return {
    id: habit.id,
    name: habit.name,
    emoji: habit.emoji_or_icon,
    color: habit.color,
    status: habit.archived_at ? "archived" : "active",
    created_at: habit.created_at,
    archived_at: habit.archived_at,
    schedule: {
      type: habit.schedule_type,
      weekdays: normalizeWeekdayNames(habit.schedule_weekdays),
    },
    target: {
      type: habit.target_type,
      count: habit.target_count,
      period: habit.target_period ?? (habit.target_type === "count" ? "week" : "day"),
    },
    reminder: {
      enabled: reminderEnabled,
      hour: reminderEnabled ? habit.reminder_hour : null,
      minute: reminderEnabled ? habit.reminder_minute ?? 0 : null,
    },
    derived: {
      due_today: isHabitDueOnDate(habit, referenceDate, timeZone),
      due_this_week: countDueDays(habit, referenceDate, 7, timeZone),
      current_streak: currentStreak(habit, normalizedCompletions, referenceDate, timeZone),
      adherence_last_7_days: adherence(habit, normalizedCompletions, referenceDate, 7, timeZone),
      last_completed_at: lastCompletedAt(habit, normalizedCompletions),
    },
    recent_completions: normalizedCompletions
      .filter((completion) => new Date(completion.date).getTime() >= recentCutoff)
      .map((completion) =>
        buildCompletionResponse(completion, habit, normalizedCompletions, { timeZone, referenceDate })
      ),
  };
}

export function buildCompletionResponse(completion, habit = null, completions = [], options = {}) {
  return {
    id: completion.id,
    habit_id: completion.habit_id,
    date: completion.date,
    count: completion.count,
    note: completion.note,
    created_at: completion.created_at,
    is_complete: habit
      ? isCompletionComplete(completion, habit, completions, options.referenceDate ?? new Date(completion.date), options.timeZone ?? "UTC")
      : completion.count > 0,
  };
}

export function isHabitDueOnDate(habit, date, timeZone = "UTC") {
  if (habit.archived_at) {
    return false;
  }

  if (habit.schedule_type === "daily") {
    return true;
  }

  const weekday = weekdayNumber(date, timeZone);
  return (habit.schedule_weekdays ?? []).includes(weekday);
}

export function currentStreak(habit, completions, referenceDate = new Date(), timeZone = "UTC") {
  if ((habit.target_period ?? (habit.target_type === "count" ? "week" : "day")) === "week") {
    let streak = 0;
    let cursor = startOfWeek(referenceDate, timeZone);

    for (let offset = 0; offset < 104; offset += 1) {
      const weekStart = addDays(cursor, -offset * 7);
      if (!hasScheduledDayInWeek(habit, weekStart, timeZone)) {
        continue;
      }

      if (!isPeriodComplete(habit, completions, weekStart, timeZone)) {
        break;
      }

      streak += 1;
    }

    return streak;
  }

  const completionMap = completionLookup(completions);
  let streak = 0;

  for (let offset = 0; offset < 365; offset += 1) {
    const currentDate = addDays(referenceDate, -offset);
    if (!isHabitDueOnDate(habit, currentDate, timeZone)) {
      continue;
    }

    const completion = completionMap.get(dateKey(currentDate, timeZone));
    if (!completion || !isCompletionComplete(completion, habit)) {
      break;
    }

    streak += 1;
  }

  return streak;
}

export function adherence(habit, completions, referenceDate = new Date(), days = 7, timeZone = "UTC") {
  if ((habit.target_period ?? (habit.target_type === "count" ? "week" : "day")) === "week") {
    const weekStart = startOfWeek(referenceDate, timeZone);
    const progress = periodProgress(habit, completions, weekStart, timeZone);
    return {
      completed_days: progress.completed,
      due_days: habit.target_count,
      ratio: Number(progress.ratio.toFixed(4)),
    };
  }

  const completionMap = completionLookup(completions);
  let dueDays = 0;
  let completedDays = 0;

  for (let offset = 0; offset < days; offset += 1) {
    const currentDate = addDays(referenceDate, -offset);
    if (!isHabitDueOnDate(habit, currentDate, timeZone)) {
      continue;
    }

    dueDays += 1;
    const completion = completionMap.get(dateKey(currentDate, timeZone));
    if (completion && isCompletionComplete(completion, habit)) {
      completedDays += 1;
    }
  }

  return {
    completed_days: completedDays,
    due_days: dueDays,
    ratio: dueDays === 0 ? 0 : Number((completedDays / dueDays).toFixed(4)),
  };
}

function countDueDays(habit, referenceDate, days, timeZone) {
  let dueDays = 0;

  for (let offset = 0; offset < days; offset += 1) {
    if (isHabitDueOnDate(habit, addDays(referenceDate, offset), timeZone)) {
      dueDays += 1;
    }
  }

  return dueDays;
}

function completionLookup(completions) {
  return completions.reduce((map, completion) => {
    map.set(dateKey(new Date(completion.date)), completion);
    return map;
  }, new Map());
}

function lastCompletedAt(habit, completions) {
  const found = completions.find((completion) =>
    isCompletionComplete(completion, habit, completions, new Date(completion.date))
  );
  return found?.date ?? null;
}

function isCompletionComplete(completion, habit, completions, referenceDate, timeZone = "UTC") {
  if ((habit.target_period ?? (habit.target_type === "count" ? "week" : "day")) === "week") {
    return isPeriodComplete(habit, completions, referenceDate, timeZone);
  }

  if (habit.target_type === "count") {
    return completion.count > 0;
  }

  return completion.count > 0;
}

function isPeriodComplete(habit, completions, referenceDate, timeZone) {
  return periodProgress(habit, completions, referenceDate, timeZone).completed >= habit.target_count;
}

function periodProgress(habit, completions, referenceDate, timeZone) {
  const weekStart = startOfWeek(referenceDate, timeZone);
  const weekEnd = addDays(weekStart, 6);
  const completed = completions.reduce((sum, completion) => {
    const completionDate = new Date(completion.date);
    if (completionDate < weekStart || completionDate > weekEnd) {
      return sum;
    }
    if (!isHabitDueOnDate(habit, completionDate, timeZone)) {
      return sum;
    }
    return sum + Math.max(completion.count, 0);
  }, 0);

  return {
    completed,
    ratio: habit.target_count === 0 ? 0 : Math.min(completed / habit.target_count, 1),
  };
}

function hasScheduledDayInWeek(habit, weekStart, timeZone) {
  for (let offset = 0; offset < 7; offset += 1) {
    if (isHabitDueOnDate(habit, addDays(weekStart, offset), timeZone)) {
      return true;
    }
  }

  return false;
}

function normalizeWeekdayNames(values = []) {
  return values
    .map((value) => WEEKDAY_NAMES[value])
    .filter(Boolean);
}

function weekdayNumber(date, timeZone = "UTC") {
  const label = new Intl.DateTimeFormat("en-US", {
    weekday: "long",
    timeZone,
  })
    .format(date)
    .toLowerCase();

  return WEEKDAY_VALUES[label];
}

function dateKey(date, timeZone = "UTC") {
  const formatter = new Intl.DateTimeFormat("en-CA", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    timeZone,
  });

  return formatter.format(date);
}

function addDays(date, days) {
  return new Date(date.getTime() + days * 24 * 60 * 60 * 1000);
}

function startOfWeek(date, timeZone = "UTC") {
  const weekday = weekdayNumber(date, timeZone);
  const offset = (weekday + 5) % 7;
  return addDays(new Date(dateKey(date, timeZone)), -offset);
}
