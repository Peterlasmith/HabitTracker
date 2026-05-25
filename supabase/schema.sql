create extension if not exists pgcrypto;

create table if not exists public.habits (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users (id) on delete cascade,
    name text not null check (char_length(trim(name)) > 0),
    emoji_or_icon text not null,
    color text not null,
    schedule_type text not null check (schedule_type in ('daily', 'weekdays')),
    schedule_weekdays integer[] not null default '{}',
    target_type text not null check (target_type in ('binary', 'count')),
    target_count integer not null check (target_count >= 1),
    reminder_hour integer check (reminder_hour between 0 and 23),
    reminder_minute integer check (reminder_minute between 0 and 59),
    created_at timestamptz not null default timezone('utc', now()),
    archived_at timestamptz,
    constraint habits_id_user_id_unique unique (id, user_id)
);

create table if not exists public.habit_completions (
    id uuid primary key default gen_random_uuid(),
    habit_id uuid not null references public.habits (id) on delete cascade,
    user_id uuid not null references auth.users (id) on delete cascade,
    date timestamptz not null,
    count integer not null check (count >= 0),
    note text not null default '',
    created_at timestamptz not null default timezone('utc', now()),
    constraint habit_completions_habit_user_match
        foreign key (habit_id, user_id)
        references public.habits (id, user_id)
        on delete cascade
);

create unique index if not exists habits_user_created_at_idx
    on public.habits (user_id, created_at);

create unique index if not exists habit_completions_habit_date_idx
    on public.habit_completions (habit_id, date);

create unique index if not exists habit_completions_user_habit_date_idx
    on public.habit_completions (user_id, habit_id, date);

alter table public.habits enable row level security;
alter table public.habit_completions enable row level security;

drop policy if exists "Users can view own habits" on public.habits;
create policy "Users can view own habits"
    on public.habits
    for select
    to authenticated
    using (auth.uid() = user_id);

drop policy if exists "Users can insert own habits" on public.habits;
create policy "Users can insert own habits"
    on public.habits
    for insert
    to authenticated
    with check (auth.uid() = user_id);

drop policy if exists "Users can update own habits" on public.habits;
create policy "Users can update own habits"
    on public.habits
    for update
    to authenticated
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

drop policy if exists "Users can view own completions" on public.habit_completions;
create policy "Users can view own completions"
    on public.habit_completions
    for select
    to authenticated
    using (auth.uid() = user_id);

drop policy if exists "Users can insert own completions" on public.habit_completions;
create policy "Users can insert own completions"
    on public.habit_completions
    for insert
    to authenticated
    with check (
        auth.uid() = user_id
        and exists (
            select 1
            from public.habits
            where habits.id = habit_completions.habit_id
              and habits.user_id = auth.uid()
        )
    );

drop policy if exists "Users can update own completions" on public.habit_completions;
create policy "Users can update own completions"
    on public.habit_completions
    for update
    to authenticated
    using (auth.uid() = user_id)
    with check (
        auth.uid() = user_id
        and exists (
            select 1
            from public.habits
            where habits.id = habit_completions.habit_id
              and habits.user_id = auth.uid()
        )
    );
