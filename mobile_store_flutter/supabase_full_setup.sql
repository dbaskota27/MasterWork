-- ══════════════════════════════════════════════════════════════════════════════
-- MOBILE STORE APP — COMPLETE SUPABASE SETUP
-- Run this entire file in the Supabase SQL Editor (one time)
-- ══════════════════════════════════════════════════════════════════════════════

-- Enable pgcrypto for worker password hashing
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ── Drop old/leftover tables from previous apps ────────────────────────────
DROP TABLE IF EXISTS categories       CASCADE;
DROP TABLE IF EXISTS sales            CASCADE;
DROP TABLE IF EXISTS inventory        CASCADE;
DROP TABLE IF EXISTS sync_log         CASCADE;

-- ── Drop current tables (to recreate fresh) ─────────────────────────────────
DROP TABLE IF EXISTS cash_adjustments CASCADE;
DROP TABLE IF EXISTS cash_register    CASCADE;
DROP TABLE IF EXISTS refunds          CASCADE;
DROP TABLE IF EXISTS expenses         CASCADE;
DROP TABLE IF EXISTS sales_targets    CASCADE;
DROP TABLE IF EXISTS workers          CASCADE;
DROP TABLE IF EXISTS invoices         CASCADE;
DROP TABLE IF EXISTS customers        CASCADE;
DROP TABLE IF EXISTS products         CASCADE;
DROP TABLE IF EXISTS store_users      CASCADE;
DROP TABLE IF EXISTS stores           CASCADE;
DROP FUNCTION IF EXISTS get_my_store_id();
DROP FUNCTION IF EXISTS get_my_profile();
DROP FUNCTION IF EXISTS create_store_with_owner(text,text,text,text,text);
DROP FUNCTION IF EXISTS create_store_with_owner(text,text,text,text,text,text,text);
DROP FUNCTION IF EXISTS authenticate_worker(text,text);
DROP FUNCTION IF EXISTS create_worker_account(text,text,text,text);
DROP FUNCTION IF EXISTS create_worker_account(text,text,text,text,jsonb);
DROP FUNCTION IF EXISTS list_workers();
DROP FUNCTION IF EXISTS update_worker_account(bigint,text,text);
DROP FUNCTION IF EXISTS update_worker_account(bigint,text,text,jsonb);
DROP FUNCTION IF EXISTS change_worker_password(bigint,text);
DROP FUNCTION IF EXISTS delete_worker_account(bigint);
DROP FUNCTION IF EXISTS add_worker_to_store(uuid,text,text);
DROP FUNCTION IF EXISTS get_store_workers();
DROP FUNCTION IF EXISTS update_worker(uuid,text,text);
DROP FUNCTION IF EXISTS delete_worker(uuid);

-- ══════════════════════════════════════════════════════════════════════════════
-- TABLES
-- ══════════════════════════════════════════════════════════════════════════════

CREATE TABLE stores (
  id                          uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  name                        text NOT NULL DEFAULT 'My Store',
  address                     text DEFAULT '',
  phone                       text DEFAULT '',
  email                       text DEFAULT '',
  currency                    text DEFAULT '$',
  tax_rate                    numeric DEFAULT 0,
  payment_qr                  text DEFAULT '',
  points_per_unit             numeric DEFAULT 1,
  points_value                numeric DEFAULT 0.01,
  default_low_stock_threshold integer NOT NULL DEFAULT 5,
  subscription_status         text DEFAULT 'active' CHECK (subscription_status IN ('trial', 'active', 'expired', 'suspended')),
  subscription_expiry         timestamptz,
  created_at                  timestamptz DEFAULT now()
);

CREATE TABLE store_users (
  id           uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id      uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  store_id     uuid NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  role         text NOT NULL DEFAULT 'manager',
  display_name text NOT NULL DEFAULT '',
  created_at   timestamptz DEFAULT now(),
  UNIQUE(user_id, store_id)
);

CREATE TABLE workers (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  store_id      uuid NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  username      text NOT NULL,
  password_hash text NOT NULL,
  display_name  text NOT NULL,
  role          text NOT NULL DEFAULT 'worker' CHECK (role IN ('manager', 'worker')),
  permissions   jsonb DEFAULT '{}',
  is_active     boolean DEFAULT true,
  created_at    timestamptz DEFAULT now(),
  UNIQUE(store_id, username)
);

