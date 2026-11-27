-- ============================================================================
-- DTI Bengaluru Training Portal - initial schema + security
-- Field names follow the portal's own data model (Ksgdhvsjh.html):
--   defaultTraining()  -> trainings / training_questions / (private) answer key
--   submission {...}   -> submissions
--   DB.certificates    -> certificates
--   defaultCertDesign()-> certificate_design
--   settings           -> portal_settings
-- ============================================================================

-- ---------------------------------------------------------------- private schema
create schema if not exists private;
revoke all on schema private from public;
revoke all on schema private from anon;
revoke all on schema private from authenticated;
comment on schema private is 'Not part of the exposed API. Answer keys + certificate counter live here.';

-- ---------------------------------------------------------------- profiles
create table public.profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  email         text not null default '',
  official_name text not null default '',
  kgid          text not null default '',
  designation   text not null default '',
  department    text not null default '',
  role          text not null default 'student' check (role in ('admin','student')),
  status        text not null default 'pending' check (status in ('pending','approved','rejected','disabled')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
comment on table public.profiles is 'One row per auth user (Google/e-mail). profile.id = auth.users.id. status gates portal access.';

-- ---------------------------------------------------------------- trainings
create table public.trainings (
  id                  text primary key,
  title               text not null,
  topic               text not null default '',
  date                text not null default '',
  description         text not null default '',
  category            text not null default '',
  accent              text not null default '#1D3557',
  institute           text not null default 'ಜಿಲ್ಲಾ ತರಬೇತಿ ಸಂಸ್ಥೆ, ಬೆಂಗಳೂರು ನಗರ',
  passing             integer not null default 70 check (passing between 1 and 100),
  published           boolean not null default false,
  archived            boolean not null default false,
  feedback_day        text not null default '',
  feedback_sessions   jsonb not null default '[]'::jsonb,
  feedback_questions  jsonb not null default '[]'::jsonb,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  created_by          uuid references auth.users(id),
  constraint trainings_feedback_sessions_array  check (jsonb_typeof(feedback_sessions) = 'array'),
  constraint trainings_feedback_questions_array check (jsonb_typeof(feedback_questions) = 'array')
);

create table public.training_questions (
  training_id text not null references public.trainings(id) on delete cascade,
  id          text not null,
  position    integer not null,
  text        text not null,
  options     jsonb not null default '[]'::jsonb,
  marks       integer not null default 1 check (marks > 0),
  primary key (training_id, id),
  unique (training_id, position),
  constraint training_questions_options_array check (jsonb_typeof(options) = 'array')
);

-- ---------------------------------------------------------------- answer keys (private)
create table private.training_answer_keys (
  training_id text primary key references public.trainings(id) on delete cascade,
  answer_key  jsonb not null default '{}'::jsonb,
  updated_at  timestamptz not null default now(),
  updated_by  uuid,
  constraint training_answer_keys_object check (jsonb_typeof(answer_key) = 'object')
);
comment on table private.training_answer_keys is 'Correct option index per question. Never granted to anon/authenticated; read only inside SECURITY DEFINER functions.';

-- ---------------------------------------------------------------- submissions
create table public.submissions (
  id              uuid primary key default gen_random_uuid(),
  student_id      uuid not null references auth.users(id) on delete cascade,
  training_id     text not null references public.trainings(id),
  official_name   text not null default '',
  kgid            text not null default '',
  email           text not null default '',
  designation     text not null default '',
  answers         jsonb not null default '{}'::jsonb,
  feedback        jsonb not null default '{"ratings":{},"answers":{}}'::jsonb,
  correct_count   integer not null default 0 check (correct_count >= 0),
  wrong_count     integer not null default 0 check (wrong_count >= 0),
  total_marks     integer not null default 0 check (total_marks >= 0),
  marks_obtained  integer not null default 0 check (marks_obtained >= 0),
  percentage      integer not null default 0 check (percentage between 0 and 100),
  passing_percent integer not null default 70 check (passing_percent between 1 and 100),
  pass_status     boolean not null default false,
  certificate_serial text,
  submitted_at    timestamptz not null default now(),
  scored_at       timestamptz,
  unique (student_id, training_id),
  constraint submissions_marks_within_total check (marks_obtained <= total_marks),
  constraint submissions_attempt_once check (true)
);
comment on table public.submissions is 'One attempt per student per training. Every score column is written only by public.submit_assessment().';

-- ---------------------------------------------------------------- certificates
create table public.certificates (
  id             uuid primary key default gen_random_uuid(),
  serial         text not null unique,
  submission_id  uuid not null unique references public.submissions(id) on delete cascade,
  student_id     uuid not null references auth.users(id) on delete cascade,
  student_name   text not null default '',
  kgid           text not null default '',
  training_id    text not null references public.trainings(id),
  training_title text not null default '',
  training_topic text not null default '',
  training_date  text not null default '',
  marks          integer not null default 0,
  total          integer not null default 0,
  percentage     integer not null default 0,
  issued_at      timestamptz not null default now(),
  constraint certificates_serial_format check (serial ~ '^DTI-BNG-[0-9]{4}-[0-9]{4,}$'),
  constraint certificates_serial_permanent check (serial <> '')
);
comment on table public.certificates is 'Permanent register. serial is unique by constraint and minted only by the database.';
create index certificates_student_idx on public.certificates(student_id);

-- ---------------------------------------------------------------- settings + design (singletons)
create table public.portal_settings (
  id              boolean primary key default true check (id),
  default_passing integer not null default 70 check (default_passing between 1 and 100),
  updated_at      timestamptz not null default now()
);
insert into public.portal_settings (id) values (true) on conflict (id) do nothing;

create table public.certificate_design (
  id              boolean primary key default true check (id),
  use_custom      boolean not null default false,
  aspect          numeric(6,3) not null default 1.414 check (aspect > 0),
  background_path text not null default '',
  fields          jsonb not null default '[]'::jsonb,
  updated_at      timestamptz not null default now(),
  updated_by      uuid references auth.users(id),
  constraint certificate_design_fields_array check (jsonb_typeof(fields) = 'array')
);
insert into public.certificate_design (id) values (true) on conflict (id) do nothing;
comment on column public.certificate_design.background_path is 'Object path inside the private certificate-assets storage bucket.';
comment on column public.certificate_design.fields is 'Editor fields: id, type(auto|static), key, text, x, y, w, fontSize, fontFamily, color, align, bold.';

-- ============================================================================
-- helper functions (fixed search_path, definer where they must read profiles)
-- ============================================================================
create or replace function public.is_admin()
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid())
      and p.role = 'admin'
      and p.status = 'approved'
  );
