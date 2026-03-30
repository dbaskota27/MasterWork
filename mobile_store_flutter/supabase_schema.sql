-- ══════════════════════════════════════════════════════════════════════════════
-- Mobile Store App — Supabase Schema
-- Run this in your Supabase SQL Editor (one time)
-- ══════════════════════════════════════════════════════════════════════════════

-- ── Stores ──────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS stores (
  id                  uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  name                text NOT NULL DEFAULT 'My Store',
  address             text DEFAULT '',
  phone               text DEFAULT '',
  email               text DEFAULT '',
  currency            text DEFAULT '$',
  tax_rate            numeric DEFAULT 0,
  payment_qr          text DEFAULT '',
  subscription_status text DEFAULT 'trial' CHECK (subscription_status IN ('trial', 'active', 'expired', 'suspended')),
  subscription_expiry timestamptz DEFAULT (now() + interval '7 days'),
  created_at          timestamptz DEFAULT now()
);

-- ── Store Users (links auth.users to a store) ──────────────────────────────
CREATE TABLE IF NOT EXISTS store_users (
  id           uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id      uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  store_id     uuid NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  role         text NOT NULL DEFAULT 'worker' CHECK (role IN ('manager', 'worker')),
  display_name text NOT NULL DEFAULT '',
  created_at   timestamptz DEFAULT now(),
  UNIQUE(user_id, store_id)
);

-- ── Products ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS products (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  store_id   uuid NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  name       text NOT NULL,
  barcode    text,
  price      numeric NOT NULL DEFAULT 0,
  stock      integer NOT NULL DEFAULT 0,
  category   text,
  image_url  text,
  created_at timestamptz DEFAULT now()
);

-- ── Customers ───────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS customers (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  store_id   uuid NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  name       text NOT NULL,
  phone      text,
  email      text,
  created_at timestamptz DEFAULT now()
);

-- ── Invoices ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS invoices (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  store_id        uuid NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  customer_name   text,
  customer_phone  text,
  items           jsonb NOT NULL DEFAULT '[]',
  marked_price    numeric NOT NULL DEFAULT 0,
  discount        numeric NOT NULL DEFAULT 0,
  customer_pays   numeric NOT NULL DEFAULT 0,
  amount_received numeric NOT NULL DEFAULT 0,
  change_given    numeric NOT NULL DEFAULT 0,
  payment_type    text NOT NULL DEFAULT 'cash',
  created_at      timestamptz DEFAULT now()
);

-- ── Indexes ─────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_store_users_user_id  ON store_users(user_id);
CREATE INDEX IF NOT EXISTS idx_store_users_store_id ON store_users(store_id);
CREATE INDEX IF NOT EXISTS idx_products_store_id    ON products(store_id);
CREATE INDEX IF NOT EXISTS idx_products_barcode     ON products(store_id, barcode);
CREATE INDEX IF NOT EXISTS idx_customers_store_id   ON customers(store_id);
CREATE INDEX IF NOT EXISTS idx_invoices_store_id    ON invoices(store_id);
CREATE INDEX IF NOT EXISTS idx_invoices_created     ON invoices(store_id, created_at DESC);

-- ── Row Level Security ──────────────────────────────────────────────────────
-- Users can only see/modify their own store's data.

ALTER TABLE stores        ENABLE ROW LEVEL SECURITY;
ALTER TABLE store_users   ENABLE ROW LEVEL SECURITY;
ALTER TABLE products      ENABLE ROW LEVEL SECURITY;
ALTER TABLE customers     ENABLE ROW LEVEL SECURITY;
ALTER TABLE invoices      ENABLE ROW LEVEL SECURITY;

-- Helper: get the current user's store_id
CREATE OR REPLACE FUNCTION get_my_store_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT store_id FROM store_users WHERE user_id = auth.uid() LIMIT 1;
$$;

-- Stores: user can only see their own store
CREATE POLICY "Users see own store" ON stores
  FOR SELECT USING (id = get_my_store_id());
CREATE POLICY "Users update own store" ON stores
  FOR UPDATE USING (id = get_my_store_id());
-- Insert: anyone authenticated can create a store (signup flow)
CREATE POLICY "Auth users create store" ON stores
  FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

-- Store Users: see users in your own store
CREATE POLICY "See own store users" ON store_users
  FOR SELECT USING (store_id = get_my_store_id());
-- Managers can insert/update/delete store users
CREATE POLICY "Managers manage users" ON store_users
  FOR ALL USING (
    store_id = get_my_store_id()
    AND EXISTS (
      SELECT 1 FROM store_users su
      WHERE su.user_id = auth.uid()
        AND su.store_id = store_users.store_id
        AND su.role = 'manager'
    )
  );
-- Allow first user to insert themselves during signup
CREATE POLICY "Self insert on signup" ON store_users
  FOR INSERT WITH CHECK (user_id = auth.uid());

-- Products / Customers / Invoices: scoped to store
CREATE POLICY "Products by store" ON products FOR ALL
  USING (store_id = get_my_store_id());
CREATE POLICY "Customers by store" ON customers FOR ALL
  USING (store_id = get_my_store_id());
CREATE POLICY "Invoices by store" ON invoices FOR ALL
  USING (store_id = get_my_store_id());
