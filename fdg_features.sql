-- FDG MIS FEATURES: documents, roles, facilities, notifications
create table if not exists public.roles (
 id uuid primary key default gen_random_uuid(),
 name text not null unique,
 description text,
 active boolean not null default true,
 created_at timestamptz not null default now()
);

insert into public.roles(name,description) values
('Chairman','Full system administration'),('Treasurer','Finance and loan administration'),('Secretary','Records and communication'),('Member','Member access')
on conflict(name) do nothing;

create table if not exists public.role_history (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null,
 old_role text,
 new_role text not null,
 changed_by uuid,
 reason text,
 changed_at timestamptz not null default now()
);

create table if not exists public.facilities (
 id uuid primary key default gen_random_uuid(),
 facility_name text not null unique,
 description text,
 facility_code text not null unique,
 icon text default '📦',
 display_order integer default 0,
 status text not null default 'Active',
 applicable_roles text[] not null default array['Member','Treasurer','Secretary','Chairman'],
 allow_member_access boolean not null default true,
 allow_contributions boolean not null default true,
 allow_statements boolean not null default true,
 allow_downloads boolean not null default true,
 table_name text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create table if not exists public.documents (
 id uuid primary key default gen_random_uuid(),
 title text not null,
 category text default 'General',
 description text,
 storage_path text not null unique,
 original_name text,
 mime_type text,
 file_size bigint,
 access_mode text not null default 'everyone' check(access_mode in ('everyone','roles','members','chairman')),
 allowed_roles text[] not null default '{}',
 uploaded_by uuid,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create table if not exists public.document_access (
 id uuid primary key default gen_random_uuid(),
 document_id uuid not null references public.documents(id) on delete cascade,
 member_id uuid not null,
 can_view boolean not null default true,
 can_download boolean not null default true,
 created_at timestamptz not null default now(),
 unique(document_id,member_id)
);

create table if not exists public.notification_rules (
 id uuid primary key default gen_random_uuid(),
 name text not null unique,
 event_type text not null,
 schedule_cron text,
 channels text[] not null default array['email'],
 active boolean not null default true,
 subject text,
 message_template text,
 target_roles text[] default '{}',
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create table if not exists public.notification_queue (
 id uuid primary key default gen_random_uuid(),
 user_id uuid,
 event_type text not null,
 subject text not null,
 message text not null,
 channels text[] not null default array['email'],
 status text not null default 'pending' check(status in ('pending','processing','sent','failed')),
 attempts integer not null default 0,
 last_error text,
 scheduled_for timestamptz not null default now(),
 sent_at timestamptz,
 created_at timestamptz not null default now()
);

create table if not exists public.announcements (
 id uuid primary key default gen_random_uuid(),
 title text not null,
 message text not null,
 active boolean not null default true,
 publish_at timestamptz not null default now(),
 expires_at timestamptz,
 created_by uuid,
 created_at timestamptz not null default now()
);

create table if not exists public.group_settings (
 id integer primary key default 1 check(id=1),
 group_name text not null default 'FAMILY DEVELOPMENT GROUP',
 logo_url text,
 updated_at timestamptz not null default now()
);
insert into public.group_settings(id) values(1) on conflict(id) do nothing;

insert into public.notification_rules(name,event_type,schedule_cron,channels,subject,message_template,target_roles) values
('Monday Meeting','meeting','0 21 * * 1',array['email','sms','whatsapp'],'FDG Monday Meeting','Reminder: FDG meeting is today at 9:00 PM.','{}'),
('Wednesday Shares','shares','0 18 * * 3',array['email','sms','whatsapp'],'FDG Share Contribution','Reminder: Wednesday is share contribution day.','{Member}'),
('Sunday Contributions','monthly_contribution','0 18 * * 0',array['email','sms','whatsapp'],'FDG Monthly Contribution','Reminder: Please make your monthly contribution.','{Member}')
on conflict(name) do nothing;

alter table public.roles enable row level security;
alter table public.role_history enable row level security;
alter table public.facilities enable row level security;
alter table public.documents enable row level security;
alter table public.document_access enable row level security;
alter table public.notification_rules enable row level security;
alter table public.notification_queue enable row level security;
alter table public.announcements enable row level security;
alter table public.group_settings enable row level security;

do $$ begin
 if not exists(select 1 from pg_policies where tablename='roles' and policyname='roles_read') then
  create policy roles_read on public.roles for select to authenticated using(true);
 end if;
 if not exists(select 1 from pg_policies where tablename='role_history' and policyname='role_history_admin') then
  create policy role_history_admin on public.role_history for select to authenticated using(lower(coalesce((select u.role from public.users u where u.id=(select auth.uid())) ,'')) in ('chairman','admin','administrator'));
 end if;
 if not exists(select 1 from pg_policies where tablename='facilities' and policyname='facilities_read') then
  create policy facilities_read on public.facilities for select to authenticated using(status='Active' or lower(coalesce((select u.role from public.users u where u.id=(select auth.uid())) ,'')) in ('chairman','admin','administrator'));
 end if;
 if not exists(select 1 from pg_policies where tablename='documents' and policyname='documents_no_direct') then
  create policy documents_no_direct on public.documents for select to authenticated using(false);
 end if;
 if not exists(select 1 from pg_policies where tablename='document_access' and policyname='document_access_no_direct') then
  create policy document_access_no_direct on public.document_access for select to authenticated using(false);
 end if;
 if not exists(select 1 from pg_policies where tablename='notification_rules' and policyname='notification_rules_read') then
  create policy notification_rules_read on public.notification_rules for select to authenticated using(true);
 end if;
 if not exists(select 1 from pg_policies where tablename='announcements' and policyname='announcements_read') then
  create policy announcements_read on public.announcements for select to authenticated using(active=true and publish_at<=now() and (expires_at is null or expires_at>now()));
 end if;
 if not exists(select 1 from pg_policies where tablename='group_settings' and policyname='group_settings_read') then
  create policy group_settings_read on public.group_settings for select to authenticated using(true);
 end if;
end $$;

-- Private document bucket
insert into storage.buckets(id,name,public,file_size_limit)
values('fdg-documents','fdg-documents',false,52428800)
on conflict(id) do update set public=false,file_size_limit=52428800;

-- Chairman/Admin only direct Storage writes. Reads are served by the secure Edge Function.
drop policy if exists fdg_documents_upload on storage.objects;
create policy fdg_documents_upload on storage.objects for insert to authenticated
with check(bucket_id='fdg-documents' and lower(coalesce((select u.role from public.users u where u.id=(select auth.uid())) ,'')) in ('chairman','admin','administrator'));

drop policy if exists fdg_documents_update on storage.objects;
create policy fdg_documents_update on storage.objects for update to authenticated
using(bucket_id='fdg-documents' and lower(coalesce((select u.role from public.users u where u.id=(select auth.uid())) ,'')) in ('chairman','admin','administrator'))
with check(bucket_id='fdg-documents' and lower(coalesce((select u.role from public.users u where u.id=(select auth.uid())) ,'')) in ('chairman','admin','administrator'));

drop policy if exists fdg_documents_delete on storage.objects;
create policy fdg_documents_delete on storage.objects for delete to authenticated
using(bucket_id='fdg-documents' and lower(coalesce((select u.role from public.users u where u.id=(select auth.uid())) ,'')) in ('chairman','admin','administrator'));

-- Update existing role data safely when role history is written by the Edge Function.
create or replace function app_admin.set_user_role(p_actor uuid,p_user uuid,p_new_role text,p_reason text default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,app_admin as $$
declare actor_role text; old_role text;
begin
 select lower(coalesce(role,'')) into actor_role from public.users where id=p_actor and lower(coalesce(status,'active'))='active';
 if actor_role not in ('chairman','admin','administrator') then raise exception 'Only Chairman/Admin can change roles'; end if;
 select role into old_role from public.users where id=p_user;
 if old_role is null then raise exception 'User not found'; end if;
 if trim(p_new_role)='' then raise exception 'Role is required'; end if;
 update public.users set role=trim(p_new_role) where id=p_user;
 insert into public.role_history(user_id,old_role,new_role,changed_by,reason) values(p_user,old_role,trim(p_new_role),p_actor,p_reason);
 return jsonb_build_object('success',true,'user_id',p_user,'old_role',old_role,'new_role',trim(p_new_role));
end $$;
revoke all on function app_admin.set_user_role(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function app_admin.set_user_role(uuid,uuid,text,text) to service_role;

-- Admin-only facility creation. It creates a new public table with a safe UUID id.
create or replace function app_admin.create_facility(p_actor uuid,p_name text,p_description text,p_code text,p_icon text default '📦',p_order integer default 0,p_roles text[] default array['Member','Treasurer','Secretary','Chairman'],p_allow_member boolean default true,p_allow_contributions boolean default true,p_allow_statements boolean default true,p_allow_downloads boolean default true)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,app_admin as $$
declare actor_role text; t text;
begin
 select lower(coalesce(role,'')) into actor_role from public.users where id=p_actor and lower(coalesce(status,'active'))='active';
 if actor_role not in ('chairman','admin','administrator') then raise exception 'Only Chairman/Admin can create facilities'; end if;
 if trim(p_name)='' or trim(p_code)='' then raise exception 'Facility name and code are required'; end if;
 t := lower(regexp_replace(trim(p_code),'[^a-zA-Z0-9_]+','_','g'));
 if t !~ '^[a-z_][a-z0-9_]{0,50}$' then raise exception 'Invalid facility code'; end if;
 execute format('create table if not exists public.%I (id uuid primary key default gen_random_uuid(), created_at timestamptz default now())',t);
 execute format('alter table public.%I enable row level security',t);
 execute format('grant select,insert,update,delete on table public.%I to authenticated',t);
 insert into public.facilities(facility_name,description,facility_code,icon,display_order,applicable_roles,allow_member_access,allow_contributions,allow_statements,allow_downloads,table_name)
 values(trim(p_name),p_description,upper(trim(p_code)),coalesce(p_icon,'📦'),p_order,p_roles,p_allow_member,p_allow_contributions,p_allow_statements,p_allow_downloads,t);
 return jsonb_build_object('success',true,'table_name',t);
end $$;
revoke all on function app_admin.create_facility(uuid,text,text,text,text,integer,text[],boolean,boolean,boolean,boolean) from public,anon,authenticated;
grant execute on function app_admin.create_facility(uuid,text,text,text,text,integer,text[],boolean,boolean,boolean,boolean) to service_role;
