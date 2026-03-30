-- ══════════════════════════════════════════════════════════════════════════════
-- STEP 3: Run this AFTER step 2 — creates the store setup RPC function
-- ══════════════════════════════════════════════════════════════════════════════

-- This function creates a store AND links the current user as manager
-- in one atomic operation, bypassing RLS (SECURITY DEFINER).
CREATE OR REPLACE FUNCTION create_store_with_owner(
  p_name text,
  p_address text DEFAULT '',
  p_phone text DEFAULT '',
  p_email text DEFAULT '',
  p_display_name text DEFAULT ''
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_store_id uuid;
BEGIN
  -- Create the store
  INSERT INTO stores (name, address, phone, email, subscription_status, subscription_expiry)
  VALUES (p_name, p_address, p_phone, p_email, 'active', NULL)
  RETURNING id INTO v_store_id;

  -- Link the authenticated user as manager
  INSERT INTO store_users (user_id, store_id, role, display_name)
  VALUES (auth.uid(), v_store_id, 'manager', p_display_name);

  RETURN v_store_id;
END;
$$;
