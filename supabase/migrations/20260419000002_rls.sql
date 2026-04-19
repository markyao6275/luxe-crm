-- Row Level Security policies.
-- Visibility rules:
--   admin         : sees everything
--   brand_manager : sees own brand's profiles, stores, contacts, contact_brands
--   sales_staff   : same as brand_manager (write surface is narrower in UI)

-- ---------------------------------------------------------------------------
-- Helper functions
-- Read the caller's role/brand without triggering RLS on `profiles`.
-- Marked STABLE + SECURITY DEFINER so policies can call them without recursion.
-- ---------------------------------------------------------------------------
create or replace function auth_role()
returns user_role
language sql
stable
security definer
set search_path = public
as $$
  select role from profiles where id = auth.uid()
$$;

create or replace function auth_brand_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select brand_id from profiles where id = auth.uid()
$$;

grant execute on function auth_role()     to authenticated;
grant execute on function auth_brand_id() to authenticated;

-- ---------------------------------------------------------------------------
-- Enable RLS
-- ---------------------------------------------------------------------------
alter table brands         enable row level security;
alter table stores         enable row level security;
alter table profiles       enable row level security;
alter table contacts       enable row level security;
alter table contact_brands enable row level security;

-- ---------------------------------------------------------------------------
-- brands: readable by any authenticated user; writable by admin
-- ---------------------------------------------------------------------------
create policy brands_select on brands
  for select using (auth.uid() is not null);

create policy brands_admin_write on brands
  for all
  using      (auth_role() = 'admin')
  with check (auth_role() = 'admin');

-- ---------------------------------------------------------------------------
-- stores: users see their brand's stores; admin all; admin writes
-- ---------------------------------------------------------------------------
create policy stores_select on stores
  for select using (
    auth_role() = 'admin' or brand_id = auth_brand_id()
  );

create policy stores_admin_write on stores
  for all
  using      (auth_role() = 'admin')
  with check (auth_role() = 'admin');

-- ---------------------------------------------------------------------------
-- profiles:
--   self read always; admin reads all; brand_manager reads own-brand profiles
--   writes only by admin (role/brand assignment is privileged)
-- ---------------------------------------------------------------------------
create policy profiles_self_or_scoped_select on profiles
  for select using (
    id = auth.uid()
    or auth_role() = 'admin'
    or (auth_role() = 'brand_manager' and brand_id = auth_brand_id())
  );

create policy profiles_admin_write on profiles
  for all
  using      (auth_role() = 'admin')
  with check (auth_role() = 'admin');

-- ---------------------------------------------------------------------------
-- contacts: visible if admin, or contact is linked to caller's brand
-- Direct inserts/updates are allowed; the create_or_link_contact RPC is the
-- preferred path since it enforces dedup + block-if-same-brand.
-- ---------------------------------------------------------------------------
create policy contacts_select on contacts
  for select using (
    auth_role() = 'admin'
    or exists (
      select 1 from contact_brands cb
      where cb.contact_id = contacts.id
        and cb.brand_id   = auth_brand_id()
    )
  );

create policy contacts_insert on contacts
  for insert with check (auth.uid() is not null);

create policy contacts_update on contacts
  for update
  using (
    auth_role() = 'admin'
    or exists (
      select 1 from contact_brands cb
      where cb.contact_id = contacts.id
        and cb.brand_id   = auth_brand_id()
    )
  )
  with check (
    auth_role() = 'admin'
    or exists (
      select 1 from contact_brands cb
      where cb.contact_id = contacts.id
        and cb.brand_id   = auth_brand_id()
    )
  );

create policy contacts_delete on contacts
  for delete using (auth_role() = 'admin');

-- ---------------------------------------------------------------------------
-- contact_brands: scoped strictly to caller's brand (admin bypasses)
-- ---------------------------------------------------------------------------
create policy contact_brands_select on contact_brands
  for select using (
    auth_role() = 'admin' or brand_id = auth_brand_id()
  );

create policy contact_brands_insert on contact_brands
  for insert with check (
    auth_role() = 'admin' or brand_id = auth_brand_id()
  );

create policy contact_brands_update on contact_brands
  for update
  using      (auth_role() = 'admin' or brand_id = auth_brand_id())
  with check (auth_role() = 'admin' or brand_id = auth_brand_id());

create policy contact_brands_delete on contact_brands
  for delete using (
    auth_role() = 'admin' or brand_id = auth_brand_id()
  );
