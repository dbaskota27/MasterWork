from __future__ import annotations
from typing import Any, Dict, List
import streamlit as st
from supabase import create_client, Client

TABLE = "user_trades"

def get_supabase() -> Client:
    url = st.secrets.get("SUPABASE_URL", "")
    key = st.secrets.get("SUPABASE_ANON_KEY", "")
    if not url or not key:
        raise RuntimeError("Missing SUPABASE_URL / SUPABASE_ANON_KEY in .streamlit/secrets.toml")
    return create_client(url, key)

def set_auth_session(sb: Client, access_token: str, refresh_token: str) -> None:
    # Ensures RLS policies apply for the logged-in user.
    sb.auth.set_session(access_token=access_token, refresh_token=refresh_token)

def delete_user_trades(sb: Client, user_id: str) -> None:
    sb.table(TABLE).delete().eq("user_id", user_id).execute()

def insert_user_trades(sb: Client, rows: List[Dict[str, Any]], batch_size: int = 500) -> None:
    for i in range(0, len(rows), batch_size):
        sb.table(TABLE).insert(rows[i:i+batch_size]).execute()

def fetch_user_trades(sb: Client, user_id: str, limit: int = 200000) -> List[Dict[str, Any]]:
    resp = sb.table(TABLE).select("*").eq("user_id", user_id).limit(limit).execute()
    return resp.data or []

def count_user_trades(sb: Client, user_id: str) -> int:
    resp = sb.table(TABLE).select("id").eq("user_id", user_id).limit(1).execute()
    return len(resp.data or [])
