-- One attempt per student per training is enforced by unique (student_id, training_id);
-- this tautological placeholder added nothing, so remove it.
alter table public.submissions drop constraint if exists submissions_attempt_once;