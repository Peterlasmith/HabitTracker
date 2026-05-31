create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_user_id uuid := auth.uid();
begin
    if v_user_id is null then
        raise exception 'A signed-in session is required.';
    end if;

    delete from auth.users
    where id = v_user_id;

    if not found then
        raise exception 'Account not found or already deleted.';
    end if;
end;
$$;

revoke all on function public.delete_my_account() from public;
grant execute on function public.delete_my_account() to authenticated;
