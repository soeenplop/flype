begin;
create table if not exists public.personal_settings (
  user_id uuid primary key references auth.users(id) on delete cascade,
  revision bigint not null default 1 check (revision > 0),
  settings jsonb not null,
  updated_at timestamptz not null default now(),
  check (
    jsonb_typeof(settings) = 'object'
    and settings ?& array['dictationMode','applyDictionary','dictationLanguage','interfaceLanguage']
    and settings - array['dictationMode','applyDictionary','dictationLanguage','interfaceLanguage'] = '{}'::jsonb
    and settings->>'dictationMode' in ('cleaned','verbatim')
    and jsonb_typeof(settings->'applyDictionary') = 'boolean'
    and settings->>'dictationLanguage' in ('de','en','fr','it','es','nl')
    and settings->>'interfaceLanguage' in ('system','de','en','fr','it','es','nl')
    and octet_length(settings::text) <= 1024
  )
);
alter table public.personal_settings enable row level security;
revoke all on public.personal_settings from anon, authenticated;

create or replace function public.flype_read_settings() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare result jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  select jsonb_build_object('revision', revision, 'settings', settings) into result
    from public.personal_settings where user_id = auth.uid();
  return coalesce(result, jsonb_build_object('revision', 0, 'settings', null));
end $$;

create or replace function public.flype_write_settings(expected_revision bigint, p_settings jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare current_row public.personal_settings;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  if p_settings is null or jsonb_typeof(p_settings) is distinct from 'object'
    or not (p_settings ?& array['dictationMode','applyDictionary','dictationLanguage','interfaceLanguage'])
    or p_settings - array['dictationMode','applyDictionary','dictationLanguage','interfaceLanguage'] <> '{}'::jsonb
    or p_settings->>'dictationMode' not in ('cleaned','verbatim')
    or jsonb_typeof(p_settings->'applyDictionary') is distinct from 'boolean'
    or p_settings->>'dictationLanguage' not in ('de','en','fr','it','es','nl')
    or p_settings->>'interfaceLanguage' not in ('system','de','en','fr','it','es','nl')
    or octet_length(p_settings::text) > 1024
    or p_settings->'dictationMode' = 'null'::jsonb
    or p_settings->'dictationLanguage' = 'null'::jsonb
    or p_settings->'interfaceLanguage' = 'null'::jsonb
    then raise exception 'Invalid settings'; end if;
  perform pg_advisory_xact_lock(hashtextextended('settings:' || auth.uid()::text, 0));
  select * into current_row from public.personal_settings where user_id = auth.uid() for update;
  if not found then
    if expected_revision is distinct from 0 then
      return jsonb_build_object('revision', 0, 'settings', null, 'applied', false);
    end if;
    insert into public.personal_settings(user_id, settings) values(auth.uid(), p_settings) returning * into current_row;
  elsif current_row.revision = expected_revision then
    update public.personal_settings set settings = p_settings, revision = revision + 1, updated_at = now()
      where user_id = auth.uid() returning * into current_row;
  else
    return jsonb_build_object('revision', current_row.revision, 'settings', current_row.settings, 'applied', false);
  end if;
  return jsonb_build_object('revision', current_row.revision, 'settings', current_row.settings, 'applied', true);
end $$;
revoke all on function public.flype_read_settings() from public, anon;
revoke all on function public.flype_write_settings(bigint,jsonb) from public, anon;
grant execute on function public.flype_read_settings() to authenticated;
grant execute on function public.flype_write_settings(bigint,jsonb) to authenticated;
commit;
