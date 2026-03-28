"""Authentication and role-based access for the store app."""
import streamlit as st
from config import (
    STORE_NAME,
    MANAGER_USERNAME, MANAGER_PASSWORD,
    WORKER_USERNAME,  WORKER_PASSWORD,
)

USERS = {
    MANAGER_USERNAME: {"password": MANAGER_PASSWORD, "role": "manager", "label": "Manager"},
    WORKER_USERNAME:  {"password": WORKER_PASSWORD,  "role": "worker",  "label": "Worker"},
}


# ─── Public API ───────────────────────────────────────────────────────────────

def require_login():
    """Call at the top of every page. Blocks with login screen if not authenticated."""
    if not st.session_state.get("authenticated"):
        _show_login()
        st.stop()
    _render_sidebar_user()


def require_manager():
    """Call on manager-only pages after require_login()."""
    if not is_manager():
        st.error("🔒 This section is for managers only.")
        st.stop()


def is_manager() -> bool:
    return st.session_state.get("role") == "manager"


def is_worker() -> bool:
    return st.session_state.get("role") == "worker"


# ─── Login screen ─────────────────────────────────────────────────────────────

def _show_login():
    st.markdown(
        f"""
        <div style="text-align:center; padding: 40px 0 10px 0;">
            <span style="font-size:48px">📱</span>
            <h1 style="margin:8px 0 4px 0;">{STORE_NAME}</h1>
            <p style="color:#888; margin:0;">Sign in to continue</p>
        </div>
        """,
        unsafe_allow_html=True,
    )

    _, col, _ = st.columns([1, 1.1, 1])
    with col:
        with st.form("login_form"):
            username = st.text_input("Username")
            password = st.text_input("Password", type="password")
            submitted = st.form_submit_button(
                "Login", use_container_width=True, type="primary"
            )

        if submitted:
            user = USERS.get(username.strip().lower())
            if user and password == user["password"]:
                st.session_state.authenticated = True
                st.session_state.role          = user["role"]
                st.session_state.username      = username.strip().lower()
                st.rerun()
            else:
                with col:
                    st.error("Incorrect username or password.")


# ─── Sidebar user info + logout ───────────────────────────────────────────────

def _render_sidebar_user():
    role  = st.session_state.get("role", "")
    uname = st.session_state.get("username", "").capitalize()
    badge = "🟢 Manager" if role == "manager" else "🔵 Worker"

    with st.sidebar:
        st.divider()
        st.markdown(f"**👤 {uname}** — {badge}")
        if st.button("🚪 Logout", use_container_width=True, key="_logout_btn"):
            for k in list(st.session_state.keys()):
                del st.session_state[k]
            st.rerun()
        st.divider()
