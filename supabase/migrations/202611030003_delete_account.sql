begin;
-- App Store guideline 5.1.1(v). The cascading foreign keys remove the synced words and settings.
create or replace function public.flype_delete_account() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare deleted_count integer;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  delete from auth.users where id = auth.uid();
  get diagnostics deleted_count = row_count;
  return jsonb_build_object('deleted', deleted_count = 1);
end $$;
revoke all on function public.flype_delete_account() from public, anon;
grant execute on function public.flype_delete_account() to authenticated;
notify pgrst, 'reload schema';
commit;
