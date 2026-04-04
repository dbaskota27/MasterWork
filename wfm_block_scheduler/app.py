import streamlit as st
import pandas as pd
import sys, os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from data_manager import get_data_status, load_generated_schedule
from config import APP_NAME

st.set_page_config(
    page_title=APP_NAME,
    page_icon="📋",
    layout="wide",
    initial_sidebar_state="expanded",
)

st.title(f"📋 {APP_NAME}")
st.markdown("Workforce Management scheduling dashboard — upload Excel data, run the scheduler, and view results.")

# --- Data Status ---
st.subheader("Data Status")

status = get_data_status()
entity_labels = {
    "employees": "Employees",
    "schedules": "Schedules",
    "pto_requests": "PTO Requests",
    "clients": "Clients",
    "dept_client_map": "Dept-Client Map",
    "agent_training": "Agent Training",
    "break_lunch_rules": "Break/Lunch Rules",
    "block_dates": "Block Dates",
    "client_hoops": "Client HOOPS",
    "member_overrides": "Member Overrides",
    "fte_requirements": "FTE Requirements",
}

cols = st.columns(5)
for i, (entity, info) in enumerate(status.items()):
    with cols[i % 5]:
        label = entity_labels.get(entity, entity)
        if info["loaded"]:
            st.success(f"✅ **{label}**\n{info['rows']} rows")
        else:
            st.error(f"❌ **{label}**\nNot loaded")

loaded_count = sum(1 for v in status.values() if v["loaded"])
total_count = len(status)
st.progress(loaded_count / total_count, text=f"{loaded_count}/{total_count} data sources loaded")

# --- Last Schedule Run ---
st.divider()
st.subheader("Generated Schedule")

schedule = load_generated_schedule()
if schedule is not None and not schedule.empty:
    for col in ['Start_DateTime', 'End_DateTime']:
        if col in schedule.columns:
            schedule[col] = pd.to_datetime(schedule[col], errors='coerce')

    m1, m2, m3, m4, m5 = st.columns(5)
    m1.metric("Total Shifts", len(schedule))
    m2.metric("Unique Agents", schedule['MemberID'].nunique())

    if 'Shift_Length' in schedule.columns:
        total_hours = schedule['Shift_Length'].sum() / 3600
        m3.metric("Total Hours", f"{total_hours:,.1f}")

    if 'Scheduled_Day' in schedule.columns:
        m4.metric("Days Covered", schedule['Scheduled_Day'].nunique())

    client_col = 'ClientCode' if 'ClientCode' in schedule.columns else 'ProjectID'
    if client_col in schedule.columns:
        m5.metric("Clients", schedule[client_col].nunique())

    # Day breakdown
    if 'Scheduled_Day' in schedule.columns:
        day_order = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
        day_summary = schedule.groupby('Scheduled_Day').agg(
            Shifts=('MemberID', 'count'),
            Agents=('MemberID', 'nunique'),
        ).reindex(day_order).dropna()

        st.bar_chart(day_summary['Shifts'])

    if st.checkbox("Show schedule preview"):
        st.dataframe(schedule.head(20), use_container_width=True)
else:
    st.info("No schedule generated yet. Go to **Run Scheduler** to create one.")

# --- Quick Links ---
st.divider()
st.subheader("Quick Navigation")

c1, c2, c3, c4, c5, c6 = st.columns(6)
c1.page_link("pages/1_Upload_Data.py", label="📤 Upload Data", icon="📤")
c2.page_link("pages/2_Run_Scheduler.py", label="⚙️ Run Scheduler", icon="⚙️")
c3.page_link("pages/3_Schedule_View.py", label="📅 Schedule View", icon="📅")
c4.page_link("pages/4_Client_Coverage.py", label="📈 Client Coverage", icon="📈")
c5.page_link("pages/5_Export.py", label="📥 Export", icon="📥")
c6.page_link("pages/6_Edit_Data.py", label="✏️ Edit Data", icon="✏️")
