delete from public.habits
where archived_at is not null;

alter table public.habits
drop column if exists archived_at;

drop policy if exists "Users can delete own habits" on public.habits;
create policy "Users can delete own habits"
    on public.habits
    for delete
    to authenticated
    using (auth.uid() = user_id);
