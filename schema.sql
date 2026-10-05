-- Chez nous : à coller dans Supabase > SQL Editor, puis "Run".

-- Les deux membres du foyer (deux comptes maximum)
create table if not exists public.members (
  user_id uuid primary key references auth.users(id) on delete cascade,
  joined_at timestamptz not null default now()
);

-- Toutes les données de l'appli : rappels, événements, tâches, réglages
create table if not exists public.docs (
  coll text not null,          -- 'reminders' | 'events' | 'tasks' | 'config'
  id text not null,
  data jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (coll, id)
);

alter table public.members enable row level security;
alter table public.docs enable row level security;

create or replace function public.is_member() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.members where user_id = auth.uid());
$$;

-- Inscrit l'utilisateur connecté comme membre tant qu'il reste une place
create or replace function public.join_home() returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return false; end if;
  if exists (select 1 from public.members where user_id = auth.uid()) then return true; end if;
  lock table public.members in exclusive mode;
  if (select count(*) from public.members) >= 2 then return false; end if;
  insert into public.members (user_id) values (auth.uid());
  return true;
end $$;

revoke execute on function public.is_member() from public, anon;
revoke execute on function public.join_home() from public, anon;
grant execute on function public.is_member() to authenticated;
grant execute on function public.join_home() to authenticated;

grant select on public.members to authenticated;
grant select, insert, update, delete on public.docs to authenticated;

drop policy if exists "membres : lecture" on public.members;
create policy "membres : lecture" on public.members
  for select to authenticated using (public.is_member());

drop policy if exists "docs : membres seulement" on public.docs;
create policy "docs : membres seulement" on public.docs
  for all to authenticated using (public.is_member()) with check (public.is_member());

-- Mise à jour en direct entre vos deux téléphones
do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'docs') then
    alter publication supabase_realtime add table public.docs;
  end if;
end $$;
