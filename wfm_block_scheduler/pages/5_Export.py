import streamlit as st
import pandas as pd
import io
import sys, os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from data_manager import load_generated_schedule

st.set_page_config(page_title="Export", page_icon="📥", layout="wide")
st.title("📥 Export Schedule")

schedule = load_generated_schedule()

if schedule is None or schedule.empty:
    st.warning("No generated schedule found. Run the scheduler first.")
    st.stop()

# Convert datetime columns for display
for col in ['Start_DateTime', 'End_DateTime', 'Lunch_Start_DateTime', 'Lunch_End_DateTime',
            'BreakA_Start_DateTime', 'BreakA_End_DateTime', 'BreakB_Start_DateTime', 'BreakB_End_DateTime']:
    if col in schedule.columns:
        schedule[col] = pd.to_datetime(schedule[col], errors='coerce')

st.info(f"**{len(schedule)}** shifts available for export")

# --- Filters ---
st.subheader("Filter Before Export")

col1, col2, col3 = st.columns(3)

export_df = schedule.copy()

with col1:
    client_col = 'ClientCode' if 'ClientCode' in schedule.columns else 'ProjectID'
    if client_col in schedule.columns:
        clients = ['All'] + sorted(schedule[client_col].dropna().unique().tolist())
        selected_client = st.selectbox("Client", clients)
        if selected_client != 'All':
            export_df = export_df[export_df[client_col] == selected_client]

with col2:
    if 'Department' in schedule.columns:
        depts = ['All'] + sorted(schedule['Department'].dropna().unique().tolist())
        selected_dept = st.selectbox("Department", depts)
        if selected_dept != 'All':
            export_df = export_df[export_df['Department'] == selected_dept]

with col3:
    if 'Scheduled_Day' in schedule.columns:
        days = ['All'] + ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
        selected_day = st.selectbox("Day", days)
        if selected_day != 'All':
            export_df = export_df[export_df['Scheduled_Day'] == selected_day]

st.markdown(f"**{len(export_df)}** shifts after filtering")

# --- Column Selection ---
st.subheader("Select Columns")
all_columns = list(export_df.columns)
default_cols = [c for c in [
    'MemberID', 'Name', 'Department', 'ClientCode', 'ProjectID',
    'Scheduled_Date', 'Scheduled_Day',
    'Start_DateTime', 'End_DateTime', 'Shift_Length',
    'Lunch_Option', 'Lunch_Start_DateTime', 'Lunch_End_DateTime', 'Lunch_Seconds',
    'BreakA_Option', 'BreakA_Start_DateTime', 'BreakA_End_DateTime', 'BreakA_Seconds',
    'BreakB_Option', 'BreakB_Start_DateTime', 'BreakB_End_DateTime', 'BreakB_Seconds',
] if c in all_columns]

selected_cols = st.multiselect("Columns to export", all_columns, default=default_cols)

if selected_cols:
    export_df = export_df[selected_cols]

# --- Preview ---
st.subheader("Preview")
st.dataframe(export_df.head(50), use_container_width=True, height=400)

# --- Download ---
st.divider()

col_dl1, col_dl2 = st.columns(2)

with col_dl1:
    # Excel download
    buffer = io.BytesIO()
    export_df.to_excel(buffer, index=False, engine='openpyxl')
    buffer.seek(0)

    st.download_button(
        label="📥 Download as Excel",
        data=buffer,
        file_name="wfm_schedule.xlsx",
        mime="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        type="primary",
        use_container_width=True,
    )

with col_dl2:
    # CSV download
    csv_data = export_df.to_csv(index=False)
    st.download_button(
        label="📥 Download as CSV",
        data=csv_data,
        file_name="wfm_schedule.csv",
        mime="text/csv",
        use_container_width=True,
    )
