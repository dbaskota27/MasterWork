-- ══════════════════════════════════════════════════════════════════════════════
-- STEP 5: Run this — worker management RPC functions
-- ══════════════════════════════════════════════════════════════════════════════

-- Add a worker to the manager's store (called after creating the auth user)
CREATE OR REPLACE FUNCTION add_worker_to_store(
  p_worker_user_id uuid,
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
  v_store_id := (SELECT store_id FROM store_users WHERE user_id = auth.uid() AND role = 'manager' LIMIT 1);
  IF v_store_id IS NULL THEN
    RAISE EXCEPTION 'Only managers can add workers';
  END IF;

  INSERT INTO store_users (user_id, store_id, role, display_name)
  VALUES (p_worker_user_id, v_store_id, p_role, p_display_name);
END;
$$;

-- List all users in the manager's store
CREATE OR REPLACE FUNCTION get_store_workers()
RETURNS TABLE(id uuid, user_id uuid, role text, display_name text, created_at timestamptz)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT su.id, su.user_id, su.role, su.display_name, su.created_at
  FROM store_users su
  WHERE su.store_id = (SELECT store_id FROM store_users WHERE user_id = auth.uid() LIMIT 1)
  ORDER BY su.created_at;
$$;

-- Update a worker's role or display name
CREATE OR REPLACE FUNCTION update_worker(
  p_id uuid,
  p_display_name text,
  p_role text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE store_users
  SET display_name = p_display_name, role = p_role
  WHERE id = p_id
    AND store_id = (SELECT store_id FROM store_users WHERE user_id = auth.uid() LIMIT 1);
END;
$$;

-- Delete a worker (can't delete yourself)
CREATE OR REPLACE FUNCTION delete_worker(p_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  DELETE FROM store_users
  WHERE id = p_id
    AND store_id = (SELECT store_id FROM store_users WHERE user_id = auth.uid() LIMIT 1)
    AND user_id != auth.uid();
END;
$$;
