\set ON_ERROR_STOP on
begin;
set local role anon;
do $$
begin
  perform public.flype_take_cleanup_quota(10);
  raise exception 'anon must not take quota';
exception when insufficient_privilege then null;
end $$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '', true);
do $$
begin
  perform public.flype_take_cleanup_quota(10);
  raise exception 'a request without a user must fail';
exception when insufficient_privilege then null;
end $$;

-- People cannot read or reset the counters directly.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
do $$
begin
  perform count(*) from public.flype_cleanup_usage;
  raise exception 'counters must stay private';
exception when insufficient_privilege then null;
end $$;
do $$
begin
  perform public.flype_take_cleanup_quota(5001);
  raise exception 'oversized requests must fail';
exception when invalid_parameter_value then null;
end $$;

-- The per-minute limit stops the eleventh request and only affects this user.
do $$
declare result jsonb;
begin
  for i in 1..10 loop
    result := public.flype_take_cleanup_quota(10);
    if not (result->>'allowed')::boolean then raise exception 'request % should pass', i; end if;
  end loop;
  result := public.flype_take_cleanup_quota(10);
  if (result->>'allowed')::boolean or result->>'scope' <> 'minute' or (result->>'retry_after')::integer not between 0 and 60 then
    raise exception 'minute limit failed: %', result;
  end if;
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', true);
do $$
begin
  if not (public.flype_take_cleanup_quota(10)->>'allowed')::boolean then raise exception 'other user was limited'; end if;
end $$;
reset role;

-- A new minute continues, but the daily request and character limits still apply.
update public.flype_cleanup_usage set minute = minute - interval '1 minute', requests = 200
  where user_id = '00000000-0000-0000-0000-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
do $$
declare result jsonb := public.flype_take_cleanup_quota(10);
begin
  if (result->>'allowed')::boolean or result->>'scope' <> 'day' then raise exception 'daily limit failed: %', result; end if;
end $$;
reset role;
update public.flype_cleanup_usage set requests = 0, characters = 49995
  where user_id = '00000000-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare result jsonb := public.flype_take_cleanup_quota(10);
begin
  if (result->>'allowed')::boolean or result->>'scope' <> 'day' then raise exception 'character limit failed: %', result; end if;
end $$;
reset role;

-- A new day resets the counters, while the global cap protects the bill.
update public.flype_cleanup_usage set day = day - 1
  where user_id = '00000000-0000-0000-0000-000000000001';
set local role authenticated;
do $$
begin
  if not (public.flype_take_cleanup_quota(10)->>'allowed')::boolean then raise exception 'new day was limited'; end if;
end $$;
reset role;
do $$
begin
  if (select characters from public.flype_cleanup_usage where user_id = '00000000-0000-0000-0000-000000000001') <> 10 then
    raise exception 'daily counters were not reset';
  end if;
end $$;
update public.flype_cleanup_global set requests = 20000;
update public.flype_cleanup_usage set minute = minute - interval '1 minute'
  where user_id = '00000000-0000-0000-0000-000000000002';
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', true);
do $$
declare result jsonb := public.flype_take_cleanup_quota(10);
begin
  if (result->>'allowed')::boolean or result->>'scope' <> 'service' then raise exception 'global cap failed: %', result; end if;
end $$;
reset role;

-- Free accounts stop at the weekly allowance until next Monday; a new week starts it again.
update public.flype_cleanup_global set requests = 0;
update public.flype_cleanup_usage set minute = minute - interval '1 minute', requests = 0, characters = 0,
  week_requests = 100 where user_id = '00000000-0000-0000-0000-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
do $$
declare result jsonb := public.flype_take_cleanup_quota(10);
begin
  if (result->>'allowed')::boolean or result->>'scope' <> 'week' or result->>'plan' <> 'free'
    or (result->>'retry_after')::integer not between 1 and 7 * 86400 then
    raise exception 'weekly request limit failed: %', result;
  end if;
