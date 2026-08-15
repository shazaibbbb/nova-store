-- NOVA E-COMMERCE — PHASE 2 DATABASE
-- Run this entire file in Supabase SQL Editor.

create extension if not exists pgcrypto;

do $$ begin
  create type public.user_role as enum ('customer','admin');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.order_status as enum ('pending','confirmed','processing','shipped','delivered','cancelled');
exception when duplicate_object then null; end $$;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  phone text not null default '',
  role public.user_role not null default 'customer',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  slug text not null unique,
  created_at timestamptz not null default now()
);

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  description text not null default '',
  price numeric(12,2) not null check (price >= 0),
  old_price numeric(12,2) check (old_price is null or old_price >= 0),
  stock integer not null default 0 check (stock >= 0),
  sku text unique,
  category_id uuid references public.categories(id) on delete set null,
  image_url text,
  featured boolean not null default false,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.addresses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  full_name text not null,
  phone text not null,
  email text not null,
  address text not null,
  city text not null,
  postal_code text not null default '',
  instructions text not null default '',
  created_at timestamptz not null default now()
);

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  order_number text not null unique default ('ORD-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,10))),
  user_id uuid not null references public.profiles(id) on delete restrict,
  customer_name text not null,
  customer_phone text not null,
  customer_email text not null,
  delivery_address text not null,
  city text not null,
  postal_code text not null default '',
  instructions text not null default '',
  subtotal numeric(12,2) not null check (subtotal >= 0),
  delivery_fee numeric(12,2) not null default 0 check (delivery_fee >= 0),
  total numeric(12,2) not null check (total >= 0),
  payment_method text not null default 'cod',
  status public.order_status not null default 'pending',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null,
  product_name text not null,
  unit_price numeric(12,2) not null check (unit_price >= 0),
  quantity integer not null check (quantity > 0),
  line_total numeric(12,2) generated always as (unit_price * quantity) stored
);

create table if not exists public.order_status_history (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  old_status public.order_status,
  new_status public.order_status not null,
  changed_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.store_settings (
  id boolean primary key default true,
  store_name text not null default 'NOVA',
  whatsapp text not null default '',
  admin_email text not null default '',
  delivery_fee numeric(12,2) not null default 200,
  logo_url text,
  updated_at timestamptz not null default now()
);
insert into public.store_settings(id) values(true) on conflict (id) do nothing;

create index if not exists products_category_idx on public.products(category_id);
create index if not exists products_active_idx on public.products(active);
create index if not exists orders_user_idx on public.orders(user_id);
create index if not exists orders_created_idx on public.orders(created_at desc);
create index if not exists order_items_order_idx on public.order_items(order_id);

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public
as $$ select exists(select 1 from public.profiles where id = auth.uid() and role = 'admin'); $$;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  insert into public.profiles(id, full_name, phone) values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name',''),
    coalesce(new.raw_user_meta_data->>'phone','')
  ) on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();

create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$ begin new.updated_at = now(); return new; end; $$;

drop trigger if exists profiles_touch on public.profiles; create trigger profiles_touch before update on public.profiles for each row execute procedure public.touch_updated_at();
drop trigger if exists products_touch on public.products; create trigger products_touch before update on public.products for each row execute procedure public.touch_updated_at();
drop trigger if exists orders_touch on public.orders; create trigger orders_touch before update on public.orders for each row execute procedure public.touch_updated_at();

-- Atomically creates an order and decrements stock. Client cannot choose prices/stock.
create or replace function public.place_order(
  p_customer_name text,
  p_customer_phone text,
  p_customer_email text,
  p_delivery_address text,
  p_city text,
  p_postal_code text,
  p_instructions text,
  p_delivery_fee numeric,
  p_items jsonb
)
returns public.orders
language plpgsql security definer set search_path = public
as $$
declare
  v_order public.orders;
  v_subtotal numeric(12,2) := 0;
  v_item jsonb;
  v_product public.products;
  v_qty integer;
  v_fee numeric(12,2) := greatest(coalesce(p_delivery_fee,0),0);
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then raise exception 'Cart is empty'; end if;

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_qty := greatest((v_item->>'quantity')::integer,0);
    select * into v_product from public.products where id = (v_item->>'product_id')::uuid and active = true for update;
    if not found then raise exception 'Product is unavailable'; end if;
    if v_qty < 1 then raise exception 'Invalid quantity'; end if;
    if v_product.stock < v_qty then raise exception 'Not enough stock for %', v_product.name; end if;
    v_subtotal := v_subtotal + (v_product.price * v_qty);
  end loop;

  insert into public.orders(user_id,customer_name,customer_phone,customer_email,delivery_address,city,postal_code,instructions,subtotal,delivery_fee,total)
  values(auth.uid(),p_customer_name,p_customer_phone,p_customer_email,p_delivery_address,p_city,p_postal_code,p_instructions,v_subtotal,v_fee,v_subtotal+v_fee)
  returning * into v_order;

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_qty := (v_item->>'quantity')::integer;
    select * into v_product from public.products where id = (v_item->>'product_id')::uuid for update;
    insert into public.order_items(order_id,product_id,product_name,unit_price,quantity)
      values(v_order.id,v_product.id,v_product.name,v_product.price,v_qty);
    update public.products set stock = stock - v_qty where id = v_product.id;
  end loop;

  insert into public.order_status_history(order_id,new_status,changed_by) values(v_order.id,'pending',auth.uid());
  return v_order;
