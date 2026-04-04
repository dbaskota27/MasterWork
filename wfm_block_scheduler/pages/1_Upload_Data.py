import streamlit as st
import pandas as pd
import sys, os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import DATA_FILES, REQUIRED_COLUMNS
from data_manager import save_data, load_data, validate_columns, delete_data


def sanitize_for_editor(df):
    """Clean a DataFrame so st.data_editor doesn't crash on mixed/NaN types."""
    df = df.copy()
    for col in df.columns:
        if isinstance(df[col].dtype, pd.CategoricalDtype):
            df[col] = df[col].astype(str)
        if df[col].dtype == object:
            df[col] = df[col].fillna('')
        if pd.api.types.is_float_dtype(df[col]):
            if df[col].dropna().apply(lambda x: x == int(x) if pd.notna(x) else True).all():
                df[col] = df[col].fillna(0).astype(int)
    return df

st.set_page_config(page_title="Upload & Edit Data", page_icon="📤", layout="wide")
st.title("📤 Upload & Edit Data")
st.markdown("Upload Excel files **or** edit data directly below. All changes save back to the Excel source files.")

# Group entities into tabs
tab_groups = {
    "Employees & Schedules": ["employees", "schedules"],
    "PTO & Overrides": ["pto_requests", "member_overrides"],
    "Clients & Training": ["clients", "dept_client_map", "agent_training", "client_hoops"],
    "Rules & Dates": ["break_lunch_rules", "block_dates", "fte_requirements"],
}

ENTITY_LABELS = {
    "employees": "Employees",
    "schedules": "Work Schedules",
    "pto_requests": "PTO Requests",
    "clients": "Clients / Projects",
    "dept_client_map": "Department-Client Mapping",
    "agent_training": "Agent Training / Skills",
    "break_lunch_rules": "Break & Lunch Rules",
    "block_dates": "Client Block Dates",
    "member_overrides": "Member Override Settings",
    "fte_requirements": "FTE Requirements",
    "client_hoops": "Client Hours of Operation (HOOPS)",
}

ENTITY_DESCRIPTIONS = {
    "employees": "Employee roster: MemberID, FullName, Department, EmploymentType (Full-Time/Part-Time), MaxWeeklyHours, WOTC_Eligible (Y/N), TerminationDate, WFMOverride (1/0), WFMDoNotSchedule (1/0)",
    "schedules": "Work schedules: MemberID + either a 'Schedule' column (JSON) or day columns like Monday_Start, Monday_End, etc.",
    "pto_requests": "PTO requests: MemberID, ScheduleDate, PaidHours, UnpaidHours, ApprovedStatus",
    "clients": "Client/project list: ProjectID, ClientCode, ClientName, Active (1/0)",
    "dept_client_map": "Maps departments to clients: Department, ClientCode",
    "agent_training": "Agent skills: MemberID, ProjectID, TypeID, Ranking (1 = primary)",
    "break_lunch_rules": "Break rules by shift length: Shift_Length_hrs, Lunch_Option (Y/N), BreakA_Option, BreakB_Option, window percentages, durations",
    "block_dates": "Blocked scheduling dates per client: Date_Blocked, ClientCode",
    "member_overrides": "Per-member overrides: MemberID, Override_breakA/B/Lunch/FullSchedule (Y/N), duration overrides",
    "fte_requirements": "Staffing requirements: ClientCode, Role, RequiredFTE, Period",
    "client_hoops": "Client hours of operation per day: ClientCode, DayOfWeek (Monday-Sunday), Open_Time (HH:MM), Close_Time (HH:MM)",
}

