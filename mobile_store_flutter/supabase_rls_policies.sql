-- ══════════════════════════════════════════════════════════════════════════════
-- STEP 2: Run this AFTER step 1 — enables Row Level Security + policies
-- ══════════════════════════════════════════════════════════════════════════════

-- Enable RLS on all tables
ALTER TABLE stores        ENABLE ROW LEVEL SECURITY;
ALTER TABLE store_users   ENABLE ROW LEVEL SECURITY;
ALTER TABLE products      ENABLE ROW LEVEL SECURITY;
ALTER TABLE customers     ENABLE ROW LEVEL SECURITY;
ALTER TABLE invoices      ENABLE ROW LEVEL SECURITY;

-- Helper function: get the current user's store_id
CREATE OR REPLACE FUNCTION get_my_store_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
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

CREATE POLICY "Self insert on signup" ON store_users
  FOR INSERT WITH CHECK (user_id = auth.uid());

-- ── Products / Customers / Invoices policies ────────────────────────────────
CREATE POLICY "Products by store" ON products FOR ALL
  USING (store_id = get_my_store_id());

CREATE POLICY "Customers by store" ON customers FOR ALL
  USING (store_id = get_my_store_id());

CREATE POLICY "Invoices by store" ON invoices FOR ALL
  USING (store_id = get_my_store_id());
