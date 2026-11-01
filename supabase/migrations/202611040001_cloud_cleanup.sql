begin;
-- Counters for the cloud cleanup. They hold numbers only, never dictated text.
create table public.flype_cleanup_usage (
  user_id uuid primary key references auth.users(id) on delete cascade,
  day date not null,
  requests integer not null default 0,
  characters integer not null default 0,
  minute timestamptz not null,
  minute_requests integer not null default 0
);
create table public.flype_cleanup_global (
  day date primary key,
  requests integer not null default 0
);
alter table public.flype_cleanup_usage enable row level security;
alter table public.flype_cleanup_global enable row level security;
revoke all on public.flype_cleanup_usage, public.flype_cleanup_global from public, anon, authenticated;

-- Runs with the caller's token, so people can only spend their own quota. The global cap limits the bill.
create function public.flype_take_cleanup_quota(p_characters integer) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  user_limit_per_minute constant integer := 10;
  user_limit_per_day constant integer := 200;
  user_characters_per_day constant integer := 50000;
  global_limit_per_day constant integer := 20000;
  current_user_id uuid := auth.uid();
  current_time_ timestamptz := now();
  today date := (current_time_ at time zone 'utc')::date;
  this_minute timestamptz := date_trunc('minute', current_time_);
  usage public.flype_cleanup_usage;
begin
  if current_user_id is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  if p_characters is null or p_characters not between 1 and 5000 then
    raise exception 'Invalid size' using errcode = '22023';
  end if;

  insert into public.flype_cleanup_usage(user_id, day, minute) values (current_user_id, today, this_minute)
    on conflict (user_id) do nothing;
  select * into strict usage from public.flype_cleanup_usage where user_id = current_user_id for update;
  if usage.day <> today then
    usage.day := today; usage.requests := 0; usage.characters := 0;
  end if;
  if usage.minute <> this_minute then
    usage.minute := this_minute; usage.minute_requests := 0;
  end if;

  if usage.minute_requests >= user_limit_per_minute then
    return jsonb_build_object('allowed', false, 'scope', 'minute',
      'retry_after', ceil(extract(epoch from this_minute + interval '1 minute' - current_time_))::integer);
  end if;
  if usage.requests >= user_limit_per_day or usage.characters + p_characters > user_characters_per_day then
    return jsonb_build_object('allowed', false, 'scope', 'day',
      'retry_after', ceil(extract(epoch from
        ((today + 1)::timestamp at time zone 'utc') - current_time_))::integer);
  end if;

  insert into public.flype_cleanup_global as global_usage(day, requests) values (today, 1)
    on conflict (day) do update set requests = global_usage.requests + 1
    where global_usage.requests < global_limit_per_day;
  if not found then
    return jsonb_build_object('allowed', false, 'scope', 'service');
  end if;
  delete from public.flype_cleanup_global where day < today - 7;

  update public.flype_cleanup_usage set
    day = usage.day, requests = usage.requests + 1, characters = usage.characters + p_characters,
    minute = usage.minute, minute_requests = usage.minute_requests + 1
    where user_id = current_user_id;
  return jsonb_build_object('allowed', true);
end $$;
revoke all on function public.flype_take_cleanup_quota(integer) from public, anon;
grant execute on function public.flype_take_cleanup_quota(integer) to authenticated;
notify pgrst, 'reload schema';
commit;
