create table if not exists public.bucket_items (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users (id) on delete cascade,
    title text not null check (char_length(trim(title)) > 0),
    category text not null check (category in ('travel', 'adventure', 'skills', 'experiences', 'milestones', 'giving', 'other')),
    completed_at timestamptz,
    created_at timestamptz not null default timezone('utc', now()),
    updated_at timestamptz not null default timezone('utc', now())
);

create index if not exists bucket_items_user_category_created_at_idx
    on public.bucket_items (user_id, category, created_at);

create index if not exists bucket_items_user_completed_at_idx
    on public.bucket_items (user_id, completed_at);

alter table public.bucket_items enable row level security;

drop policy if exists "Users can view own bucket items" on public.bucket_items;
create policy "Users can view own bucket items"
    on public.bucket_items
    for select
    to authenticated
    using (auth.uid() = user_id);

drop policy if exists "Users can insert own bucket items" on public.bucket_items;
create policy "Users can insert own bucket items"
    on public.bucket_items
    for insert
    to authenticated
    with check (auth.uid() = user_id);

drop policy if exists "Users can update own bucket items" on public.bucket_items;
create policy "Users can update own bucket items"
    on public.bucket_items
    for update
    to authenticated
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

drop policy if exists "Users can delete own bucket items" on public.bucket_items;
create policy "Users can delete own bucket items"
    on public.bucket_items
    for delete
    to authenticated
    using (auth.uid() = user_id);

create or replace function public.set_bucket_items_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at = timezone('utc', now());
    return new;
end;
$$;

drop trigger if exists set_bucket_items_updated_at on public.bucket_items;
create trigger set_bucket_items_updated_at
    before update on public.bucket_items
    for each row
    execute function public.set_bucket_items_updated_at();