CREATE TABLE products (
  id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  store_id            uuid NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  name                text NOT NULL,
  barcode             text,
  price               numeric NOT NULL DEFAULT 0,
  cost_price          numeric NOT NULL DEFAULT 0,
  stock               integer NOT NULL DEFAULT 0,
  low_stock_threshold integer NOT NULL DEFAULT 5,
  category            text,
  image_url           text,
  created_at          timestamptz DEFAULT now()
);

CREATE TABLE customers (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  store_id   uuid NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  name            text NOT NULL,
  phone           text,
  email           text,
  points_balance  numeric NOT NULL DEFAULT 0,
  created_at      timestamptz DEFAULT now()
);

CREATE TABLE invoices (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  store_id        uuid NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  worker_name      text,
  customer_id      bigint REFERENCES customers(id) ON DELETE SET NULL,
  customer_name    text,
  customer_phone   text,
  points_earned    numeric NOT NULL DEFAULT 0,
  points_redeemed  numeric NOT NULL DEFAULT 0,
  items           jsonb NOT NULL DEFAULT '[]',
  marked_price    numeric NOT NULL DEFAULT 0,
  discount        numeric NOT NULL DEFAULT 0,
  customer_pays   numeric NOT NULL DEFAULT 0,
  amount_received numeric NOT NULL DEFAULT 0,
  change_given    numeric NOT NULL DEFAULT 0,
  payment_type    text NOT NULL DEFAULT 'cash',
  status          text NOT NULL DEFAULT 'completed' CHECK (status IN ('completed', 'partially_refunded', 'fully_refunded')),
  created_at      timestamptz DEFAULT now()
);

CREATE TABLE refunds (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  store_id      uuid NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  invoice_id    bigint NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
  worker_name   text,
  items         jsonb DEFAULT '[]',
  refund_amount numeric DEFAULT 0,
  reason        text,
  created_at    timestamptz DEFAULT now()
);

CREATE TABLE cash_register (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  store_id        uuid NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  worker_name     text,
  date            date DEFAULT CURRENT_DATE,
  opening_balance numeric DEFAULT 0,
  closing_balance numeric,
  cash_in         numeric DEFAULT 0,
  cash_out        numeric DEFAULT 0,
  notes           text,
  status          text DEFAULT 'open' CHECK (status IN ('open', 'closed')),
  opened_at       timestamptz DEFAULT now(),
  closed_at       timestamptz,
  created_at      timestamptz DEFAULT now()
);

CREATE TABLE cash_adjustments (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  register_id bigint NOT NULL REFERENCES cash_register(id) ON DELETE CASCADE,
  store_id    uuid NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  type        text NOT NULL CHECK (type IN ('in', 'out')),
  amount      numeric NOT NULL,
  reason      text,
  worker_name text,
  created_at  timestamptz DEFAULT now()
);

CREATE TABLE expenses (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  store_id    uuid NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  category    text DEFAULT 'other',
  amount      numeric NOT NULL,
  description text,
  date        date DEFAULT CURRENT_DATE,
  worker_name text,
  created_at  timestamptz DEFAULT now()
);

CREATE TABLE sales_targets (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  store_id      uuid NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  worker_id     bigint REFERENCES workers(id) ON DELETE SET NULL,
  worker_name   text,
  period_type   text DEFAULT 'daily' CHECK (period_type IN ('daily', 'monthly')),
  target_amount numeric DEFAULT 0,
  period_start  date NOT NULL,
  period_end    date NOT NULL,
  created_at    timestamptz DEFAULT now()
);

-- ── Indexes ─────────────────────────────────────────────────────────────────
CREATE INDEX idx_store_users_user_id       ON store_users(user_id);
CREATE INDEX idx_store_users_store_id      ON store_users(store_id);
CREATE INDEX idx_workers_store_id          ON workers(store_id);
CREATE INDEX idx_products_store_id         ON products(store_id);
CREATE INDEX idx_products_barcode          ON products(store_id, barcode);
CREATE INDEX idx_customers_store_id        ON customers(store_id);
CREATE INDEX idx_invoices_store_id         ON invoices(store_id);
CREATE INDEX idx_invoices_created          ON invoices(store_id, created_at DESC);
CREATE INDEX idx_refunds_store_id          ON refunds(store_id);
CREATE INDEX idx_refunds_invoice_id        ON refunds(invoice_id);
CREATE INDEX idx_cash_register_store_id    ON cash_register(store_id);
CREATE INDEX idx_cash_adjustments_store_id ON cash_adjustments(store_id);
CREATE INDEX idx_cash_adjustments_reg_id   ON cash_adjustments(register_id);
CREATE INDEX idx_expenses_store_id         ON expenses(store_id);
CREATE INDEX idx_expenses_date             ON expenses(store_id, date DESC);
CREATE INDEX idx_sales_targets_store_id    ON sales_targets(store_id);

