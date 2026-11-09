begin;
-- Pro is a time-limited entitlement per account. Only the service role writes it (App Store or direct
-- purchase, or by hand while there is no checkout yet); people can read their own row.
create table public.flype_entitlements (
  user_id uuid primary key references auth.users(id) on delete cascade,
  plan text not null check (plan = 'pro'),
  expires_at timestamptz not null,
  source text not null check (source in ('app_store', 'direct', 'manual')),
  updated_at timestamptz not null default now()
);
alter table public.flype_entitlements enable row level security;
revoke all on public.flype_entitlements from public, anon, authenticated;
grant select on public.flype_entitlements to authenticated;
create policy "Read own entitlement" on public.flype_entitlements for select to authenticated
  using (user_id = auth.uid());

-- Free accounts also have a weekly allowance. Weeks start on Monday, UTC.
alter table public.flype_cleanup_usage
  add column week date not null default date_trunc('week', now() at time zone 'utc')::date,
  add column week_requests integer not null default 0,
  add column week_characters integer not null default 0;

-- Free: 100 cleanups and 20,000 characters a week (about 2,000 dictated words, since the text around
-- the cursor counts too), at most 200 and 50,000 a day. Pro: no weekly allowance, 500 and 150,000 a day
-- as fair use. The global cap still limits the bill.
create or replace function public.flype_take_cleanup_quota(p_characters integer) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  user_limit_per_minute constant integer := 10;
  free_requests_per_week constant integer := 100;
  free_characters_per_week constant integer := 20000;
  global_limit_per_day constant integer := 20000;
  current_user_id uuid := auth.uid();
  current_time_ timestamptz := now();
  today date := (current_time_ at time zone 'utc')::date;
  this_week date := date_trunc('week', current_time_ at time zone 'utc')::date;
  this_minute timestamptz := date_trunc('minute', current_time_);
  plan text;
  requests_per_day integer;
  characters_per_day integer;
  usage public.flype_cleanup_usage;
begin
  if current_user_id is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  if p_characters is null or p_characters not between 1 and 5000 then
    raise exception 'Invalid size' using errcode = '22023';
  end if;
  plan := case when exists (
    select 1 from public.flype_entitlements e
    where e.user_id = current_user_id and e.plan = 'pro' and e.expires_at > current_time_
  ) then 'pro' else 'free' end;
  requests_per_day := case plan when 'pro' then 500 else 200 end;
  characters_per_day := case plan when 'pro' then 150000 else 50000 end;

  insert into public.flype_cleanup_usage(user_id, day, minute, week) values (current_user_id, today, this_minute, this_week)
    on conflict (user_id) do nothing;
  select * into strict usage from public.flype_cleanup_usage where user_id = current_user_id for update;
  if usage.day <> today then
    usage.day := today; usage.requests := 0; usage.characters := 0;
  end if;
  if usage.week <> this_week then
    usage.week := this_week; usage.week_requests := 0; usage.week_characters := 0;
  end if;
  if usage.minute <> this_minute then
    usage.minute := this_minute; usage.minute_requests := 0;
  end if;

  if usage.minute_requests >= user_limit_per_minute then
    return jsonb_build_object('allowed', false, 'scope', 'minute', 'plan', plan,
      'retry_after', ceil(extract(epoch from this_minute + interval '1 minute' - current_time_))::integer);
  end if;
  if plan = 'free' and (usage.week_requests >= free_requests_per_week
      or usage.week_characters + p_characters > free_characters_per_week) then
    return jsonb_build_object('allowed', false, 'scope', 'week', 'plan', plan,
      'retry_after', ceil(extract(epoch from
        ((this_week + 7)::timestamp at time zone 'utc') - current_time_))::integer);
  end if;
  if usage.requests >= requests_per_day or usage.characters + p_characters > characters_per_day then
    return jsonb_build_object('allowed', false, 'scope', 'day', 'plan', plan,
      'retry_after', ceil(extract(epoch from
        ((today + 1)::timestamp at time zone 'utc') - current_time_))::integer);
  end if;

  insert into public.flype_cleanup_global as global_usage(day, requests) values (today, 1)
    on conflict (day) do update set requests = global_usage.requests + 1
    where global_usage.requests < global_limit_per_day;
  if not found then
    return jsonb_build_object('allowed', false, 'scope', 'service', 'plan', plan);
  end if;
  delete from public.flype_cleanup_global where day < today - 7;

  update public.flype_cleanup_usage set
    day = usage.day, requests = usage.requests + 1, characters = usage.characters + p_characters,
    week = usage.week, week_requests = usage.week_requests + 1,
    week_characters = usage.week_characters + p_characters,
    minute = usage.minute, minute_requests = usage.minute_requests + 1
    where user_id = current_user_id;
  return jsonb_build_object('allowed', true, 'plan', plan);
end $$;
revoke all on function public.flype_take_cleanup_quota(integer) from public, anon;
grant execute on function public.flype_take_cleanup_quota(integer) to authenticated;
notify pgrst, 'reload schema';
commit;
