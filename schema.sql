-- JURICALC: base inicial para Supabase Postgres
create extension if not exists pgcrypto;
create table if not exists public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 display_name text not null default 'Novo usuário',
 role text not null default 'calculista' check (role in ('admin','calculista','digitador')),
 can_assign boolean not null default false,
 active boolean not null default true,
 created_at timestamptz not null default now()
);
create table if not exists public.cases (
 id uuid primary key default gen_random_uuid(),
 name text not null,
 case_number text not null unique,
 calculator_id uuid references public.profiles(id),
 typist_id uuid references public.profiles(id),
 status text not null default 'Parado' check(status in ('Parado','Em andamento','Aguardando PDF','Aguardando digitação','Em digitação','Concluído')),
 status_changed_at timestamptz not null default now(),
 created_at timestamptz not null default now(),
 created_by uuid references public.profiles(id)
);
create table if not exists public.case_events (
 id bigint generated always as identity primary key,
 case_id uuid not null references public.cases(id) on delete restrict,
 actor_id uuid references public.profiles(id),
 old_status text,
 new_status text,
 old_typist_id uuid,
 new_typist_id uuid,
 created_at timestamptz not null default now()
);
create or replace function public.create_profile() returns trigger language plpgsql security definer set search_path = '' as $$
begin
 insert into public.profiles(id,display_name) values(new.id,coalesce(new.raw_user_meta_data->>'full_name','Novo usuário')) on conflict(id) do nothing;
 return new;
end; $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.create_profile();
create or replace function public.is_admin() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles where id=(select auth.uid()) and role='admin' and active);
$$;
create or replace function public.is_assigner() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles where id=(select auth.uid()) and role='admin' and can_assign and active);
$$;
create or replace function public.is_active() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles where id=(select auth.uid()) and active);
$$;
create or replace function public.audit_case() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='UPDATE' then
   if new.status is distinct from old.status then new.status_changed_at=now(); end if;
   if new.status is distinct from old.status or new.typist_id is distinct from old.typist_id then
     insert into public.case_events(case_id,actor_id,old_status,new_status,old_typist_id,new_typist_id)
     values(old.id,auth.uid(),old.status,new.status,old.typist_id,new.typist_id);
   end if;
 elsif tg_op='INSERT' then
   insert into public.case_events(case_id,actor_id,new_status,new_typist_id)
   values(new.id,auth.uid(),new.status,new.typist_id);
 end if;
 return new;
end; $$;
drop trigger if exists case_audit_insert on public.cases;
create trigger case_audit_insert after insert on public.cases for each row execute function public.audit_case();
drop trigger if exists case_audit_update on public.cases;
create trigger case_audit_update after update on public.cases for each row execute function public.audit_case();
-- Enforcement in database, not just UI
create or replace function public.check_case_update() returns trigger language plpgsql security definer set search_path='' as $$
declare r text; a boolean;
begin
 select role,active into r,a from public.profiles where id=auth.uid();
 if a is distinct from true then raise exception 'Conta inativa'; end if;
 if new.id is distinct from old.id or new.created_at is distinct from old.created_at or new.created_by is distinct from old.created_by then raise exception 'Campos imutáveis'; end if;
 if new.typist_id is distinct from old.typist_id and not public.is_assigner() then raise exception 'Somente Felipe pode distribuir'; end if;
 if r='calculista' then
   if old.calculator_id is distinct from auth.uid() or new.calculator_id is distinct from old.calculator_id or new.name is distinct from old.name or new.case_number is distinct from old.case_number or new.typist_id is distinct from old.typist_id or new.status not in ('Parado','Em andamento','Aguardando PDF','Aguardando digitação') then raise exception 'Alteração não autorizada'; end if;
 elsif r='digitador' then
   if old.typist_id is distinct from auth.uid() or new.typist_id is distinct from old.typist_id or new.calculator_id is distinct from old.calculator_id or new.name is distinct from old.name or new.case_number is distinct from old.case_number or new.status not in ('Parado','Em digitação','Concluído') then raise exception 'Alteração não autorizada'; end if;
 elsif r<>'admin' then raise exception 'Sem permissão'; end if;
 if new.status is distinct from old.status and new.status_changed_at is distinct from old.status_changed_at then raise exception 'Data do status é automática'; end if;
 return new;
end; $$;
drop trigger if exists check_case_before_update on public.cases;
create trigger check_case_before_update before update on public.cases for each row execute function public.check_case_update();
alter table public.profiles enable row level security;
alter table public.cases enable row level security;
alter table public.case_events enable row level security;
create policy profiles_read on public.profiles for select to authenticated using(public.is_active());
create policy cases_read on public.cases for select to authenticated using(public.is_active() and (public.is_admin() or calculator_id=auth.uid() or typist_id=auth.uid()));
create policy cases_insert on public.cases for insert to authenticated with check(public.is_active() and (public.is_admin() or (created_by=auth.uid() and calculator_id=auth.uid() and typist_id is null and status='Parado')));
create policy cases_update on public.cases for update to authenticated using(public.is_active() and (public.is_admin() or calculator_id=auth.uid() or typist_id=auth.uid())) with check(public.is_active() and (public.is_admin() or calculator_id=auth.uid() or typist_id=auth.uid()));
create policy events_read on public.case_events for select to authenticated using(public.is_active() and exists(select 1 from public.cases c where c.id=case_id));
-- No direct client write permissions for profiles or audit events.
revoke insert,update,delete on public.profiles from authenticated;
revoke insert,update,delete on public.case_events from authenticated;
