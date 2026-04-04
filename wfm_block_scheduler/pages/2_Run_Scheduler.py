import streamlit as st
import pandas as pd
import sys, os
from datetime import datetime, timedelta

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from data_manager import load_data, load_all_data, save_generated_schedule, load_generated_schedule
from scheduling_engine import run_scheduling_pipeline
from config import DEFAULT_MAX_ROUND_ROBINS

st.set_page_config(page_title="Run Scheduler", page_icon="⚙️", layout="wide")
st.title("⚙️ Run Scheduler")

# --- Configuration ---
st.subheader("Scheduling Configuration")

col1, col2, col3 = st.columns(3)

with col1:
    today = datetime.now().date()
    next_monday = today - timedelta(days=today.weekday()) + timedelta(7)

    date_options = {
        "Next Week": next_monday,
        "Current Week": today - timedelta(days=today.weekday()),
        "2 Weeks Out": next_monday + timedelta(7),
        "3 Weeks Out": next_monday + timedelta(14),
        "4 Weeks Out": next_monday + timedelta(21),
    }
    date_choice = st.selectbox("Schedule Week", list(date_options.keys()))
    start_date = date_options[date_choice]
    end_date = start_date + timedelta(6)
    st.info(f"📅 {start_date.strftime('%b %d')} — {end_date.strftime('%b %d, %Y')}")

with col2:
    # Get available clients
    clients_df = load_data("clients")
    client_options = ["ALL"]
    if clients_df is not None and not clients_df.empty:
        client_options += sorted(clients_df['ClientCode'].dropna().unique().tolist())
    client_filter = st.selectbox("Client Filter", client_options)

with col3:
    max_round_robins = st.slider("Max Round Robins", 1, 10, DEFAULT_MAX_ROUND_ROBINS)

col4, col5 = st.columns(2)
with col4:
    prioritize_wotc = st.checkbox("Prioritize WOTC-eligible workers", value=True,
                                   help="Schedule WOTC workers first so they get priority when shifts are limited")
with col5:
    st.caption("Part-time workers are automatically capped at their MaxWeeklyHours. "
               "Client HOOPS are enforced if client_hoops data is loaded.")

# --- Data Status Check ---
st.subheader("Data Status")
data = load_all_data()

required_entities = ["employees", "schedules"]
optional_entities = ["pto_requests", "clients", "dept_client_map", "agent_training",
                     "break_lunch_rules", "block_dates", "member_overrides", "client_hoops"]

status_cols = st.columns(5)
all_entities = required_entities + optional_entities
for i, entity in enumerate(all_entities):
    with status_cols[i % 5]:
        if entity in data:
            st.success(f"✅ {entity}: {len(data[entity])} rows")
        elif entity in required_entities:
            st.error(f"❌ {entity}: REQUIRED")
        else:
            st.warning(f"⚠️ {entity}: not loaded")

# Check if required data is available
can_run = all(e in data for e in required_entities)

if not can_run:
    st.error("Upload required data (employees, schedules) before running the scheduler.")
    st.stop()

# --- Run Button ---
st.divider()

if st.button("🚀 Run Scheduler", type="primary", use_container_width=True):
    progress_bar = st.progress(0)
    status_text = st.empty()
    log_container = st.container()

    def progress_callback(step, total, message):
        progress_bar.progress(step / total)
        status_text.text(f"Step {step}/{total}: {message}")

    with st.spinner("Running scheduling pipeline..."):
        result_df, log_messages = run_scheduling_pipeline(
            employees_df=data["employees"],
            schedules_df=data["schedules"],
            pto_df=data.get("pto_requests"),
            clients_df=data.get("clients"),
            dept_client_map_df=data.get("dept_client_map"),
            training_df=data.get("agent_training"),
            rules_df=data.get("break_lunch_rules"),
            block_dates_df=data.get("block_dates"),
            overrides_df=data.get("member_overrides"),
            hoops_df=data.get("client_hoops"),
            start_date=start_date,
            client_filter=client_filter,
            max_round_robins=max_round_robins,
            prioritize_wotc=prioritize_wotc,
            progress_callback=progress_callback,
        )

    progress_bar.progress(1.0)
    status_text.text("Complete!")

    # Show log
    with st.expander("Pipeline Log", expanded=False):
        for msg in log_messages:
            st.text(msg)

    # Show results
    if result_df is not None and not result_df.empty:
        st.success(f"✅ Generated {len(result_df)} shift schedules!")

        # Summary metrics
        m1, m2, m3, m4 = st.columns(4)
        m1.metric("Total Shifts", len(result_df))
        m2.metric("Unique Agents", result_df['MemberID'].nunique())
        if 'Scheduled_Day' in result_df.columns:
            m3.metric("Days Covered", result_df['Scheduled_Day'].nunique())
        if 'ClientCode' in result_df.columns:
            m4.metric("Clients", result_df['ClientCode'].nunique())
        elif 'ProjectID' in result_df.columns:
            m4.metric("Projects", result_df['ProjectID'].nunique())

        st.dataframe(result_df, use_container_width=True, height=400)

        # Save result
        save_generated_schedule(result_df)
        st.info("💾 Schedule saved. View it in Schedule View or Export pages.")
    else:
        st.warning("No shifts were generated. Check the pipeline log for details.")

# --- Previous Results ---
st.divider()
st.subheader("Previous Generated Schedule")
prev = load_generated_schedule()
if prev is not None:
    st.info(f"Last generated schedule: {len(prev)} shifts")
    if st.checkbox("Show previous schedule"):
        st.dataframe(prev, use_container_width=True, height=300)
else:
    st.info("No previous schedule found. Run the scheduler to generate one.")
