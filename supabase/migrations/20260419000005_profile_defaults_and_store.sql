-- Relax profile provisioning and associate sales staff with a store.
--
-- Rationale:
--   The previous profiles_role_brand_ck required non-admins to have a brand_id,
--   which forced admins to always include metadata when creating users. We now
--   allow a non-admin profile to exist with brand_id = null (a "pending
--   assignment" state). RLS naturally prevents such a user from seeing any
--   contacts until an admin assigns their brand.
--
-- Schema changes:
--   1. Drop the old check constraint
--   2. Add a soft guardrail: admin must have neither brand_id nor store_id
--   3. Add profiles.store_id (optional FK to stores)
--   4. Trigger defaults role to 'sales_staff' when metadata is omitted

alter table profiles drop constraint profiles_role_brand_ck;

alter table profiles
  add column store_id uuid references stores(id) on delete set null;
create index profiles_store_id_idx on profiles (store_id);

alter table profiles add constraint profiles_admin_scope_ck check (
  role <> 'admin' or (brand_id is null and store_id is null)
);

-- Refresh the trigger: metadata is now fully optional; role defaults to
-- sales_staff, and brand_id/store_id default to null.
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
  v_store_raw  text  := v_meta->>'store_id';
  v_role       user_role := 'sales_staff';
  v_brand_id   uuid;
  v_store_id   uuid;
  v_first_name text  := v_meta->>'first_name';
  v_last_name  text  := v_meta->>'last_name';
begin
  if v_role_raw is not null and v_role_raw <> '' then
    begin
      v_role := v_role_raw::user_role;
    exception when invalid_text_representation then
      raise exception
        'invalid role "%": expected admin | brand_manager | sales_staff', v_role_raw;
    end;
  end if;

  if v_brand_raw is not null and v_brand_raw <> '' then
    begin
      v_brand_id := v_brand_raw::uuid;
    exception when invalid_text_representation then
      raise exception 'invalid brand_id "%": expected uuid', v_brand_raw;
    end;
  end if;

  if v_store_raw is not null and v_store_raw <> '' then
    begin
      v_store_id := v_store_raw::uuid;
    exception when invalid_text_representation then
      raise exception 'invalid store_id "%": expected uuid', v_store_raw;
    end;
  end if;

  insert into profiles (id, role, brand_id, store_id, first_name, last_name)
  values (new.id, v_role, v_brand_id, v_store_id, v_first_name, v_last_name);

  return new;
end;
$$;
