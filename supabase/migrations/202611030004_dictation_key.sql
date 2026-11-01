begin;
alter table public.personal_settings drop constraint personal_settings_settings_check;
alter table public.personal_settings add constraint personal_settings_settings_check
  check (
    jsonb_typeof(settings) = 'object'
    and settings ?& array['dictationMode','applyDictionary','dictationLanguage','interfaceLanguage']
    and settings - array['dictationMode','applyDictionary','dictationLanguage','interfaceLanguage','speechProvider','dictationKey'] = '{}'::jsonb
    and settings->>'dictationMode' in ('cleaned','verbatim')
    and jsonb_typeof(settings->'applyDictionary') = 'boolean'
    and settings->>'dictationLanguage' in ('de','en','fr','it','es','nl')
    and settings->>'interfaceLanguage' in ('system','de','en','fr','it','es','nl')
    and (not (settings ? 'speechProvider') or (jsonb_typeof(settings->'speechProvider') = 'string' and settings->>'speechProvider' in ('apple','parakeet')))
    and (not (settings ? 'dictationKey') or (jsonb_typeof(settings->'dictationKey') = 'number' and settings->>'dictationKey' ~ '^([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$' and settings->>'dictationKey' not in ('53','57')))
    and octet_length(settings::text) <= 1024
  );

create or replace function public.flype_write_settings(expected_revision bigint, p_settings jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare current_row public.personal_settings;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  if p_settings is null or jsonb_typeof(p_settings) is distinct from 'object'
    or not (p_settings ?& array['dictationMode','applyDictionary','dictationLanguage','interfaceLanguage'])
    or p_settings - array['dictationMode','applyDictionary','dictationLanguage','interfaceLanguage','speechProvider','dictationKey'] <> '{}'::jsonb
    or p_settings->>'dictationMode' not in ('cleaned','verbatim')
    or jsonb_typeof(p_settings->'applyDictionary') is distinct from 'boolean'
    or p_settings->>'dictationLanguage' not in ('de','en','fr','it','es','nl')
    or p_settings->>'interfaceLanguage' not in ('system','de','en','fr','it','es','nl')
    or (p_settings ? 'speechProvider' and (jsonb_typeof(p_settings->'speechProvider') is distinct from 'string' or p_settings->>'speechProvider' not in ('apple','parakeet')))
    or (p_settings ? 'dictationKey' and (jsonb_typeof(p_settings->'dictationKey') is distinct from 'number' or p_settings->>'dictationKey' !~ '^([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$' or p_settings->>'dictationKey' in ('53','57')))
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
    -- Older app versions send only four fields. Preserve the newer model choice.
    if not (p_settings ? 'speechProvider') and current_row.settings ? 'speechProvider' then
      p_settings := p_settings || jsonb_build_object('speechProvider', current_row.settings->'speechProvider');
    end if;
    -- Older app versions do not know the dictation key. Preserve it as well.
    if not (p_settings ? 'dictationKey') and current_row.settings ? 'dictationKey' then
      p_settings := p_settings || jsonb_build_object('dictationKey', current_row.settings->'dictationKey');
    end if;
    update public.personal_settings set settings = p_settings, revision = revision + 1, updated_at = now()
      where user_id = auth.uid() returning * into current_row;
  else
    return jsonb_build_object('revision', current_row.revision, 'settings', current_row.settings, 'applied', false);
  end if;
  return jsonb_build_object('revision', current_row.revision, 'settings', current_row.settings, 'applied', true);
end $$;
notify pgrst, 'reload schema';
commit;
