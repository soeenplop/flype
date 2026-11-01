set role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
do $$
declare a jsonb := '{"dictationMode":"cleaned","applyDictionary":true,"dictationLanguage":"de","interfaceLanguage":"system"}';
  result jsonb; invalid jsonb;
begin
  if public.flype_read_settings()->>'revision' <> '0' or public.flype_read_settings()->'settings' <> 'null'::jsonb then raise exception 'Initial settings not empty'; end if;
  result := public.flype_write_settings(0, a);
  if result->>'applied' <> 'true' or result->>'revision' <> '1' or result->'settings' <> a then raise exception 'First settings write failed'; end if;
  result := public.flype_write_settings(0, jsonb_set(a,'{dictationLanguage}','"fr"'));
  if result->>'applied' <> 'false' or result->'settings' <> a then raise exception 'Stale settings write lost data'; end if;
  for invalid in select value from jsonb_array_elements(jsonb_build_array(
    '{}'::jsonb, 'null'::jsonb, '[]'::jsonb,
    a || '{"secret":"must-not-sync"}'::jsonb,
    a || '{"speechProvider":"unknown"}'::jsonb,
    a || '{"speechProvider":null}'::jsonb,
    a || '{"speechProvider":true}'::jsonb,
    a || '{"dictationKey":"96"}'::jsonb,
    a || '{"dictationKey":null}'::jsonb,
    a || '{"dictationKey":256}'::jsonb,
    a || '{"dictationKey":-1}'::jsonb,
    a || '{"dictationKey":1.5}'::jsonb,
    a || '{"dictationKey":53}'::jsonb,
    a || '{"dictationKey":57}'::jsonb,
    a || '{"dictationMode":"unknown"}'::jsonb,
    a || '{"applyDictionary":"true"}'::jsonb,
    a || '{"dictationLanguage":"xx"}'::jsonb,
    a || '{"interfaceLanguage":"xx"}'::jsonb,
    a || '{"dictationMode":null}'::jsonb,
    a || '{"dictationLanguage":null}'::jsonb,
    a || '{"interfaceLanguage":null}'::jsonb
  )) loop
    begin
      perform public.flype_write_settings(1, invalid);
      raise exception 'Invalid settings accepted';
    exception when raise_exception or check_violation then
      if sqlerrm = 'Invalid settings accepted' then raise; end if;
    end;
  end loop;
  begin
    perform * from public.personal_settings;
    raise exception 'Direct settings table access allowed';
  exception when insufficient_privilege then null;
  end;
  result := public.flype_write_settings(1, jsonb_set(a,'{dictationLanguage}','"fr"'));
  if result->>'revision' <> '2' or result->>'applied' <> 'true' then raise exception 'Settings update failed'; end if;
  result := public.flype_write_settings(2, a || '{"speechProvider":"parakeet"}'::jsonb);
  if result->>'revision' <> '3' or result->'settings'->>'speechProvider' <> 'parakeet' then raise exception 'Model choice not saved'; end if;
  result := public.flype_write_settings(3, jsonb_set(a,'{dictationLanguage}','"fr"'));
  if result->>'revision' <> '4' or result->'settings'->>'speechProvider' <> 'parakeet' then raise exception 'Legacy client reset model choice'; end if;
  result := public.flype_write_settings(3, a || '{"speechProvider":"apple"}'::jsonb);
  if result->>'applied' <> 'false' or result->'settings'->>'speechProvider' <> 'parakeet' then raise exception 'Stale model write lost data'; end if;
  result := public.flype_write_settings(4, jsonb_set(a,'{dictationLanguage}','"fr"') || '{"speechProvider":"apple"}'::jsonb);
  if result->>'applied' <> 'true' or result->'settings'->>'speechProvider' <> 'apple' then raise exception 'Model switch failed'; end if;
  result := public.flype_write_settings(5, a || '{"speechProvider":"apple","dictationKey":96}'::jsonb);
  if result->>'applied' <> 'true' or result->'settings'->>'dictationKey' <> '96' then raise exception 'Dictation key not saved'; end if;
  result := public.flype_write_settings(6, jsonb_set(a,'{dictationLanguage}','"fr"') || '{"speechProvider":"apple"}'::jsonb);
  if result->>'applied' <> 'true' or result->'settings'->>'dictationKey' <> '96' then raise exception 'Legacy client reset dictation key'; end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
do $$ begin
  if public.flype_read_settings()->>'revision' <> '0' then raise exception 'Cross-user settings disclosure'; end if;
  perform public.flype_write_settings(0, '{"dictationMode":"verbatim","applyDictionary":false,"dictationLanguage":"en","interfaceLanguage":"nl"}');
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
do $$ begin
  if public.flype_read_settings()->'settings'->>'dictationLanguage' <> 'fr' then raise exception 'Other user overwrote settings'; end if;
end $$;
select set_config('request.jwt.claim.sub','',false);
do $$ begin
  begin
    perform public.flype_read_settings();
    raise exception 'Missing user accepted';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
set role anon;
do $$ begin
  begin
    perform public.flype_read_settings();
    raise exception 'Anonymous settings read allowed';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.flype_write_settings(0, '{}');
    raise exception 'Anonymous settings write allowed';
  exception when insufficient_privilege then null;
  end;
end $$;