-- ══════════════════════════════════════════════════════════════════════════════
-- ROW LEVEL SECURITY
-- ══════════════════════════════════════════════════════════════════════════════

ALTER TABLE stores            ENABLE ROW LEVEL SECURITY;
ALTER TABLE store_users       ENABLE ROW LEVEL SECURITY;
ALTER TABLE products          ENABLE ROW LEVEL SECURITY;
ALTER TABLE customers         ENABLE ROW LEVEL SECURITY;
ALTER TABLE invoices          ENABLE ROW LEVEL SECURITY;
ALTER TABLE workers           ENABLE ROW LEVEL SECURITY;
ALTER TABLE refunds           ENABLE ROW LEVEL SECURITY;
ALTER TABLE cash_register     ENABLE ROW LEVEL SECURITY;
ALTER TABLE cash_adjustments  ENABLE ROW LEVEL SECURITY;
ALTER TABLE expenses          ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales_targets     ENABLE ROW LEVEL SECURITY;

-- Helper: get the current user's store_id
CREATE OR REPLACE FUNCTION get_my_store_id()
RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER
AS $$
  SELECT store_id FROM store_users WHERE user_id = auth.uid() LIMIT 1;
$$;

-- ── Stores policies ─────────────────────────────────────────────────────────
CREATE POLICY "Users see own store" ON stores
  FOR SELECT USING (id = get_my_store_id());
CREATE POLICY "Users update own store" ON stores
  FOR UPDATE USING (id = get_my_store_id());
CREATE POLICY "Auth users create store" ON stores
  FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

-- ── Store Users policies ────────────────────────────────────────────────────
CREATE POLICY "See own store users" ON store_users
  FOR SELECT USING (store_id = get_my_store_id());
CREATE POLICY "Self insert on signup" ON store_users
  FOR INSERT WITH CHECK (user_id = auth.uid());

-- ── Products / Customers / Invoices / Workers policies ──────────────────────
CREATE POLICY "Products by store" ON products FOR ALL
  USING (store_id = get_my_store_id());
CREATE POLICY "Customers by store" ON customers FOR ALL
  USING (store_id = get_my_store_id());
CREATE POLICY "Invoices by store" ON invoices FOR ALL
  USING (store_id = get_my_store_id());
CREATE POLICY "Workers by store" ON workers FOR ALL
  USING (store_id = get_my_store_id());

-- ── Refunds / Cash Register / Expenses / Sales Targets policies ─────────────
CREATE POLICY "Refunds by store" ON refunds FOR ALL
  USING (store_id = get_my_store_id());
CREATE POLICY "Cash register by store" ON cash_register FOR ALL
  USING (store_id = get_my_store_id());
CREATE POLICY "Cash adjustments by store" ON cash_adjustments FOR ALL
  USING (store_id = get_my_store_id());
CREATE POLICY "Expenses by store" ON expenses FOR ALL
  USING (store_id = get_my_store_id());
CREATE POLICY "Sales targets by store" ON sales_targets FOR ALL
  USING (store_id = get_my_store_id());

-- ══════════════════════════════════════════════════════════════════════════════
-- RPC FUNCTIONS (all SECURITY DEFINER to bypass RLS)
-- ══════════════════════════════════════════════════════════════════════════════

-- Get current user's profile (store_id, role, display_name)
CREATE OR REPLACE FUNCTION get_my_profile()
RETURNS TABLE(store_id uuid, role text, display_name text)
LANGUAGE sql STABLE SECURITY DEFINER
AS $$
  SELECT store_id, role, display_name
  FROM store_users
  WHERE user_id = auth.uid()
  LIMIT 1;
$$;

