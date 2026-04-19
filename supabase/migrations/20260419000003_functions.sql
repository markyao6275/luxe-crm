-- RPCs for dedup-aware contact creation.
--
-- The client should:
--   1) Normalize phone to E.164 and trim/lowercase email before calling.
--   2) Call `find_contact_by_phone_or_email` to drive the "already exists" UX.
--   3) Call `create_or_link_contact` to actually persist — this enforces
--      "block if contact already exists for this brand; otherwise link."

-- ---------------------------------------------------------------------------
-- normalize_email: trim + lowercase; returns null for empty
-- ---------------------------------------------------------------------------
create or replace function normalize_email(e text)
returns text
language sql
immutable
as $$
  select nullif(lower(trim(e)), '')
$$;

-- ---------------------------------------------------------------------------
-- find_contact_by_phone_or_email
-- SECURITY DEFINER so dedup lookup can see contacts across all brands,
-- but only returns the contact id + which brands it's linked to (no PII).
-- ---------------------------------------------------------------------------
create or replace function find_contact_by_phone_or_email(
  p_phone text,
  p_email text
)
returns table (
  contact_id        uuid,
  matched_on        text,
  existing_brand_ids uuid[]
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id    uuid;
  v_match text;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  if p_phone is not null then
    select id into v_id from contacts where phone = p_phone;
    if found then v_match := 'phone'; end if;
  end if;

  if v_id is null and p_email is not null then
    select id into v_id from contacts where lower(email) = lower(p_email);
    if found then v_match := 'email'; end if;
  end if;

  if v_id is null then
    return;
  end if;

  return query
    select
      v_id,
      v_match,
      coalesce(array_agg(cb.brand_id) filter (where cb.brand_id is not null), '{}'::uuid[])
    from contact_brands cb
    where cb.contact_id = v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- create_or_link_contact
-- Returns one row with flags:
--   was_created = true  : new contact inserted AND linked to brand
--   was_linked  = true  : existing contact linked to a new brand
-- Raises unique_violation if a link already exists for (contact, brand).
-- ---------------------------------------------------------------------------
create or replace function create_or_link_contact(
  p_first_name text,
  p_last_name  text,
  p_phone      text,
  p_email      text,
  p_dob        date,
  p_gender     gender,
  p_city       text,
  p_brand_id   uuid,
  p_store_id   uuid,
  p_notes      text
)
returns table (
  contact_id  uuid,
  was_created boolean,
  was_linked  boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid        uuid := auth.uid();
  v_role       user_role;
  v_user_brand uuid;
  v_contact_id uuid;
  v_email_n    text := normalize_email(p_email);
  v_exists     int;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select role, brand_id into v_role, v_user_brand from profiles where id = v_uid;
  if v_role is null then
    raise exception 'caller has no profile';
  end if;

  if v_role <> 'admin' and p_brand_id <> v_user_brand then
    raise exception 'cannot create contact for another brand';
  end if;

  if p_phone is null and v_email_n is null then
    raise exception 'phone or email required';
  end if;

  -- Dedup lookup (phone first, then email)
  if p_phone is not null then
    select id into v_contact_id from contacts where phone = p_phone;
  end if;
  if v_contact_id is null and v_email_n is not null then
    select id into v_contact_id from contacts where lower(email) = v_email_n;
  end if;

  if v_contact_id is null then
    -- Brand-new contact
    insert into contacts (first_name, last_name, dob, gender, phone, email, city)
    values (p_first_name, p_last_name, p_dob, p_gender, p_phone, v_email_n, p_city)
    returning id into v_contact_id;

    insert into contact_brands (contact_id, brand_id, store_id, created_by, notes)
    values (v_contact_id, p_brand_id, p_store_id, v_uid, p_notes);

    return query select v_contact_id, true, false;
    return;
  end if;

  -- Contact exists — block if already linked to this brand
  select count(*) into v_exists
  from contact_brands
  where contact_id = v_contact_id and brand_id = p_brand_id;

  if v_exists > 0 then
    raise exception 'contact already exists for this brand'
      using errcode = 'unique_violation';
  end if;

  insert into contact_brands (contact_id, brand_id, store_id, created_by, notes)
  values (v_contact_id, p_brand_id, p_store_id, v_uid, p_notes);

  return query select v_contact_id, false, true;
end;
$$;

-- Lock down defaults and expose only to authenticated users
revoke all on function find_contact_by_phone_or_email(text, text) from public;
revoke all on function create_or_link_contact(text, text, text, text, date, gender, text, uuid, uuid, text) from public;

grant execute on function find_contact_by_phone_or_email(text, text)
  to authenticated;
grant execute on function create_or_link_contact(text, text, text, text, date, gender, text, uuid, uuid, text)
  to authenticated;
