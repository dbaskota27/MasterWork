import streamlit as st

def setup_page():
    st.set_page_config(page_title="Khata Dashboard", layout="wide", page_icon="📈")
    st.title("Mystical Trading Dashboard")
    st.markdown("""
    Auto-loads **all .csv files** from the current folder """)
