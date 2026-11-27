-- An optional important notice the administrator writes above the
-- feedback form. Students see it before they rate the sessions.
alter table public.trainings
  add column if not exists feedback_notice text not null default '';

-- the new column needs the same column-level grants as the rest of the table
grant select (feedback_notice), insert (feedback_notice), update (feedback_notice)
  on public.trainings to authenticated;