end $$;
reset role;
update public.flype_cleanup_usage set week_requests = 0, week_characters = 19995
  where user_id = '00000000-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare result jsonb := public.flype_take_cleanup_quota(10);
begin
  if (result->>'allowed')::boolean or result->>'scope' <> 'week' then raise exception 'weekly character limit failed: %', result; end if;
end $$;
reset role;
update public.flype_cleanup_usage set week = week - 7
  where user_id = '00000000-0000-0000-0000-000000000001';
set local role authenticated;
do $$
begin
  if not (public.flype_take_cleanup_quota(10)->>'allowed')::boolean then raise exception 'new week was limited'; end if;
end $$;
reset role;
do $$
begin
  if (select week_characters from public.flype_cleanup_usage where user_id = '00000000-0000-0000-0000-000000000001') <> 10 then
    raise exception 'weekly counters were not reset';
  end if;
end $$;

-- People can read their own entitlement but never grant one.
insert into auth.users(id) values ('00000000-0000-0000-0000-000000000003') on conflict do nothing;
insert into public.flype_entitlements(user_id, plan, expires_at, source) values
  ('00000000-0000-0000-0000-000000000001', 'pro', now() + interval '30 days', 'manual'),
  ('00000000-0000-0000-0000-000000000003', 'pro', now() + interval '30 days', 'manual');
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
do $$
begin
  if (select count(*) from public.flype_entitlements) <> 1 then raise exception 'entitlements of others are visible'; end if;
end $$;
do $$
begin
  update public.flype_entitlements set expires_at = now() + interval '10 years';
  raise exception 'people must not extend their entitlement';
exception when insufficient_privilege then null;
end $$;
do $$
begin
  insert into public.flype_entitlements(user_id, plan, expires_at, source)
    values ('00000000-0000-0000-0000-000000000002', 'pro', now() + interval '1 year', 'manual');
  raise exception 'people must not grant entitlements';
exception when insufficient_privilege then null;
end $$;
reset role;

-- Pro has no weekly allowance and a higher daily one.
update public.flype_cleanup_usage set minute = minute - interval '1 minute', requests = 300, characters = 0,
  week_requests = 1000, week_characters = 100000 where user_id = '00000000-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare result jsonb := public.flype_take_cleanup_quota(10);
begin
  if not (result->>'allowed')::boolean or result->>'plan' <> 'pro' then raise exception 'pro was limited: %', result; end if;
end $$;
reset role;
update public.flype_cleanup_usage set minute = minute - interval '1 minute', requests = 500
  where user_id = '00000000-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare result jsonb := public.flype_take_cleanup_quota(10);
begin
  if (result->>'allowed')::boolean or result->>'scope' <> 'day' or result->>'plan' <> 'pro' then
    raise exception 'pro daily limit failed: %', result;
  end if;
end $$;
reset role;

-- An expired entitlement counts as free again.
update public.flype_entitlements set expires_at = now() - interval '1 second'
  where user_id = '00000000-0000-0000-0000-000000000001';
update public.flype_cleanup_usage set minute = minute - interval '1 minute', requests = 0
  where user_id = '00000000-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare result jsonb := public.flype_take_cleanup_quota(10);
begin
  if (result->>'allowed')::boolean or result->>'scope' <> 'week' or result->>'plan' <> 'free' then
    raise exception 'expired pro still counted: %', result;
  end if;
end $$;
reset role;

-- Deleting an account removes its entitlement.
delete from auth.users where id = '00000000-0000-0000-0000-000000000003';
do $$
begin
  if exists (select 1 from public.flype_entitlements where user_id = '00000000-0000-0000-0000-000000000003') then
    raise exception 'entitlement survived account deletion';
  end if;
end $$;

-- Deleting an account removes its counters.
delete from auth.users where id = '00000000-0000-0000-0000-000000000002';
do $$
begin
  if exists (select 1 from public.flype_cleanup_usage where user_id = '00000000-0000-0000-0000-000000000002') then
    raise exception 'counters survived account deletion';
  end if;
end $$;
rollback;
