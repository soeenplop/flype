begin;
create table if not exists public.personal_dictionaries (
  user_id uuid primary key references auth.users(id) on delete cascade,
  revision bigint not null default 1 check (revision > 0),
  entries jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now(),
  check (jsonb_typeof(entries) = 'array' and jsonb_array_length(entries) <= 1000),
  check (octet_length(entries::text) <= 2000000)
);
alter table public.personal_dictionaries enable row level security;
revoke all on public.personal_dictionaries from anon, authenticated;
-- Writes only through the revision-checked function below. No client can name another user.
create or replace function public.flype_read_dictionary() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare result jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  select jsonb_build_object('revision', revision, 'entries', entries) into result
    from public.personal_dictionaries where user_id = auth.uid();
  return coalesce(result, jsonb_build_object('revision', 0, 'entries', '[]'::jsonb));
end $$;
create or replace function public.flype_write_dictionary(expected_revision bigint, p_entries jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare current_row public.personal_dictionaries; item jsonb; word text; keys text[] := '{}'; ids uuid[] := '{}'; entry_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  if p_entries is null or jsonb_typeof(p_entries) <> 'array' or jsonb_array_length(p_entries) > 1000
     or octet_length(p_entries::text) > 2000000 then raise exception 'Invalid dictionary'; end if;
  for item in select value from jsonb_array_elements(p_entries) loop
    entry_id := (item->>'id')::uuid;
    if entry_id is null or entry_id = any(ids) then raise exception 'Duplicate or missing entry'; end if;
    ids := array_append(ids, entry_id);
    if jsonb_typeof(item->'spelling') is distinct from 'string'
      or jsonb_typeof(item->'aliases') is distinct from 'array' or jsonb_array_length(item->'aliases') > 8
      or jsonb_typeof(item->'enabled') is distinct from 'boolean'
      or jsonb_typeof(item->'useForTyping') is distinct from 'boolean'
      or jsonb_typeof(item->'useForDictation') is distinct from 'boolean'
      or jsonb_typeof(item->'replaceAliases') is distinct from 'boolean'
      then raise exception 'Invalid entry'; end if;
    if exists(select 1 from jsonb_array_elements(item->'aliases') a where jsonb_typeof(a) <> 'string') then raise exception 'Invalid alias'; end if;
    for word in select item->>'spelling' union all select jsonb_array_elements_text(item->'aliases') loop
      if length(word) not between 1 and 80 or word <> btrim(regexp_replace(word, '\s+', ' ', 'g'))
        or lower(word) = any(keys) then raise exception 'Invalid or duplicate spelling'; end if;
      keys := array_append(keys, lower(word));
    end loop;
  end loop;
  -- Serialize even the first write when no row exists yet.
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text, 0));
  select * into current_row from public.personal_dictionaries where user_id = auth.uid() for update;
  if not found then
    if expected_revision <> 0 or expected_revision is null then
      return jsonb_build_object('revision', 0, 'entries', '[]'::jsonb, 'applied', false);
    end if;
    insert into public.personal_dictionaries(user_id, entries) values(auth.uid(), p_entries) returning * into current_row;
  elsif current_row.revision = expected_revision then
    update public.personal_dictionaries set entries = p_entries, revision = revision + 1, updated_at = now()
      where user_id = auth.uid() returning * into current_row;
  else
    return jsonb_build_object('revision', current_row.revision, 'entries', current_row.entries, 'applied', false);
  end if;
  return jsonb_build_object('revision', current_row.revision, 'entries', current_row.entries, 'applied', true);
end $$;
revoke all on function public.flype_read_dictionary() from public, anon;
revoke all on function public.flype_write_dictionary(bigint,jsonb) from public, anon;
grant execute on function public.flype_read_dictionary() to authenticated;
grant execute on function public.flype_write_dictionary(bigint,jsonb) to authenticated;
commit;