# Column type hints for data_editor
COLUMN_CONFIG = {
    "employees": {
        "EmploymentType": st.column_config.SelectboxColumn("EmploymentType", options=["Full-Time", "Part-Time"], default="Full-Time"),
        "WOTC_Eligible": st.column_config.SelectboxColumn("WOTC_Eligible", options=["Y", "N"], default="N"),
        "WFMOverride": st.column_config.SelectboxColumn("WFMOverride", options=[0, 1], default=1),
        "WFMDoNotSchedule": st.column_config.SelectboxColumn("WFMDoNotSchedule", options=[0, 1], default=0),
    },
    "pto_requests": {
        "ApprovedStatus": st.column_config.SelectboxColumn("ApprovedStatus", options=["Approved", "Pending", "Denied"], default="Pending"),
        "ScheduleDate": st.column_config.TextColumn("ScheduleDate"),
    },
    "clients": {
        "Active": st.column_config.SelectboxColumn("Active", options=[0, 1], default=1),
    },
    "break_lunch_rules": {
        "Lunch_Option": st.column_config.SelectboxColumn("Lunch_Option", options=["Y", "N"], default="N"),
        "BreakA_Option": st.column_config.SelectboxColumn("BreakA_Option", options=["Y", "N"], default="N"),
        "BreakB_Option": st.column_config.SelectboxColumn("BreakB_Option", options=["Y", "N"], default="N"),
    },
    "block_dates": {
        "Date_Blocked": st.column_config.TextColumn("Date_Blocked"),
    },
    "member_overrides": {
        "Override_breakA": st.column_config.SelectboxColumn("Override_breakA", options=["Y", "N"], default="N"),
        "Override_breakB": st.column_config.SelectboxColumn("Override_breakB", options=["Y", "N"], default="N"),
        "Override_Lunch": st.column_config.SelectboxColumn("Override_Lunch", options=["Y", "N"], default="N"),
        "Override_FullSchedule": st.column_config.SelectboxColumn("Override_FullSchedule", options=["Y", "N"], default="N"),
    },
    "client_hoops": {
        "DayOfWeek": st.column_config.SelectboxColumn("DayOfWeek", options=["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]),
    },
}

tabs = st.tabs(list(tab_groups.keys()))

for tab, (group_name, entities) in zip(tabs, tab_groups.items()):
    with tab:
        for entity in entities:
            st.subheader(ENTITY_LABELS[entity])
            st.caption(ENTITY_DESCRIPTIONS[entity])

            required = REQUIRED_COLUMNS.get(entity, [])
            st.markdown(f"**Required columns:** `{'`, `'.join(required)}`")

            existing = load_data(entity)

            # --- Upload section ---
            with st.expander("📁 Upload from Excel file", expanded=existing is None):
                uploaded = st.file_uploader(
                    f"Upload {ENTITY_LABELS[entity]}",
                    type=["xlsx", "xls"],
                    key=f"upload_{entity}",
                )
                if uploaded is not None:
                    try:
                        df = pd.read_excel(uploaded)
                        st.dataframe(df.head(10), use_container_width=True)
                        st.info(f"Preview: {len(df)} rows, {len(df.columns)} columns")

                        valid, missing = validate_columns(entity, df)
                        if not valid:
                            st.error(f"Missing required columns: {', '.join(missing)}")
                        else:
                            st.success("All required columns present")
                            if st.button(f"💾 Import {ENTITY_LABELS[entity]}", key=f"save_{entity}"):
                                if save_data(entity, df):
                                    st.success(f"Imported {len(df)} rows to {entity}.xlsx")
                                    st.rerun()
                    except Exception as e:
                        st.error(f"Error reading file: {e}")

            # --- Inline editor section ---
            if existing is not None:
                st.markdown(f"**{len(existing)} rows loaded** — edit inline below, then click Save.")

                col_config = COLUMN_CONFIG.get(entity, {})

                edited_df = st.data_editor(
                    sanitize_for_editor(existing),
                    num_rows="dynamic",
                    use_container_width=True,
                    key=f"editor_{entity}",
                    column_config=col_config,
                    height=min(400, max(150, (len(existing) + 1) * 35 + 50)),
                )

                btn_col1, btn_col2, btn_col3 = st.columns([1, 1, 4])

                with btn_col1:
                    if st.button(f"💾 Save Changes", key=f"save_edit_{entity}", type="primary"):
                        # Validate before saving
                        valid, missing = validate_columns(entity, edited_df)
                        if not valid:
                            st.error(f"Missing required columns: {', '.join(missing)}")
                        else:
                            if save_data(entity, edited_df):
                                st.success(f"Saved {len(edited_df)} rows back to {entity}.xlsx")
                                st.rerun()

                with btn_col2:
                    if st.button(f"🗑️ Remove All", key=f"delete_{entity}"):
                        delete_data(entity)
                        st.success(f"Removed {entity} data.")
                        st.rerun()
            else:
                st.info("No data loaded yet. Upload an Excel file above to get started.")

            st.divider()
