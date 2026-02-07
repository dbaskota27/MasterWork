from __future__ import annotations
import streamlit as st
from supabase import Client

def auth_gate(sb: Client) -> dict | None:
    """
    Returns auth dict {user_id, email, access_token, refresh_token} if logged in,
    else shows login/signup UI and returns None.
    """
    if "auth" not in st.session_state:
        st.session_state.auth = None

    if st.session_state.auth:
        return st.session_state.auth

    st.subheader("Login / Sign Up")
    tab_login, tab_signup = st.tabs(["Login", "Sign Up"])

    with tab_login:
        email = st.text_input("Email", key="login_email")
        password = st.text_input("Password", type="password", key="login_password")
        if st.button("Login", use_container_width=True):
            try:
                res = sb.auth.sign_in_with_password({"email": email, "password": password})
                session = res.session
                user = res.user
                st.session_state.auth = {
                    "user_id": user.id,
                    "email": user.email,
                    "access_token": session.access_token,
                    "refresh_token": session.refresh_token,
                }
                st.rerun()
            except Exception as e:
                st.error(f"Login failed: {e}")

    with tab_signup:
        email2 = st.text_input("Email", key="signup_email")
        password2 = st.text_input("Password", type="password", key="signup_password")
        st.caption("If Supabase email confirmation is ON, you must confirm email before logging in.")
        if st.button("Create Account", use_container_width=True):
            try:
                sb.auth.sign_up({"email": email2, "password": password2})
                st.success("Account created. Now login (and confirm email if required).")
            except Exception as e:
                st.error(f"Sign up failed: {e}")

    return None

def logout_button(sb: Client):
    if st.session_state.get("auth"):
        if st.sidebar.button("Logout", use_container_width=True):
            try:
                sb.auth.sign_out()
            except Exception:
                pass
            st.session_state.auth = None
            st.rerun()
