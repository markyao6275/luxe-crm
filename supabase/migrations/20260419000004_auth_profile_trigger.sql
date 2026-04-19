-- Auto-provision a profile row whenever a new auth.users row is created.
--
-- Role + brand are read from auth.users.raw_user_meta_data. Admins supply this
-- when creating users via Supabase Studio ("Add user" → User Metadata field)
-- or the Auth admin API.
--
-- Expected shape (role is required; brand_id is required for non-admins):
--
--   { "role": "brand_manager",
--     "brand_id": "<uuid>",
--     "first_name": "Ava",
--     "last_name":  "Lee" }
--
-- For an admin, omit brand_id:
--
--   { "role": "admin",
--     "first_name": "Ops",
--     "last_name":  "Admin" }
--
-- Missing/invalid metadata or violating the role/brand check constraint
-- raises, which aborts the user creation — the admin sees the error and can
-- retry with correct metadata.

create or replace function handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_meta       jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  v_role_raw   text  := v_meta->>'role';
  v_brand_raw  text  := v_meta->>'brand_id';
  v_role       user_role;
  v_brand_id   uuid;
  v_first_name text  := v_meta->>'first_name';
  v_last_name  text  := v_meta->>'last_name';
begin
  if v_role_raw is null or v_role_raw = '' then
    raise exception
      'user metadata must include "role" (admin | brand_manager | sales_staff)';
  end if;

  begin
    v_role := v_role_raw::user_role;
  exception when invalid_text_representation then
    raise exception
      'invalid role "%": expected admin | brand_manager | sales_staff', v_role_raw;
  end;

  if v_brand_raw is not null and v_brand_raw <> '' then
    begin
      v_brand_id := v_brand_raw::uuid;
    exception when invalid_text_representation then
      raise exception 'invalid brand_id "%": expected uuid', v_brand_raw;
    end;
  end if;

  -- The profiles_role_brand_ck constraint enforces admin<->brand consistency:
  --   admin must have null brand_id; non-admins must have one.
  insert into profiles (id, role, brand_id, first_name, last_name)
  values (new.id, v_role, v_brand_id, v_first_name, v_last_name);

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_auth_user();
