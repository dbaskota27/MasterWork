-- ══════════════════════════════════════════════════════════════════════════════
-- STEP 1: Run this FIRST — drops old tables and creates all new tables + indexes
-- ══════════════════════════════════════════════════════════════════════════════

-- Drop old tables (from previous Streamlit app) so we start clean.
-- CASCADE removes any dependent objects (indexes, foreign keys, etc.)
DROP TABLE IF EXISTS invoices  CASCADE;
DROP TABLE IF EXISTS customers CASCADE;
DROP TABLE IF EXISTS products  CASCADE;
DROP TABLE IF EXISTS store_users CASCADE;
DROP TABLE IF EXISTS stores    CASCADE;

-- Also drop the helper function if it exists from a previous attempt
DROP FUNCTION IF EXISTS get_my_store_id();

-- ── Stores ──────────────────────────────────────────────────────────────────
CREATE TABLE stores (
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
CREATE TABLE store_users (
  id           uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id      uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  store_id     uuid NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  role         text NOT NULL DEFAULT 'worker' CHECK (role IN ('manager', 'worker')),
  display_name text NOT NULL DEFAULT '',
  created_at   timestamptz DEFAULT now(),
  UNIQUE(user_id, store_id)
);

-- ── Products ────────────────────────────────────────────────────────────────
CREATE TABLE products (
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
CREATE TABLE customers (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  store_id   uuid NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  name       text NOT NULL,
  phone      text,
  email      text,
  created_at timestamptz DEFAULT now()
);

-- ── Invoices ────────────────────────────────────────────────────────────────
CREATE TABLE invoices (
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
CREATE INDEX idx_store_users_user_id  ON store_users(user_id);
CREATE INDEX idx_store_users_store_id ON store_users(store_id);
CREATE INDEX idx_products_store_id    ON products(store_id);
CREATE INDEX idx_products_barcode     ON products(store_id, barcode);
CREATE INDEX idx_customers_store_id   ON customers(store_id);
CREATE INDEX idx_invoices_store_id    ON invoices(store_id);
CREATE INDEX idx_invoices_created     ON invoices(store_id, created_at DESC);
