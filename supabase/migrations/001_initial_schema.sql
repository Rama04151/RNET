-- RNET Store: initial schema + secure wallet RPCs
-- Run this file in Supabase SQL Editor as project owner.
-- Never expose service_role keys in browser code.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  role text not null default 'buyer' check (role in ('buyer','admin')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.wallets (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  balance bigint not null default 0 check (balance >= 0),
  updated_at timestamptz not null default now()
);

create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text not null default '',
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  category_id uuid references public.categories(id) on delete set null,
  name text not null,
  description text not null default '',
  notes text not null default '',
  price bigint not null check (price >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.payment_methods (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  instructions text not null default '',
  account_name text not null default '',
  account_number text not null default '',
  image_url text,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.deposits (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id),
  payment_method_id uuid references public.payment_methods(id) on delete set null,
  amount bigint not null check (amount >= 1000),
  proof_url text,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  admin_note text not null default '',
  created_at timestamptz not null default now(),
  processed_at timestamptz
);

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  order_number text not null unique,
  user_id uuid not null references public.profiles(id),
  product_id uuid references public.products(id) on delete set null,
  product_name text not null,
  product_price bigint not null check (product_price >= 0),
  destination text not null default '',
  buyer_note text not null default '',
  status text not null default 'pending' check (status in ('pending','processing','success','failed')),
  admin_note text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz
);

create table if not exists public.transfers (
  id uuid primary key default gen_random_uuid(),
  transaction_number text not null unique,
  sender_id uuid not null references public.profiles(id),
  recipient_id uuid not null references public.profiles(id),
  amount bigint not null check (amount >= 10000),
  created_at timestamptz not null default now(),
  constraint transfer_different_users check (sender_id <> recipient_id)
);

create table if not exists public.transactions (
  id uuid primary key default gen_random_uuid(),
  transaction_number text not null unique,
  user_id uuid not null references public.profiles(id),
  type text not null check (type in ('deposit','purchase','transfer_in','transfer_out','refund','admin_adjustment')),
  amount bigint not null,
  reference_id uuid,
  description text not null default '',
  created_at timestamptz not null default now()
);

create table if not exists public.announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null,
  is_active boolean not null default true,
  starts_at timestamptz,
  ends_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.site_settings (
  key text primary key,
  value jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

create index if not exists deposits_user_created_idx on public.deposits(user_id, created_at desc);
create index if not exists orders_user_created_idx on public.orders(user_id, created_at desc);
create index if not exists transfers_sender_created_idx on public.transfers(sender_id, created_at desc);
create index if not exists transfers_recipient_created_idx on public.transfers(recipient_id, created_at desc);
create index if not exists transactions_user_created_idx on public.transactions(user_id, created_at desc);
create index if not exists products_category_active_idx on public.products(category_id, is_active);

create or replace function public.is_admin()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin' and is_active = true
  );
$$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name',''));
  insert into public.wallets (user_id, balance) values (new.id, 0);
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_rnet on auth.users;
create trigger on_auth_user_created_rnet
after insert on auth.users
for each row execute procedure public.handle_new_user();

create or replace function public.create_wallet_order(
  p_product_id uuid,
  p_destination text default '',
  p_buyer_note text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_product public.products%rowtype;
  v_balance bigint;
  v_order_id uuid;
  v_order_number text;
  v_tx text;
begin
  if v_user is null then raise exception 'Silakan login terlebih dahulu'; end if;
  select * into v_product from public.products where id = p_product_id and is_active = true;
  if not found then raise exception 'Produk tidak tersedia'; end if;
  select balance into v_balance from public.wallets where user_id = v_user for update;
  if not found then raise exception 'Wallet tidak ditemukan'; end if;
  if v_balance < v_product.price then raise exception 'Saldo tidak mencukupi'; end if;

  update public.wallets set balance = balance - v_product.price, updated_at = now()
  where user_id = v_user;

  v_order_id := gen_random_uuid();
  v_order_number := 'RNET-ORD-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,12));
  v_tx := 'RNET-TX-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,12));

  insert into public.orders(id,order_number,user_id,product_id,product_name,product_price,destination,buyer_note)
  values(v_order_id,v_order_number,v_user,v_product.id,v_product.name,v_product.price,coalesce(p_destination,''),coalesce(p_buyer_note,''));

  insert into public.transactions(transaction_number,user_id,type,amount,reference_id,description)
  values(v_tx,v_user,'purchase',-v_product.price,v_order_id,'Pembelian ' || v_product.name);

  return jsonb_build_object('order_id',v_order_id,'order_number',v_order_number,'transaction_number',v_tx,'status','pending');
end;
$$;

create or replace function public.transfer_wallet(p_recipient_email text, p_amount bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sender uuid := auth.uid();
  v_recipient uuid;
  v_balance bigint;
  v_transfer_id uuid := gen_random_uuid();
  v_transfer_no text := 'RNET-TRF-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,12));
  v_sender_tx text := 'RNET-TX-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,12));
  v_recipient_tx text := 'RNET-TX-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,12));
begin
  if v_sender is null then raise exception 'Silakan login terlebih dahulu'; end if;
  if p_amount is null or p_amount < 10000 then raise exception 'Minimal transfer Rp10.000'; end if;
  select u.id into v_recipient from auth.users u
  where lower(u.email) = lower(trim(p_recipient_email)) and u.id <> v_sender;
  if v_recipient is null then raise exception 'Akun penerima tidak ditemukan'; end if;

  -- Lock both wallet rows in stable UUID order to reduce deadlock risk.
  perform 1 from public.wallets
  where user_id in (v_sender,v_recipient)
  order by user_id
  for update;
  if (select count(*) from public.wallets where user_id in (v_sender,v_recipient)) <> 2 then
    raise exception 'Wallet pengirim atau penerima tidak ditemukan';
  end if;
  select balance into v_balance from public.wallets where user_id = v_sender;
  if v_balance < p_amount then raise exception 'Saldo tidak mencukupi'; end if;

  update public.wallets set balance = balance - p_amount, updated_at = now() where user_id = v_sender;
  update public.wallets set balance = balance + p_amount, updated_at = now() where user_id = v_recipient;

  insert into public.transfers(id,transaction_number,sender_id,recipient_id,amount)
  values(v_transfer_id,v_transfer_no,v_sender,v_recipient,p_amount);
  insert into public.transactions(transaction_number,user_id,type,amount,reference_id,description) values
    (v_sender_tx,v_sender,'transfer_out',-p_amount,v_transfer_id,'Transfer saldo ke buyer lain'),
    (v_recipient_tx,v_recipient,'transfer_in',p_amount,v_transfer_id,'Transfer saldo diterima');
  return jsonb_build_object('transfer_id',v_transfer_id,'transaction_number',v_transfer_no,'amount',p_amount,'status','success');
end;
$$;

create or replace function public.admin_process_deposit(p_deposit_id uuid,p_approve boolean,p_note text default '')
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deposit public.deposits%rowtype;
  v_tx text := 'RNET-TX-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,12));
begin
  if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if;
  select * into v_deposit from public.deposits where id = p_deposit_id for update;
  if not found then raise exception 'Permintaan deposit tidak ditemukan'; end if;
  if v_deposit.status <> 'pending' then raise exception 'Deposit sudah diproses'; end if;

  update public.deposits set status = case when p_approve then 'approved' else 'rejected' end,
    admin_note = coalesce(p_note,''), processed_at = now() where id = p_deposit_id;
  if p_approve then
    update public.wallets set balance = balance + v_deposit.amount, updated_at = now()
    where user_id = v_deposit.user_id;
    insert into public.transactions(transaction_number,user_id,type,amount,reference_id,description)
    values(v_tx,v_deposit.user_id,'deposit',v_deposit.amount,p_deposit_id,'Deposit disetujui admin');
  end if;
  return jsonb_build_object('deposit_id',p_deposit_id,'status',case when p_approve then 'approved' else 'rejected' end);
end;
$$;

create or replace function public.admin_finish_order(p_order_id uuid,p_status text,p_note text default '')
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_tx text := 'RNET-TX-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,12));
begin
  if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if;
  if p_status not in ('processing','success','failed') then raise exception 'Status tidak valid'; end if;
  select * into v_order from public.orders where id = p_order_id for update;
  if not found then raise exception 'Pesanan tidak ditemukan'; end if;
  if v_order.status in ('success','failed') then raise exception 'Pesanan sudah selesai'; end if;

  update public.orders set status=p_status,admin_note=coalesce(p_note,''),updated_at=now(),
    completed_at=case when p_status in ('success','failed') then now() else null end
  where id=p_order_id;

  if p_status='failed' then
    update public.wallets set balance=balance+v_order.product_price,updated_at=now() where user_id=v_order.user_id;
    insert into public.transactions(transaction_number,user_id,type,amount,reference_id,description)
    values(v_tx,v_order.user_id,'refund',v_order.product_price,p_order_id,'Pengembalian dana pesanan gagal');
  end if;
  return jsonb_build_object('order_id',p_order_id,'status',p_status);
end;
$$;

alter table public.profiles enable row level security;
alter table public.wallets enable row level security;
alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.payment_methods enable row level security;
alter table public.deposits enable row level security;
alter table public.orders enable row level security;
alter table public.transfers enable row level security;
alter table public.transactions enable row level security;
alter table public.announcements enable row level security;
alter table public.site_settings enable row level security;

drop policy if exists "profiles_select_own_or_admin" on public.profiles;
create policy "profiles_select_own_or_admin" on public.profiles for select to authenticated
using (id = auth.uid() or public.is_admin());

drop policy if exists "wallets_select_own_or_admin" on public.wallets;
create policy "wallets_select_own_or_admin" on public.wallets for select to authenticated
using (user_id = auth.uid() or public.is_admin());

drop policy if exists "categories_read_active_or_admin" on public.categories;
create policy "categories_read_active_or_admin" on public.categories for select
using (is_active = true or public.is_admin());
drop policy if exists "categories_admin_all" on public.categories;
create policy "categories_admin_all" on public.categories for all to authenticated
using (public.is_admin()) with check (public.is_admin());

drop policy if exists "products_read_active_or_admin" on public.products;
create policy "products_read_active_or_admin" on public.products for select
using (is_active = true or public.is_admin());
drop policy if exists "products_admin_all" on public.products;
create policy "products_admin_all" on public.products for all to authenticated
using (public.is_admin()) with check (public.is_admin());

drop policy if exists "payment_methods_read_active_or_admin" on public.payment_methods;
create policy "payment_methods_read_active_or_admin" on public.payment_methods for select
using (is_active = true or public.is_admin());
drop policy if exists "payment_methods_admin_all" on public.payment_methods;
create policy "payment_methods_admin_all" on public.payment_methods for all to authenticated
using (public.is_admin()) with check (public.is_admin());

drop policy if exists "deposits_select_own_or_admin" on public.deposits;
create policy "deposits_select_own_or_admin" on public.deposits for select to authenticated
using (user_id = auth.uid() or public.is_admin());
drop policy if exists "deposits_insert_own" on public.deposits;
create policy "deposits_insert_own" on public.deposits for insert to authenticated
with check (user_id = auth.uid() and status = 'pending');

drop policy if exists "orders_select_own_or_admin" on public.orders;
create policy "orders_select_own_or_admin" on public.orders for select to authenticated
using (user_id = auth.uid() or public.is_admin());

drop policy if exists "transfers_select_participant_or_admin" on public.transfers;
create policy "transfers_select_participant_or_admin" on public.transfers for select to authenticated
using (sender_id = auth.uid() or recipient_id = auth.uid() or public.is_admin());

drop policy if exists "transactions_select_own_or_admin" on public.transactions;
create policy "transactions_select_own_or_admin" on public.transactions for select to authenticated
using (user_id = auth.uid() or public.is_admin());

drop policy if exists "announcements_read_active_or_admin" on public.announcements;
create policy "announcements_read_active_or_admin" on public.announcements for select
using ((is_active = true and (starts_at is null or starts_at <= now()) and (ends_at is null or ends_at > now())) or public.is_admin());
drop policy if exists "announcements_admin_all" on public.announcements;
create policy "announcements_admin_all" on public.announcements for all to authenticated
using (public.is_admin()) with check (public.is_admin());

drop policy if exists "settings_read_public" on public.site_settings;
create policy "settings_read_public" on public.site_settings for select to anon, authenticated
using (key in ('store_name','customer_service_whatsapp','customer_service_email'));
drop policy if exists "settings_admin_all" on public.site_settings;
create policy "settings_admin_all" on public.site_settings for all to authenticated
using (public.is_admin()) with check (public.is_admin());

revoke all on function public.create_wallet_order(uuid,text,text) from public;
revoke all on function public.transfer_wallet(text,bigint) from public;
revoke all on function public.admin_process_deposit(uuid,boolean,text) from public;
revoke all on function public.admin_finish_order(uuid,text,text) from public;
grant execute on function public.create_wallet_order(uuid,text,text) to authenticated;
grant execute on function public.transfer_wallet(text,bigint) to authenticated;
grant execute on function public.admin_process_deposit(uuid,boolean,text) to authenticated;
grant execute on function public.admin_finish_order(uuid,text,text) to authenticated;

-- IMPORTANT: After creating your own account, promote its profile to admin
-- manually in the Supabase SQL Editor, replacing the email below:
-- update public.profiles p set role='admin'
-- from auth.users u where p.id=u.id and u.email='YOUR-ADMIN-EMAIL';
