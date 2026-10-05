-- Chez nous : à coller dans Supabase > SQL Editor, puis "Run".
-- Peut être relancé sans risque : rien n'est effacé.

-- Un espace = un couple ou une famille
create table if not exists public.spaces (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('couple','famille')),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

-- Qui fait partie de quel espace (un seul espace par compte)
create table if not exists public.members (
  user_id uuid primary key references auth.users(id) on delete cascade,
  space_id uuid not null references public.spaces(id) on delete cascade,
  joined_at timestamptz not null default now()
);
create index if not exists members_space_idx on public.members(space_id);

-- Invitations en attente, par adresse e-mail
create table if not exists public.invites (
  space_id uuid not null references public.spaces(id) on delete cascade,
  email text not null,
  invited_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (space_id, email)
);

-- Toutes les données de l'appli : personnes, rappels, événements, tâches
create table if not exists public.docs (
  space_id uuid not null references public.spaces(id) on delete cascade,
  coll text not null,          -- 'people' | 'reminders' | 'events' | 'tasks'
  id text not null,
  data jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (space_id, coll, id)
);

alter table public.spaces enable row level security;
alter table public.members enable row level security;
alter table public.invites enable row level security;
alter table public.docs enable row level security;

-- Espace de l'utilisateur connecté (null s'il n'en a pas)
create or replace function public.my_space() returns uuid
language sql stable security definer set search_path = public as $$
  select space_id from public.members where user_id = auth.uid();
$$;

-- E-mail confirmé de l'utilisateur connecté
create or replace function public.my_email() returns text
language sql stable security definer set search_path = public as $$
  select lower(email) from auth.users where id = auth.uid() and email_confirmed_at is not null;
$$;

-- Crée un espace et y inscrit l'utilisateur (renvoie l'espace existant s'il en a déjà un)
create or replace function public.create_space(p_kind text) returns uuid
language plpgsql security definer set search_path = public as $$
declare sid uuid;
begin
  if auth.uid() is null then raise exception 'non connecté'; end if;
  select space_id into sid from public.members where user_id = auth.uid();
  if sid is not null then return sid; end if;
  if p_kind not in ('couple','famille') then raise exception 'type inconnu'; end if;
  insert into public.spaces (kind, created_by) values (p_kind, auth.uid()) returning id into sid;
  insert into public.members (user_id, space_id) values (auth.uid(), sid);
  return sid;
end $$;

-- Invite une adresse e-mail dans son espace : 'ok' | 'invalide' | 'plein' | 'deja_membre' | 'sans_espace'
create or replace function public.invite(p_email text) returns text
language plpgsql security definer set search_path = public as $$
declare sid uuid; k text; n int; e text := lower(trim(p_email));
begin
  sid := public.my_space();
  if sid is null then return 'sans_espace'; end if;
  if e is null or e !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then return 'invalide'; end if;
  select kind into k from public.spaces where id = sid for update;
  if exists (select 1 from public.members m join auth.users u on u.id = m.user_id
             where m.space_id = sid and lower(u.email) = e) then return 'deja_membre'; end if;
  if exists (select 1 from public.invites where space_id = sid and email = e) then return 'ok'; end if;
  select (select count(*) from public.members where space_id = sid)
       + (select count(*) from public.invites where space_id = sid) into n;
  if n >= (case k when 'couple' then 2 else 6 end) then return 'plein'; end if;
  insert into public.invites (space_id, email, invited_by) values (sid, e, auth.uid());
  return 'ok';
end $$;

-- Invitations reçues par l'utilisateur connecté (à son e-mail confirmé)
create or replace function public.my_invites()
returns table (space_id uuid, kind text, from_name text)
language sql stable security definer set search_path = public as $$
  select i.space_id, s.kind, coalesce(d.data->>'name', 'Quelqu''un')
  from public.invites i
  join public.spaces s on s.id = i.space_id
  left join public.docs d on d.space_id = i.space_id and d.coll = 'people' and d.id = i.invited_by::text
  where i.email = public.my_email();
$$;

-- Accepte une invitation : 'ok' | 'plein' | 'introuvable' | 'deja_membre'
create or replace function public.accept_invite(sid uuid) returns text
language plpgsql security definer set search_path = public as $$
declare e text; k text; n int;
begin
  if auth.uid() is null then return 'introuvable'; end if;
  if exists (select 1 from public.members where user_id = auth.uid()) then return 'deja_membre'; end if;
  e := public.my_email();
  if e is null or not exists (select 1 from public.invites where space_id = sid and email = e) then return 'introuvable'; end if;
  select kind into k from public.spaces where id = sid for update;
  select count(*) into n from public.members where space_id = sid;
  if n >= (case k when 'couple' then 2 else 6 end) then return 'plein'; end if;
  insert into public.members (user_id, space_id) values (auth.uid(), sid);
  delete from public.invites where space_id = sid and email = e;
  return 'ok';
end $$;

revoke execute on function public.my_space() from public, anon;
revoke execute on function public.my_email() from public, anon;
revoke execute on function public.create_space(text) from public, anon;
revoke execute on function public.invite(text) from public, anon;
revoke execute on function public.my_invites() from public, anon;
revoke execute on function public.accept_invite(uuid) from public, anon;
grant execute on function public.my_space() to authenticated;
grant execute on function public.my_email() to authenticated;
grant execute on function public.create_space(text) to authenticated;
grant execute on function public.invite(text) to authenticated;
grant execute on function public.my_invites() to authenticated;
grant execute on function public.accept_invite(uuid) to authenticated;

grant select on public.spaces to authenticated;
grant select on public.members to authenticated;
grant select, delete on public.invites to authenticated;
grant select, insert, update, delete on public.docs to authenticated;

-- Chacun ne voit que son propre espace
drop policy if exists "espaces : le sien" on public.spaces;
create policy "espaces : le sien" on public.spaces
  for select to authenticated using (id = public.my_space());

drop policy if exists "membres : son espace" on public.members;
create policy "membres : son espace" on public.members
  for select to authenticated using (space_id = public.my_space());

drop policy if exists "invitations : lecture" on public.invites;
create policy "invitations : lecture" on public.invites
  for select to authenticated using (space_id = public.my_space());

drop policy if exists "invitations : annulation" on public.invites;
create policy "invitations : annulation" on public.invites
  for delete to authenticated using (space_id = public.my_space());

drop policy if exists "docs : son espace" on public.docs;
create policy "docs : son espace" on public.docs
  for all to authenticated using (space_id = public.my_space()) with check (space_id = public.my_space());

-- Adresse secrète iCal du Google Agenda de chacun (lue uniquement par la fonction serveur "gcal")
create table if not exists public.calendar_feeds (
  user_id uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  url text not null check (url like 'https://calendar.google.com/calendar/ical/%'),
  updated_at timestamptz not null default now()
);
alter table public.calendar_feeds enable row level security;
grant select, insert, update, delete on public.calendar_feeds to authenticated;
drop policy if exists "agenda google : le sien" on public.calendar_feeds;
create policy "agenda google : le sien" on public.calendar_feeds
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Mise à jour en direct entre les téléphones
do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'docs') then
    alter publication supabase_realtime add table public.docs;
  end if;
end $$;
