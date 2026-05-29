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
    target_period text not null default 'day' check (target_period in ('day', 'week')),
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

create index if not exists habits_user_created_at_idx
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

create table if not exists public.assistant_clients (
    id uuid primary key default gen_random_uuid(),
    client_identifier text not null unique,
    client_secret_hash text not null,
    name text not null check (char_length(trim(name)) > 0),
    redirect_uris text[] not null check (coalesce(array_length(redirect_uris, 1), 0) > 0),
    allowed_scopes text[] not null default array['habits.read'],
    created_at timestamptz not null default timezone('utc', now()),
    updated_at timestamptz not null default timezone('utc', now()),
    revoked_at timestamptz
);

create table if not exists public.assistant_authorization_codes (
    id uuid primary key default gen_random_uuid(),
    code_hash text not null unique,
    client_id uuid not null references public.assistant_clients (id) on delete cascade,
    user_id uuid not null references auth.users (id) on delete cascade,
    redirect_uri text not null,
    scope text[] not null,
    code_challenge text,
    code_challenge_method text check (code_challenge_method in ('plain', 'S256')),
    created_at timestamptz not null default timezone('utc', now()),
    expires_at timestamptz not null,
    consumed_at timestamptz,
    revoked_at timestamptz
);

create table if not exists public.assistant_access_tokens (
    id uuid primary key default gen_random_uuid(),
    token_hash text not null unique,
    client_id uuid not null references public.assistant_clients (id) on delete cascade,
    user_id uuid not null references auth.users (id) on delete cascade,
    scope text[] not null,
    created_at timestamptz not null default timezone('utc', now()),
    expires_at timestamptz not null,
    last_used_at timestamptz,
    revoked_at timestamptz
);

create index if not exists assistant_clients_client_identifier_idx
    on public.assistant_clients (client_identifier)
    where revoked_at is null;

create index if not exists assistant_authorization_codes_client_user_idx
    on public.assistant_authorization_codes (client_id, user_id, expires_at);

create index if not exists assistant_access_tokens_client_user_idx
    on public.assistant_access_tokens (client_id, user_id, expires_at);

alter table public.assistant_clients enable row level security;
alter table public.assistant_authorization_codes enable row level security;
alter table public.assistant_access_tokens enable row level security;

drop policy if exists "No direct assistant client access" on public.assistant_clients;
create policy "No direct assistant client access"
    on public.assistant_clients
    for all
    to authenticated
    using (false)
    with check (false);

drop policy if exists "No direct assistant authorization code access" on public.assistant_authorization_codes;
create policy "No direct assistant authorization code access"
    on public.assistant_authorization_codes
    for all
    to authenticated
    using (false)
    with check (false);

drop policy if exists "No direct assistant token access" on public.assistant_access_tokens;
create policy "No direct assistant token access"
    on public.assistant_access_tokens
    for all
    to authenticated
    using (false)
    with check (false);

create or replace function public.create_assistant_client(
    p_name text,
    p_redirect_uris text[],
    p_allowed_scopes text[] default array['habits.read']
)
returns table (
    client_identifier text,
    client_secret text,
    allowed_scopes text[]
)
language plpgsql
security definer
set search_path = public
as $$
declare
    v_client_identifier text := encode(gen_random_bytes(18), 'hex');
    v_client_secret text := encode(gen_random_bytes(32), 'hex');
begin
    if coalesce(array_length(p_redirect_uris, 1), 0) = 0 then
        raise exception 'At least one redirect URI is required.';
    end if;

    insert into public.assistant_clients (
        client_identifier,
        client_secret_hash,
        name,
        redirect_uris,
        allowed_scopes
    )
    values (
        v_client_identifier,
        encode(digest(v_client_secret, 'sha256'), 'hex'),
        trim(p_name),
        p_redirect_uris,
        coalesce(p_allowed_scopes, array['habits.read'])
    );

    return query
    select
        v_client_identifier,
        v_client_secret,
        coalesce(p_allowed_scopes, array['habits.read']);
end;
$$;

create or replace function public.rotate_assistant_client_secret(
    p_client_identifier text
)
returns table (
    client_identifier text,
    client_secret text
)
language plpgsql
security definer
set search_path = public
as $$
declare
    v_client_secret text := encode(gen_random_bytes(32), 'hex');
begin
    update public.assistant_clients
    set
        client_secret_hash = encode(digest(v_client_secret, 'sha256'), 'hex'),
        updated_at = timezone('utc', now())
    where assistant_clients.client_identifier = p_client_identifier
      and assistant_clients.revoked_at is null;

    if not found then
        raise exception 'Assistant client not found.';
    end if;

    return query
    select p_client_identifier, v_client_secret;
end;
$$;

revoke all on function public.create_assistant_client(text, text[], text[]) from public, anon, authenticated;
grant execute on function public.create_assistant_client(text, text[], text[]) to service_role;

revoke all on function public.rotate_assistant_client_secret(text) from public, anon, authenticated;
grant execute on function public.rotate_assistant_client_secret(text) to service_role;
