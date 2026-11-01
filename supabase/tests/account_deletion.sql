\set ON_ERROR_STOP on
begin;
-- Anonymous callers have no execute right.
set local role anon;
do $$
begin
  perform public.flype_delete_account();
  raise exception 'anon must not delete accounts';
exception when insufficient_privilege then null;
end $$;
reset role;

-- Prepare data for both users, then delete only the first.
insert into public.personal_dictionaries(user_id, entries)
  values ('00000000-0000-0000-0000-000000000001', '[]'), ('00000000-0000-0000-0000-000000000002', '[]')
  on conflict (user_id) do nothing;
insert into public.personal_settings(user_id, settings) values
  ('00000000-0000-0000-0000-000000000001',
   '{"dictationMode":"cleaned","applyDictionary":true,"dictationLanguage":"de","interfaceLanguage":"system"}'),
  ('00000000-0000-0000-0000-000000000002',
   '{"dictationMode":"cleaned","applyDictionary":true,"dictationLanguage":"de","interfaceLanguage":"system"}')
  on conflict (user_id) do nothing;

set local role authenticated;
select set_config('request.jwt.claim.sub', '', true);
do $$
begin
  perform public.flype_delete_account();
  raise exception 'a request without a user must fail';
exception when insufficient_privilege then null;
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
do $$
begin
  if public.flype_delete_account() is distinct from '{"deleted": true}'::jsonb then
    raise exception 'first deletion must report success';
  end if;
  if public.flype_delete_account() is distinct from '{"deleted": false}'::jsonb then
    raise exception 'repeated deletion must report nothing deleted';
  end if;
end $$;
reset role;

do $$
begin
  if exists(select 1 from auth.users where id = '00000000-0000-0000-0000-000000000001')
    or exists(select 1 from public.personal_dictionaries where user_id = '00000000-0000-0000-0000-000000000001')
    or exists(select 1 from public.personal_settings where user_id = '00000000-0000-0000-0000-000000000001') then
    raise exception 'the deleted account left data behind';
  end if;
  if not exists(select 1 from auth.users where id = '00000000-0000-0000-0000-000000000002')
    or not exists(select 1 from public.personal_dictionaries where user_id = '00000000-0000-0000-0000-000000000002')
    or not exists(select 1 from public.personal_settings where user_id = '00000000-0000-0000-0000-000000000002') then
    raise exception 'another account must stay untouched';
  end if;
end $$;
rollback;
