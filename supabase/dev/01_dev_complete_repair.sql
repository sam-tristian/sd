-- =============================================================================
-- 01_dev_complete_repair.sql  -  TEST PROJECT ONLY. NEVER add this to migrations/.
-- =============================================================================
-- Powers the "Complete now" button of the Team 4 test harness.
--
-- Why it exists: the real flow is  customer books -> Team 3's admin moves the
-- status -> completed  and a customer is NOT allowed to complete a repair
-- (Team 2's guard trigger blocks it). To test reviews alone we need a shortcut.
--
-- What it does: for the SIGNED-IN customer's OWN active repair only, it drops the
-- session claims for this one statement (so the guard sees "shop/SQL editor"),
-- sets status = completed and, if the repair has no technician, assigns the first
-- technician so the Technician Performance report has data.
-- =============================================================================
create or replace function public.dev_complete_my_repair(p_repair_id uuid)
returns public.repairs
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid  uuid := auth.uid();
  v_row  public.repairs;
begin
  if v_uid is null then
    raise exception 'You are not signed in.' using errcode = '42501';
  end if;

  perform 1 from public.repairs
   where id = p_repair_id
     and customer_id = v_uid
     and status in ('pending', 'in_progress', 'testing');
  if not found then
    raise exception 'Only one of your own active repairs can be completed.' using errcode = '42501';
  end if;

  -- act as "no session" for this transaction only (see header comment)
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);

  update public.repairs
     set status = 'completed',
         technician_id = coalesce(technician_id, (select t.id from public.technicians t order by t.id limit 1))
   where id = p_repair_id
   returning * into v_row;

  return v_row;
end
$$;

revoke all on function public.dev_complete_my_repair(uuid) from public, anon;
grant execute on function public.dev_complete_my_repair(uuid) to authenticated;
