-- ============================================================================
-- training_system_feedback_v2
--   Implements the institute's training-system update WITHOUT touching the
--   MCQ assessment (training_questions, private.training_answer_keys,
--   submissions scoring columns and submit_assessment are unchanged).
--
--   What changes on public.trainings:
--     start_date, end_date   the training period (the old free-text `date`
--                            column is kept and stays in step for reports,
--                            certificates and archive views)
--     feedback_version       1 = the row was saved with the new ಭಾಗ-1/ಭಾಗ-2
--                            layout. 0 keeps the legacy fallback in the page
--                            (old feedback_sessions / feedback_questions are
--                            converted in memory, never deleted).
--     feedback_part1         jsonb array of day-wise question blocks:
--                            {id, day, date, sessionFrom, sessionTo,
--                             subject, question, lecturer, deleted}
--     feedback_part2         jsonb array of questions:
--                            {id, text, format: choice|rating|text,
--                             options: [...], deleted}
--
--   Nothing is dropped or rewritten. feedback_sessions / feedback_questions
--   keep every old response and can still be read.
-- ============================================================================

alter table public.trainings
  add column if not exists start_date       text  not null default '',
  add column if not exists end_date         text  not null default '',
  add column if not exists feedback_version integer not null default 0,
  add column if not exists feedback_part1   jsonb not null default '[]'::jsonb,
  add column if not exists feedback_part2   jsonb not null default '[]'::jsonb;

comment on column public.trainings.start_date is 'Training start date, ISO (YYYY-MM-DD) as produced by the admin date input.';
comment on column public.trainings.end_date   is 'Training end date, ISO (YYYY-MM-DD).';
comment on column public.trainings.feedback_version is '1 = saved with the ಭಾಗ-1/ಭಾಗ-2 feedback layout; 0 = legacy feedback columns only.';
comment on column public.trainings.feedback_part1   is 'ಭಾಗ-1 blocks: id, day, date, sessionFrom, sessionTo, subject, question, lecturer, deleted.';
comment on column public.trainings.feedback_part2   is 'ಭಾಗ-2 questions: id, text, format(choice|rating|text), options[], deleted.';

-- array guards, added only if they are not there yet (idempotent)
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.trainings'::regclass
      and conname = 'trainings_feedback_part1_array'
  ) then
    alter table public.trainings
      add constraint trainings_feedback_part1_array
      check (jsonb_typeof(feedback_part1) = 'array');
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.trainings'::regclass
      and conname = 'trainings_feedback_part2_array'
  ) then
    alter table public.trainings
      add constraint trainings_feedback_part2_array
      check (jsonb_typeof(feedback_part2) = 'array');
  end if;
end
$$;

-- ----------------------------------------------------------------------------
-- Backfill the two dates from the existing free-text `date`, converting
-- DD-MM-YYYY (what the old form stored) to ISO. The legacy column itself is
-- not modified, and rows whose date cannot be parsed are left untouched.
-- ----------------------------------------------------------------------------
update public.trainings
set start_date = case
      when date ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then date
      when date ~ '^[0-9]{2}-[0-9]{2}-[0-9]{4}$' then to_char(to_date(date, 'DD-MM-YYYY'), 'YYYY-MM-DD')
      else ''
    end
where start_date = '' and btrim(date) <> '';

update public.trainings
set end_date = start_date
where end_date = '' and start_date <> '';

-- ----------------------------------------------------------------------------
-- Column privileges. The initial schema grants table-level insert/update/
-- delete on public.trainings, so these are belt-and-braces for projects that
-- revoked at column level.
-- ----------------------------------------------------------------------------
grant select (start_date, end_date, feedback_version, feedback_part1, feedback_part2),
      insert (start_date, end_date, feedback_version, feedback_part1, feedback_part2),
      update (start_date, end_date, feedback_version, feedback_part1, feedback_part2)
  on public.trainings to authenticated;
