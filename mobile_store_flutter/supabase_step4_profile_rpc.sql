-- ══════════════════════════════════════════════════════════════════════════════
-- STEP 4: Run this AFTER step 3 — profile loader RPC (bypasses RLS)
-- ══════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION get_my_profile()
RETURNS TABLE(store_id uuid, role text, display_name text)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT store_id, role, display_name
  FROM store_users
  WHERE user_id = auth.uid()
  LIMIT 1;
$$;