end;
$$;

-- RLS
alter table public.profiles enable row level security;
alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.addresses enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.order_status_history enable row level security;
alter table public.store_settings enable row level security;

-- Drop policies so this script is safely re-runnable.
do $$ declare r record; begin for r in select schemaname, tablename, policyname from pg_policies where schemaname='public' and tablename in ('profiles','categories','products','addresses','orders','order_items','order_status_history','store_settings') loop execute format('drop policy if exists %I on %I.%I', r.policyname, r.schemaname, r.tablename); end loop; end $$;

create policy profiles_select_own_or_admin on public.profiles for select using (id=auth.uid() or public.is_admin());
create policy profiles_update_own_or_admin on public.profiles for update using (id=auth.uid() or public.is_admin()) with check (id=auth.uid() or public.is_admin());
create policy profiles_admin_all on public.profiles for all using (public.is_admin()) with check (public.is_admin());

create policy categories_public_read on public.categories for select using (true);
create policy categories_admin_write on public.categories for all using (public.is_admin()) with check (public.is_admin());

create policy products_public_read on public.products for select using (active=true or public.is_admin());
create policy products_admin_write on public.products for all using (public.is_admin()) with check (public.is_admin());

create policy addresses_own on public.addresses for all using (user_id=auth.uid() or public.is_admin()) with check (user_id=auth.uid() or public.is_admin());

create policy orders_own_or_admin_select on public.orders for select using (user_id=auth.uid() or public.is_admin());
create policy orders_admin_update on public.orders for update using (public.is_admin()) with check (public.is_admin());
create policy orders_admin_delete on public.orders for delete using (public.is_admin());

create policy order_items_own_or_admin_select on public.order_items for select using (exists(select 1 from public.orders o where o.id=order_id and (o.user_id=auth.uid() or public.is_admin())));
create policy order_history_own_or_admin_select on public.order_status_history for select using (exists(select 1 from public.orders o where o.id=order_id and (o.user_id=auth.uid() or public.is_admin())));
create policy order_history_admin_insert on public.order_status_history for insert with check (public.is_admin());

create policy settings_public_read on public.store_settings for select using (true);
create policy settings_admin_write on public.store_settings for all using (public.is_admin()) with check (public.is_admin());

-- Product image bucket.
insert into storage.buckets(id,name,public) values('product-images','product-images',true) on conflict (id) do update set public=true;

drop policy if exists product_images_public_read on storage.objects;
drop policy if exists product_images_admin_insert on storage.objects;
drop policy if exists product_images_admin_update on storage.objects;
drop policy if exists product_images_admin_delete on storage.objects;
create policy product_images_public_read on storage.objects for select using (bucket_id='product-images');
create policy product_images_admin_insert on storage.objects for insert with check (bucket_id='product-images' and public.is_admin());
create policy product_images_admin_update on storage.objects for update using (bucket_id='product-images' and public.is_admin()) with check (bucket_id='product-images' and public.is_admin());
create policy product_images_admin_delete on storage.objects for delete using (bucket_id='product-images' and public.is_admin());

-- Seed categories/products. Safe to re-run because slugs are unique.
insert into public.categories(name,slug) values
('Electronics','electronics'),('Fashion','fashion'),('Accessories','accessories')
on conflict (slug) do nothing;

insert into public.products(name,slug,description,price,old_price,stock,category_id,featured,active)
select 'Aero Wireless Headphones','aero-wireless-headphones','Immersive sound, comfortable fit and all-day battery.',6999,7999,12,id,true,true from public.categories where slug='electronics'
on conflict (slug) do nothing;
insert into public.products(name,slug,description,price,old_price,stock,category_id,featured,active)
select 'Nova Essential Hoodie','nova-essential-hoodie','Clean everyday hoodie with a premium soft finish.',3499,3999,20,id,true,true from public.categories where slug='fashion'
on conflict (slug) do nothing;
insert into public.products(name,slug,description,price,old_price,stock,category_id,featured,active)
select 'Orbit Smart Watch','orbit-smart-watch','Modern smartwatch with fitness and notification features.',8999,9999,8,id,true,true from public.categories where slug='accessories'
on conflict (slug) do nothing;
insert into public.products(name,slug,description,price,old_price,stock,category_id,featured,active)
select 'Urban Carry Backpack','urban-carry-backpack','Minimal everyday backpack with laptop compartment.',2999,3499,15,id,false,true from public.categories where slug='accessories'
on conflict (slug) do nothing;

-- Phase 3: notification delivery logs
create table if not exists public.notification_logs (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  channel text not null check (channel in ('admin_email','customer_email','whatsapp','email')),
  status text not null check (status in ('sent','failed','skipped')),
  provider_response jsonb,
  created_at timestamptz not null default now()
);
create index if not exists notification_logs_order_idx on public.notification_logs(order_id, created_at desc);
alter table public.notification_logs enable row level security;
drop policy if exists notification_logs_admin_select on public.notification_logs;
create policy notification_logs_admin_select on public.notification_logs for select using (public.is_admin());
revoke all on public.notification_logs from anon, authenticated;
grant select on public.notification_logs to authenticated;
