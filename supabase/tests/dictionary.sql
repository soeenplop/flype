set role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
do $$
declare first_result jsonb; stale_result jsonb; item jsonb := '[{"id":"10000000-0000-0000-0000-000000000001","spelling":"Flype","aliases":[],"enabled":true,"useForTyping":true,"useForDictation":true,"replaceAliases":false}]';
begin
  if public.flype_read_dictionary()->>'revision' <> '0' then raise exception 'Initial dictionary not empty'; end if;
  first_result := public.flype_write_dictionary(0, item);
  if first_result->>'applied' <> 'true' or first_result->>'revision' <> '1' then raise exception 'First write failed'; end if;
  stale_result := public.flype_write_dictionary(0, '[]');
  if stale_result->>'applied' <> 'false' or stale_result->'entries' <> item then raise exception 'Stale write lost data'; end if;
  begin
    perform public.flype_write_dictionary(1, '[{}]');
    raise exception 'Invalid entry accepted';
  exception when raise_exception then
    if sqlerrm = 'Invalid entry accepted' then raise; end if;
  end;
  begin
    perform public.flype_write_dictionary(1, item || item);
    raise exception 'Duplicate accepted';
  exception when raise_exception then
    if sqlerrm = 'Duplicate accepted' then raise; end if;
  end;
  begin
    perform * from public.personal_dictionaries;
    raise exception 'Direct table access allowed';
  exception when insufficient_privilege then null;
  end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
do $$ begin
  if public.flype_read_dictionary()->>'revision' <> '0' then raise exception 'Cross-user data disclosure'; end if;
  perform public.flype_write_dictionary(0, '[]');
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
do $$ begin
  if jsonb_array_length(public.flype_read_dictionary()->'entries') <> 1 then raise exception 'Other user overwrote dictionary'; end if;
  if public.flype_write_dictionary(1, '[]')->>'revision' <> '2' then raise exception 'Deletion failed'; end if;
end $$;
reset role;
set role anon;
do $$ begin
  begin
    perform public.flype_read_dictionary();
    raise exception 'Anonymous read allowed';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.flype_write_dictionary(0, '[]');
    raise exception 'Anonymous write allowed';
  exception when insufficient_privilege then null;
  end;
end $$;