-- Create store + link manager + create manager worker profile
CREATE OR REPLACE FUNCTION create_store_with_owner(
  p_name text,
  p_address text DEFAULT '',
  p_phone text DEFAULT '',
  p_email text DEFAULT '',
  p_display_name text DEFAULT '',
  p_username text DEFAULT 'admin',
  p_password text DEFAULT 'admin123'
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_store_id uuid;
BEGIN
  INSERT INTO stores (name, address, phone, email, subscription_status, subscription_expiry)
  VALUES (p_name, p_address, p_phone, p_email, 'active', NULL)
  RETURNING id INTO v_store_id;

  INSERT INTO store_users (user_id, store_id, role, display_name)
  VALUES (auth.uid(), v_store_id, 'manager', p_display_name);

  INSERT INTO workers (store_id, username, password_hash, display_name, role, permissions)
  VALUES (v_store_id, lower(p_username), crypt(p_password, gen_salt('bf')), p_display_name, 'manager',
    '{"inventory_view":true,"inventory_edit":true,"customers_view":true,"customers_edit":true,"sales":true,"invoices_view":true,"invoices_refund":true,"expenses_view":true,"expenses_edit":true,"reports":true,"cash_register":true,"dashboard":true}'::jsonb);

  RETURN v_store_id;
END;
$$;

-- Authenticate worker by username + password
CREATE OR REPLACE FUNCTION authenticate_worker(p_username text, p_password text)
RETURNS TABLE(id bigint, display_name text, role text, permissions jsonb)
LANGUAGE sql STABLE SECURITY DEFINER
AS $$
  SELECT w.id, w.display_name, w.role, COALESCE(w.permissions, '{}'::jsonb)
  FROM workers w
  WHERE w.store_id = (SELECT store_id FROM store_users WHERE user_id = auth.uid() LIMIT 1)
    AND w.username = lower(p_username)
    AND w.password_hash = crypt(p_password, w.password_hash)
    AND w.is_active = true
  LIMIT 1;
$$;

-- Create a worker account
CREATE OR REPLACE FUNCTION create_worker_account(
  p_username text,
  p_password text,
  p_display_name text,
  p_role text DEFAULT 'worker',
  p_permissions jsonb DEFAULT '{}'
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_store_id uuid;
BEGIN
  v_store_id := (SELECT store_id FROM store_users WHERE user_id = auth.uid() LIMIT 1);
  IF v_store_id IS NULL THEN RAISE EXCEPTION 'No store linked'; END IF;

  INSERT INTO workers (store_id, username, password_hash, display_name, role, permissions)
  VALUES (v_store_id, lower(p_username), crypt(p_password, gen_salt('bf')), p_display_name, p_role, p_permissions);
END;
$$;

-- List all workers in the store
CREATE OR REPLACE FUNCTION list_workers()
RETURNS TABLE(id bigint, username text, display_name text, role text, is_active boolean, created_at timestamptz, permissions jsonb)
LANGUAGE sql STABLE SECURITY DEFINER
AS $$
  SELECT w.id, w.username, w.display_name, w.role, w.is_active, w.created_at, COALESCE(w.permissions, '{}'::jsonb)
  FROM workers w
  WHERE w.store_id = (SELECT store_id FROM store_users WHERE user_id = auth.uid() LIMIT 1)
  ORDER BY w.created_at;
$$;

-- Update worker name/role/permissions
CREATE OR REPLACE FUNCTION update_worker_account(p_id bigint, p_display_name text, p_role text, p_permissions jsonb DEFAULT '{}')
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
  UPDATE workers SET display_name = p_display_name, role = p_role, permissions = p_permissions
  WHERE id = p_id
    AND store_id = (SELECT store_id FROM store_users WHERE user_id = auth.uid() LIMIT 1);
END;
$$;

-- Change worker password
CREATE OR REPLACE FUNCTION change_worker_password(p_id bigint, p_new_password text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
  UPDATE workers SET password_hash = crypt(p_new_password, gen_salt('bf'))
  WHERE id = p_id
    AND store_id = (SELECT store_id FROM store_users WHERE user_id = auth.uid() LIMIT 1);
END;
$$;

-- Delete a worker
CREATE OR REPLACE FUNCTION delete_worker_account(p_id bigint)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
  DELETE FROM workers
  WHERE id = p_id
    AND store_id = (SELECT store_id FROM store_users WHERE user_id = auth.uid() LIMIT 1)
    AND user_id IS DISTINCT FROM auth.uid();
END;
$$;
