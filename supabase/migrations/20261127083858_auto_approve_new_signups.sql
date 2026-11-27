-- ============================================================================
-- auto_approve_new_signups
--   The portal no longer has an admin approval step: a first Google sign-in
--   gets a usable account immediately. The admin address is still promoted to
--   the admin role, and guard_profile_update still stops a browser session
--   from editing its own role or status.
--   Only the status value in the INSERT changed; role handling is as before.
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
    'approved'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

-- any account left waiting from the old flow becomes usable too;
-- deliberately rejected or disabled accounts are untouched
update public.profiles set status = 'approved' where status = 'pending';