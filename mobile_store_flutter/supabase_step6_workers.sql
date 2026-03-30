-- ══════════════════════════════════════════════════════════════════════════════
-- STEP 6: Run this — workers table + auth functions (username/password)
-- ══════════════════════════════════════════════════════════════════════════════

-- Enable pgcrypto for password hashing
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Workers table (username + hashed password, no email needed)
CREATE TABLE IF NOT EXISTS workers (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  store_id   uuid NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  username   text NOT NULL,
  password_hash text NOT NULL,
  display_name  text NOT NULL,
  role       text NOT NULL DEFAULT 'worker' CHECK (role IN ('manager', 'worker')),
  is_active  boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  UNIQUE(store_id, username)
);

CREATE INDEX IF NOT EXISTS idx_workers_store_id ON workers(store_id);

-- Add worker_name to invoices to track who made the sale
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS worker_name text;

-- ── Update create_store_with_owner to also create manager's worker profile ──

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
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_store_id uuid;
BEGIN
  INSERT INTO stores (name, address, phone, email, subscription_status, subscription_expiry)
  VALUES (p_name, p_address, p_phone, p_email, 'active', NULL)
  RETURNING id INTO v_store_id;

  INSERT INTO store_users (user_id, store_id, role, display_name)
  VALUES (auth.uid(), v_store_id, 'manager', p_display_name);

  INSERT INTO workers (store_id, username, password_hash, display_name, role)
  VALUES (v_store_id, lower(p_username), crypt(p_password, gen_salt('bf')), p_display_name, 'manager');

  RETURN v_store_id;
END;
$$;

-- ── Worker authentication ───────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION authenticate_worker(p_username text, p_password text)
RETURNS TABLE(id bigint, display_name text, role text)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT w.id, w.display_name, w.role
  FROM workers w
  WHERE w.store_id = (SELECT store_id FROM store_users WHERE user_id = auth.uid() LIMIT 1)
    AND w.username = lower(p_username)
    AND w.password_hash = crypt(p_password, w.password_hash)
    AND w.is_active = true
  LIMIT 1;
$$;

-- ── Worker CRUD ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION create_worker_account(
  p_username text,
  p_password text,
  p_display_name text,
  p_role text DEFAULT 'worker'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_store_id uuid;
BEGIN
  v_store_id := (SELECT store_id FROM store_users WHERE user_id = auth.uid() LIMIT 1);
  IF v_store_id IS NULL THEN RAISE EXCEPTION 'No store linked'; END IF;

  INSERT INTO workers (store_id, username, password_hash, display_name, role)
  VALUES (v_store_id, lower(p_username), crypt(p_password, gen_salt('bf')), p_display_name, p_role);
END;
$$;

CREATE OR REPLACE FUNCTION list_workers()
RETURNS TABLE(id bigint, username text, display_name text, role text, is_active boolean, created_at timestamptz)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT w.id, w.username, w.display_name, w.role, w.is_active, w.created_at
  FROM workers w
  WHERE w.store_id = (SELECT store_id FROM store_users WHERE user_id = auth.uid() LIMIT 1)
  ORDER BY w.created_at;
$$;

CREATE OR REPLACE FUNCTION update_worker_account(
  p_id bigint,
  p_display_name text,
  p_role text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE workers
  SET display_name = p_display_name, role = p_role
  WHERE id = p_id
    AND store_id = (SELECT store_id FROM store_users WHERE user_id = auth.uid() LIMIT 1);
END;
$$;

CREATE OR REPLACE FUNCTION change_worker_password(
  p_id bigint,
  p_new_password text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE workers
  SET password_hash = crypt(p_new_password, gen_salt('bf'))
  WHERE id = p_id
    AND store_id = (SELECT store_id FROM store_users WHERE user_id = auth.uid() LIMIT 1);
END;
$$;

CREATE OR REPLACE FUNCTION delete_worker_account(p_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  DELETE FROM workers
  WHERE id = p_id
    AND store_id = (SELECT store_id FROM store_users WHERE user_id = auth.uid() LIMIT 1);
END;
$$;