$$;

create or replace function public.is_approved()
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid())
      and p.status = 'approved'
  );
$$;

create or replace function public.can_read_training(p_training_id text)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.trainings t
    where t.id = p_training_id
      and (public.is_admin() or (t.published and not t.archived and public.is_approved()))
  );
$$;

create or replace function public.set_updated_at()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- ============================================================================
-- auth -> profile provisioning + profile guards
-- ============================================================================
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_admin_email constant text := 'savithakh80@gmail.com';
  v_email text := lower(coalesce(new.email, ''));
  v_name  text := coalesce(
    nullif(new.raw_user_meta_data ->> 'full_name', ''),
    nullif(new.raw_user_meta_data ->> 'name', ''),
    ''
  );
begin
  insert into public.profiles (id, email, official_name, role, status)
  values (
    new.id,
    coalesce(new.email, ''),
    v_name,
    case when v_email = v_admin_email then 'admin' else 'student' end,
    case when v_email = v_admin_email then 'approved' else 'pending' end
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

create or replace function public.guard_profile_update()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  -- service_role / dashboard / migrations may fix anything
  if coalesce((select auth.role()), '') <> 'authenticated' then
    return new;
  end if;
  if public.is_admin() then
    return new;
  end if;
  if new.id          is distinct from old.id          then raise exception 'profile id is read-only'      using errcode = '42501'; end if;
  if new.role        is distinct from old.role        then raise exception 'role cannot be changed'       using errcode = '42501'; end if;
  if new.status      is distinct from old.status      then raise exception 'status cannot be changed'     using errcode = '42501'; end if;
  if new.email       is distinct from old.email       then raise exception 'email cannot be changed'      using errcode = '42501'; end if;
  if new.created_at  is distinct from old.created_at  then raise exception 'created_at is read-only'      using errcode = '42501'; end if;
  return new;
end;
$$;

create trigger profiles_guard_update
before update on public.profiles
for each row execute function public.guard_profile_update();

create trigger profiles_touch_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

create trigger trainings_touch_updated_at
before update on public.trainings
for each row execute function public.set_updated_at();

create trigger portal_settings_touch_updated_at
before update on public.portal_settings
for each row execute function public.set_updated_at();

create trigger certificate_design_touch_updated_at
before update on public.certificate_design
for each row execute function public.set_updated_at();

-- ============================================================================
-- certificate serials (private counter, database-minted)
-- ============================================================================
create sequence if not exists private.certificate_serial_seq start with 1;
revoke all on sequence private.certificate_serial_seq from public, anon, authenticated;

create or replace function private.next_certificate_serial()
returns text
language sql volatile security definer set search_path = ''
as $$
  select 'DTI-BNG-' || to_char(now(), 'YYYY') || '-' ||
         lpad(nextval('private.certificate_serial_seq')::text, 4, '0');
$$;

-- ============================================================================
-- server-side scoring (the only writer of scores + certificates)
-- ============================================================================
create or replace function public.submit_assessment(
  p_training_id   text,
  p_answers       jsonb,
  p_feedback      jsonb default '{"ratings":{},"answers":{}}'::jsonb,
  p_official_name text default '',
  p_kgid          text default '',
  p_email         text default ''
)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid          uuid := (select auth.uid());
  v_profile      public.profiles%rowtype;
  v_training     public.trainings%rowtype;
  v_key          jsonb;
  v_q            record;
  v_given        integer;
  v_expected     integer;
  v_questions    integer := 0;
  v_correct      integer := 0;
  v_total_marks  integer := 0;
  v_earned       integer := 0;
  v_pct          integer := 0;
  v_passed       boolean := false;
  v_submission   uuid;
  v_name         text;
  v_serial       text := null;
begin
  if v_uid is null then
    raise exception 'not-authenticated' using errcode = '28000';
  end if;

  select * into v_profile from public.profiles where id = v_uid;
  if not found then
    raise exception 'no-profile' using errcode = '42501';
  end if;
  if v_profile.status <> 'approved' then
    raise exception 'not-approved' using errcode = '42501';
  end if;

  select * into v_training from public.trainings where id = p_training_id;
  if not found then
    raise exception 'training-not-found' using errcode = '23503';
  end if;
  if not v_training.published or v_training.archived then
    raise exception 'training-not-open' using errcode = '42501';
  end if;

  if exists (select 1 from public.submissions s
             where s.student_id = v_uid and s.training_id = p_training_id) then
    raise exception 'already-submitted' using errcode = '23505';
  end if;

  select k.answer_key into v_key
  from private.training_answer_keys k
  where k.training_id = p_training_id;
  if v_key is null then
    raise exception 'answer-key-missing' using errcode = '55000';
  end if;

  for v_q in
    select q.id, q.marks
    from public.training_questions q
    where q.training_id = p_training_id
    order by q.position
  loop
    v_questions   := v_questions + 1;
    v_total_marks := v_total_marks + v_q.marks;

    begin
      v_given := nullif(btrim(coalesce(p_answers ->> v_q.id, '')), '')::integer;
    exception when others then
      v_given := null;
    end;

    begin
      v_expected := nullif(btrim(coalesce(v_key ->> v_q.id, '')), '')::integer;
    exception when others then
      v_expected := null;
    end;

    if v_given is not null and v_expected is not null and v_given = v_expected then
      v_correct := v_correct + 1;
      v_earned  := v_earned + v_q.marks;
    end if;
  end loop;

  if v_total_marks > 0 then
    v_pct := round(v_earned::numeric * 100 / v_total_marks)::integer;
  end if;
  v_passed := v_pct >= v_training.passing;
  v_name   := coalesce(nullif(btrim(p_official_name), ''), nullif(v_profile.official_name, ''), v_profile.email);

  insert into public.submissions (
    student_id, training_id, official_name, kgid, email, designation,
    answers, feedback, correct_count, wrong_count, total_marks, marks_obtained,
    percentage, passing_percent, pass_status, submitted_at, scored_at
  ) values (
    v_uid, p_training_id, v_name,
    coalesce(nullif(btrim(p_kgid), ''), v_profile.kgid),
    coalesce(nullif(btrim(p_email), ''), v_profile.email),
    v_profile.designation,
    coalesce(p_answers, '{}'::jsonb),
    coalesce(p_feedback, '{"ratings":{},"answers":{}}'::jsonb),
    v_correct, v_questions - v_correct, v_total_marks, v_earned,
    v_pct, v_training.passing, v_passed, now(), now()
  ) returning id into v_submission;

  if v_passed then
    v_serial := private.next_certificate_serial();
    insert into public.certificates (
      serial, submission_id, student_id, student_name, kgid,
      training_id, training_title, training_topic, training_date,
      marks, total, percentage
    ) values (
      v_serial, v_submission, v_uid, v_name,
      coalesce(nullif(btrim(p_kgid), ''), v_profile.kgid),
      v_training.id, v_training.title, v_training.topic, v_training.date,
      v_earned, v_total_marks, v_pct
    );
    update public.submissions set certificate_serial = v_serial where id = v_submission;
  end if;

  return jsonb_build_object(
    'submission_id', v_submission,
    'correct', v_correct,
    'wrong', v_questions - v_correct,
    'total_questions', v_questions,
    'total_marks', v_total_marks,
    'marks', v_earned,
    'percentage', v_pct,
    'passed', v_passed,
    'passing', v_training.passing,
    'certificate_serial', v_serial
  );
end;
$$;

-- ============================================================================
-- admin-only RPCs (the two things RLS alone cannot do)
-- ============================================================================
create or replace function public.admin_set_profile_status(p_profile_id uuid, p_status text)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_admin() then
    raise exception 'not-admin' using errcode = '42501';
  end if;
  if p_status not in ('pending','approved','rejected','disabled') then
    raise exception 'invalid-status' using errcode = '22023';
  end if;
  update public.profiles
     set status = p_status
   where id = p_profile_id and role <> 'admin';
  if not found then
    raise exception 'profile-not-found' using errcode = '23503';
  end if;
end;
$$;

create or replace function public.admin_save_answer_key(p_training_id text, p_answer_key jsonb)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_bad text;
begin
  if not public.is_admin() then
    raise exception 'not-admin' using errcode = '42501';
  end if;
  if p_answer_key is null or jsonb_typeof(p_answer_key) <> 'object' then
    raise exception 'answer key must be a JSON object' using errcode = '22023';
  end if;
  if not exists (select 1 from public.trainings t where t.id = p_training_id) then
    raise exception 'training-not-found' using errcode = '23503';
  end if;

  select e.key into v_bad
  from jsonb_each_text(p_answer_key) as e(key, value)
  where e.value !~ '^[0-9]+$'
     or not exists (
       select 1 from public.training_questions q
       where q.training_id = p_training_id and q.id = e.key
     )
  limit 1;
  if v_bad is not null then
    raise exception 'answer key has an unknown question or non-numeric option: %', v_bad using errcode = '22023';
  end if;

  insert into private.training_answer_keys (training_id, answer_key, updated_at, updated_by)
  values (p_training_id, p_answer_key, now(), (select auth.uid()))
  on conflict (training_id) do update
    set answer_key = excluded.answer_key,
        updated_at = now(),
        updated_by = excluded.updated_by;
end;
$$;

-- ============================================================================
-- privileges
-- ============================================================================
revoke all on public.profiles, public.trainings, public.training_questions,
              public.submissions, public.certificates,
              public.portal_settings, public.certificate_design
  from anon, authenticated;

grant select on public.profiles, public.trainings, public.training_questions,
                public.submissions, public.certificates,
                public.portal_settings, public.certificate_design
  to authenticated;

-- students may only ever write these four profile columns
revoke update on public.profiles from authenticated;
grant update (official_name, kgid, designation, department) on public.profiles to authenticated;

-- admin writes are allowed by privilege but gated by RLS (is_admin())
grant insert, update, delete on public.trainings           to authenticated;
grant insert, update, delete on public.training_questions  to authenticated;
grant update                 on public.portal_settings     to authenticated;
grant insert, update, delete on public.certificate_design  to authenticated;

revoke all on function public.is_admin()                from public, anon;
revoke all on function public.is_approved()             from public, anon;
revoke all on function public.can_read_training(text)   from public, anon;
revoke all on function public.submit_assessment(text, jsonb, jsonb, text, text, text) from public, anon;
revoke all on function public.admin_set_profile_status(uuid, text) from public, anon;
revoke all on function public.admin_save_answer_key(text, jsonb)   from public, anon;
revoke all on function public.handle_new_user()        from public, anon, authenticated;
revoke all on function public.guard_profile_update()   from public, anon, authenticated;
revoke all on function public.set_updated_at()         from public, anon, authenticated;
revoke all on function private.next_certificate_serial() from public, anon, authenticated;

grant execute on function public.is_admin()              to authenticated;
grant execute on function public.is_approved()           to authenticated;
grant execute on function public.can_read_training(text) to authenticated;
grant execute on function public.submit_assessment(text, jsonb, jsonb, text, text, text) to authenticated;
grant execute on function public.admin_set_profile_status(uuid, text) to authenticated;
grant execute on function public.admin_save_answer_key(text, jsonb)   to authenticated;

-- ============================================================================
-- RLS
-- ============================================================================
alter table public.profiles             enable row level security;
alter table public.trainings            enable row level security;
alter table public.training_questions   enable row level security;
alter table public.submissions          enable row level security;
alter table public.certificates         enable row level security;
alter table public.portal_settings      enable row level security;
alter table public.certificate_design   enable row level security;

-- profiles: own row, or the admin
create policy profiles_select_own_or_admin on public.profiles
  for select to authenticated
  using (id = (select auth.uid()) or public.is_admin());

create policy profiles_update_own on public.profiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

create policy profiles_admin_update on public.profiles
  for update to authenticated
  using (public.is_admin())
  with check (public.is_admin());

create policy profiles_admin_delete on public.profiles
  for delete to authenticated
  using (public.is_admin());

-- trainings: students see published + not archived, admin sees everything
create policy trainings_select on public.trainings
  for select to authenticated
  using (public.is_admin() or (published and not archived and public.is_approved()));

create policy trainings_admin_insert on public.trainings
  for insert to authenticated
  with check (public.is_admin());

create policy trainings_admin_update on public.trainings
  for update to authenticated
  using (public.is_admin())
  with check (public.is_admin());

create policy trainings_admin_delete on public.trainings
  for delete to authenticated
  using (public.is_admin());

-- questions follow their training
create policy training_questions_select on public.training_questions
  for select to authenticated
  using (public.can_read_training(training_id));

create policy training_questions_admin_insert on public.training_questions
  for insert to authenticated
  with check (public.is_admin());

create policy training_questions_admin_update on public.training_questions
  for update to authenticated
  using (public.is_admin())
  with check (public.is_admin());

create policy training_questions_admin_delete on public.training_questions
  for delete to authenticated
  using (public.is_admin());

-- submissions: read only (own, or admin). No insert/update/delete policy at all.
create policy submissions_select_own_or_admin on public.submissions
  for select to authenticated
  using (student_id = (select auth.uid()) or public.is_admin());

-- certificates: read only (own, or admin)
create policy certificates_select_own_or_admin on public.certificates
  for select to authenticated
  using (student_id = (select auth.uid()) or public.is_admin());

-- settings + design: readable by approved users, writable by admin
create policy portal_settings_select on public.portal_settings
  for select to authenticated
  using (public.is_approved() or public.is_admin());

create policy portal_settings_admin_update on public.portal_settings
  for update to authenticated
  using (public.is_admin())
  with check (public.is_admin());

create policy certificate_design_select on public.certificate_design
  for select to authenticated
  using (public.is_approved() or public.is_admin());

create policy certificate_design_admin_insert on public.certificate_design
  for insert to authenticated
  with check (public.is_admin());

create policy certificate_design_admin_update on public.certificate_design
  for update to authenticated
  using (public.is_admin())
  with check (public.is_admin());

create policy certificate_design_admin_delete on public.certificate_design
  for delete to authenticated
  using (public.is_admin());

-- ============================================================================
-- storage: private bucket for the certificate background image
-- ============================================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('certificate-assets', 'certificate-assets', false, 5242880, array['image/png','image/jpeg'])
on conflict (id) do nothing;

create policy certificate_assets_read on storage.objects
  for select to authenticated
  using (bucket_id = 'certificate-assets' and (public.is_approved() or public.is_admin()));

create policy certificate_assets_admin_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'certificate-assets' and public.is_admin());

create policy certificate_assets_admin_update on storage.objects
  for update to authenticated
  using (bucket_id = 'certificate-assets' and public.is_admin())
  with check (bucket_id = 'certificate-assets' and public.is_admin());

create policy certificate_assets_admin_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'certificate-assets' and public.is_admin());