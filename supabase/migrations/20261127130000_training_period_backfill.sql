-- ============================================================================
-- training_period_backfill
--   The v2 migration filled start_date / end_date only when the legacy
--   free-text `date` column held a single date. Rows whose `date` holds the
--   whole period ("23-11-2026 – 25-11-2026") were left with empty columns, so
--   the printed certificate repeated the period in both the Start and the End
--   box.
--
--   The page now splits such a value in memory, so certificates, results and
--   registers are already correct. This migration repairs the stored columns
--   as well, so an export or a report sees the same two dates.
--
--   Only empty start_date / end_date values are filled. The legacy `date`
--   column, every question, response, submission and certificate are
--   untouched, and running it twice changes nothing.
-- ============================================================================

do $$
declare
  r  record;
  m  text[];
  d1 date;
  d2 date;
begin
  for r in
    select id, date from public.trainings
    where (start_date = '' or end_date = '')
      and coalesce(date, '') ~ '[0-9]'
  loop
    d1 := null;
    d2 := null;
    begin
      -- DD-MM-YYYY (or DD/MM/YYYY) range: what the old form stored
      m := regexp_match(r.date, '(\d{1,2}[-/.]\d{1,2}[-/.]\d{4})[^0-9]*(\d{1,2}[-/.]\d{1,2}[-/.]\d{4})');
      if m is not null then
        d1 := to_date(m[1], 'DD-MM-YYYY');
        d2 := to_date(m[2], 'DD-MM-YYYY');
      else
        -- an ISO range, in case one was typed into the old field
        m := regexp_match(r.date, '(\d{4}-\d{1,2}-\d{1,2})[^0-9]*(\d{4}-\d{1,2}-\d{1,2})');
        if m is not null then
          d1 := m[1]::date;
          d2 := m[2]::date;
        end if;
      end if;

      if d1 is not null and d2 is not null then
        update public.trainings
        set start_date = case when start_date = '' then to_char(d1, 'YYYY-MM-DD') else start_date end,
            end_date   = case when end_date   = '' then to_char(d2, 'YYYY-MM-DD') else end_date   end
        where id = r.id;
      end if;

    exception when others then
      -- one unreadable legacy string must never stop the migration
      raise notice 'training_period_backfill: skipped % (%)', r.id, sqlerrm;
    end;
  end loop;
end
$$;
