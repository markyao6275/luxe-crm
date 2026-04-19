-- Core schema: brands, stores, profiles, contacts, contact_brands.
-- Run with `supabase db reset` (local) or `supabase db push` (linked project).

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
create type user_role as enum ('admin', 'brand_manager', 'sales_staff');
create type gender   as enum ('male', 'female', 'other', 'prefer_not_to_say');

-- ---------------------------------------------------------------------------
-- brands
-- ---------------------------------------------------------------------------
create table brands (
  id         uuid primary key default gen_random_uuid(),
  name       text not null unique,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- stores  (each store belongs to a brand)
-- ---------------------------------------------------------------------------
create table stores (
  id         uuid primary key default gen_random_uuid(),
  brand_id   uuid not null references brands(id) on delete restrict,
  name       text not null,
  address    text,
  created_at timestamptz not null default now(),
  unique (brand_id, name)
);
create index stores_brand_id_idx on stores (brand_id);

-- ---------------------------------------------------------------------------
-- profiles  (1:1 with auth.users; admin has no brand, others must)
-- ---------------------------------------------------------------------------
create table profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  role       user_role not null,
  brand_id   uuid references brands(id) on delete restrict,
  first_name text,
  last_name  text,
  created_at timestamptz not null default now(),
  constraint profiles_role_brand_ck check (
    (role = 'admin'      and brand_id is null)
    or (role <> 'admin'  and brand_id is not null)
  )
);
create index profiles_brand_id_idx on profiles (brand_id);

-- ---------------------------------------------------------------------------
-- contacts  (phone OR email required; deduped by phone first, email second)
-- ---------------------------------------------------------------------------
create table contacts (
  id         uuid primary key default gen_random_uuid(),
  first_name text not null,
  last_name  text not null,
  dob        date,
  gender     gender,
  phone      text,
  email      text,
  city       text,
  created_at timestamptz not null default now(),
  constraint contacts_phone_or_email_ck check (phone is not null or email is not null)
);

-- Dedup: partial unique indexes (emails are compared case-insensitively).
-- Phone is expected to be stored in E.164 by the application layer.
create unique index contacts_phone_uq on contacts (phone)        where phone is not null;
create unique index contacts_email_uq on contacts (lower(email)) where email is not null;

-- ---------------------------------------------------------------------------
-- contact_brands  (junction carrying brand-scoped data: creator, store, notes)
-- ---------------------------------------------------------------------------
create table contact_brands (
  contact_id uuid not null references contacts(id) on delete cascade,
  brand_id   uuid not null references brands(id)   on delete restrict,
  store_id   uuid references stores(id)            on delete set null,
  created_by uuid references profiles(id)          on delete set null,
  notes      text,
  created_at timestamptz not null default now(),
  primary key (contact_id, brand_id)
);
create index contact_brands_brand_id_idx on contact_brands (brand_id);
create index contact_brands_store_id_idx on contact_brands (store_id);

-- A store_id, when provided, must belong to the same brand as the row.
create or replace function contact_brands_validate_store()
returns trigger
language plpgsql
as $$
begin
  if new.store_id is not null then
    perform 1 from stores where id = new.store_id and brand_id = new.brand_id;
    if not found then
      raise exception 'store_id % does not belong to brand_id %', new.store_id, new.brand_id;
    end if;
  end if;
  return new;
end;
$$;

create trigger contact_brands_validate_store_trg
before insert or update on contact_brands
for each row execute function contact_brands_validate_store();
