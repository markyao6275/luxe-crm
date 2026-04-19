-- Local seed data. Runs after migrations on `supabase db reset`.
-- Safe to re-run: uses ON CONFLICT DO NOTHING for natural keys.

insert into brands (name) values
  ('Luxe'),
  ('Aurora')
on conflict (name) do nothing;

insert into stores (brand_id, name, address)
select b.id, s.name, s.address
from (values
  ('Luxe',   'Luxe Flagship',   '123 Madison Ave, New York, NY'),
  ('Luxe',   'Luxe SoHo',       '45 Spring St, New York, NY'),
  ('Aurora', 'Aurora Downtown', '500 Market St, San Francisco, CA')
) as s(brand_name, name, address)
join brands b on b.name = s.brand_name
on conflict (brand_id, name) do nothing;
