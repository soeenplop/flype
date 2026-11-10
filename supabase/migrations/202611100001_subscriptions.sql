begin;
-- One row per account and source, so a Stripe and an App Store subscription never overwrite each other.
-- expires_at alone decides Pro: it is the end of the paid or trial period plus a short grace period for
-- retried payments. The other columns only describe the subscription to the apps.
alter table public.flype_entitlements drop constraint flype_entitlements_pkey;
alter table public.flype_entitlements add primary key (user_id, source);
alter table public.flype_entitlements
  add column status text not null default 'active' check (status in ('trialing', 'active', 'past_due', 'canceled')),
  add column period text check (period in ('month', 'year')),
  add column will_renew boolean not null default false,
  -- Stripe subscription ID or the App Store's original transaction ID.
  add column external_id text;
create unique index flype_entitlements_external_id on public.flype_entitlements(source, external_id)
  where external_id is not null;

-- The Stripe customer of an account, and whether it ever had a free trial on any platform. Only the
-- service role reads or writes it.
create table public.flype_billing_customers (
  user_id uuid primary key references auth.users(id) on delete cascade,
  stripe_customer_id text unique,
  trial_used_at timestamptz,
  updated_at timestamptz not null default now()
);
alter table public.flype_billing_customers enable row level security;
revoke all on public.flype_billing_customers from public, anon, authenticated;

-- What the apps show: the active subscription that lasts longest, and whether the yearly trial is still
-- open. A trial is offered once per account, so any earlier purchase on either platform also uses it up.
create or replace function public.flype_subscription_status() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  current_user_id uuid := auth.uid();
  active public.flype_entitlements;
begin
  if current_user_id is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  select * into active from public.flype_entitlements e
    where e.user_id = current_user_id and e.plan = 'pro' and e.expires_at > now()
    order by e.expires_at desc limit 1;
  return jsonb_build_object(
    'plan', case when active.user_id is null then 'free' else 'pro' end,
    'source', active.source,
    'status', active.status,
    'period', active.period,
    'will_renew', active.will_renew,
    'expires_at', active.expires_at,
    'trial_available', not exists (
      select 1 from public.flype_billing_customers c
      where c.user_id = current_user_id and c.trial_used_at is not null
    ) and not exists (
      select 1 from public.flype_entitlements e
      where e.user_id = current_user_id and e.source in ('app_store', 'direct')
    ));
end $$;
revoke all on function public.flype_subscription_status() from public, anon;
grant execute on function public.flype_subscription_status() to authenticated;
notify pgrst, 'reload schema';
commit;
