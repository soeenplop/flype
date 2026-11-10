\set ON_ERROR_STOP on
begin;
set local role anon;
do $$
begin
  perform public.flype_subscription_status();
  raise exception 'anon must not read a subscription';
exception when insufficient_privilege then null;
end $$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '', true);
do $$
begin
  perform public.flype_subscription_status();
  raise exception 'a request without a user must fail';
exception when insufficient_privilege then null;
end $$;

-- A new account is free and may still start the trial.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
do $$
declare result jsonb := public.flype_subscription_status();
begin
  if result->>'plan' <> 'free' or not (result->>'trial_available')::boolean or result->'source' <> 'null'::jsonb then
    raise exception 'new account status failed: %', result;
  end if;
end $$;

-- Billing customers stay private.
do $$
begin
  perform count(*) from public.flype_billing_customers;
  raise exception 'billing customers must stay private';
exception when insufficient_privilege then null;
end $$;
reset role;

-- A Stripe and an App Store subscription of the same account live side by side, and the longer one wins.
insert into public.flype_entitlements(user_id, plan, expires_at, source, status, period, will_renew, external_id) values
  ('00000000-0000-0000-0000-000000000001', 'pro', now() + interval '7 days', 'direct', 'trialing', 'year', true, 'sub_1'),
  ('00000000-0000-0000-0000-000000000001', 'pro', now() + interval '20 days', 'app_store', 'active', 'month', false, '2000');
set local role authenticated;
do $$
declare result jsonb := public.flype_subscription_status();
begin
  if result->>'plan' <> 'pro' or result->>'source' <> 'app_store' or result->>'period' <> 'month'
    or (result->>'will_renew')::boolean or (result->>'trial_available')::boolean then
    raise exception 'two sources failed: %', result;
  end if;
end $$;
reset role;

-- The same external subscription cannot belong to two accounts.
do $$
begin
  insert into public.flype_entitlements(user_id, plan, expires_at, source, external_id)
    values ('00000000-0000-0000-0000-000000000002', 'pro', now() + interval '1 day', 'direct', 'sub_1');
  raise exception 'a Stripe subscription was attached twice';
exception when unique_violation then null;
end $$;
do $$
begin
  insert into public.flype_entitlements(user_id, plan, expires_at, source, status)
    values ('00000000-0000-0000-0000-000000000002', 'pro', now() + interval '1 day', 'direct', 'paused');
  raise exception 'an unknown status was accepted';
exception when check_violation then null;
end $$;

-- After both expire the account is free again, and the trial stays used up.
update public.flype_entitlements set expires_at = now() - interval '1 second'
  where user_id = '00000000-0000-0000-0000-000000000001';
set local role authenticated;
do $$
declare result jsonb := public.flype_subscription_status();
begin
  if result->>'plan' <> 'free' or (result->>'trial_available')::boolean then
    raise exception 'expired status failed: %', result;
  end if;
end $$;
reset role;

-- A Pro granted by hand neither shows as purchased nor uses up the trial; a recorded trial does.
insert into public.flype_entitlements(user_id, plan, expires_at, source)
  values ('00000000-0000-0000-0000-000000000002', 'pro', now() + interval '1 year', 'manual');
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', true);
do $$
declare result jsonb := public.flype_subscription_status();
begin
  if result->>'plan' <> 'pro' or result->>'source' <> 'manual' or not (result->>'trial_available')::boolean then
    raise exception 'manual status failed: %', result;
  end if;
end $$;
reset role;
insert into public.flype_billing_customers(user_id, stripe_customer_id, trial_used_at)
  values ('00000000-0000-0000-0000-000000000002', 'cus_2', now());
set local role authenticated;
do $$
begin
  if (public.flype_subscription_status()->>'trial_available')::boolean then raise exception 'used trial was offered'; end if;
end $$;
reset role;

-- Deleting an account removes its billing customer.
delete from auth.users where id = '00000000-0000-0000-0000-000000000002';
do $$
begin
  if exists (select 1 from public.flype_billing_customers where user_id = '00000000-0000-0000-0000-000000000002') then
    raise exception 'billing customer survived account deletion';
  end if;
end $$;
rollback;
