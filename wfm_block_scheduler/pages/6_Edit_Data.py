import streamlit as st
import pandas as pd
import numpy as np
import sys, os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from data_manager import load_data, save_data

st.set_page_config(page_title="Edit Data", page_icon="✏️", layout="wide")
st.title("✏️ Edit Data")
st.markdown("Edit source data directly. Changes are saved back to the Excel files.")

DAY_OPTIONS = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]


def sanitize_for_editor(df):
    """Clean a DataFrame so st.data_editor doesn't crash on mixed/NaN types."""
    df = df.copy()
    for col in df.columns:
        # Convert any categorical to string
        if isinstance(df[col].dtype, pd.CategoricalDtype):
            df[col] = df[col].astype(str)
        # For object (string) columns, fill NaN with empty string
        if df[col].dtype == object:
            df[col] = df[col].fillna('')
        # For float columns that are really ints (e.g. 1.0 → 1), convert
        if pd.api.types.is_float_dtype(df[col]):
            if df[col].dropna().apply(lambda x: x == int(x) if pd.notna(x) else True).all():
                df[col] = df[col].fillna(0).astype(int)
    return df


tab_hoops, tab_agents, tab_clients, tab_training, tab_overrides = st.tabs([
    "Client HOOPS", "Agents / Employees", "Clients", "Agent Training", "Member Overrides",
])

# ============================================================================
# TAB 1: CLIENT HOOPS
# ============================================================================
with tab_hoops:
    st.subheader("Client Hours of Operation")
    st.caption("Set open/close times per client per day. Shifts outside these windows will be trimmed or removed.")

    hoops = load_data("client_hoops")

    if hoops is not None and not hoops.empty:
        client_list = sorted(hoops['ClientCode'].dropna().unique().tolist())
        selected_client = st.selectbox("Select Client to Edit", client_list, key="hoops_client")

        client_hoops = hoops[hoops['ClientCode'] == selected_client].copy()

        # Ensure all 7 days exist
        existing_days = client_hoops['DayOfWeek'].tolist()
        for day in DAY_OPTIONS:
            if day not in existing_days:
                new_row = pd.DataFrame([{'ClientCode': selected_client, 'DayOfWeek': day, 'Open_Time': '', 'Close_Time': ''}])
                client_hoops = pd.concat([client_hoops, new_row], ignore_index=True)

        # Sort by day order using a temp column (avoid Categorical)
        client_hoops['_sort'] = client_hoops['DayOfWeek'].map({d: i for i, d in enumerate(DAY_OPTIONS)})
        client_hoops = client_hoops.sort_values('_sort').drop(columns='_sort').reset_index(drop=True)

        st.markdown(f"**{selected_client}** — leave Open/Close empty to mark that day as closed")

        editor_df = sanitize_for_editor(client_hoops[['DayOfWeek', 'Open_Time', 'Close_Time']])
        edited_hoops = st.data_editor(
            editor_df,
            use_container_width=True,
            hide_index=True,
            disabled=['DayOfWeek'],
            key=f"hoops_editor_{selected_client}",
            column_config={
                'DayOfWeek': st.column_config.TextColumn("Day", width="medium"),
                'Open_Time': st.column_config.TextColumn("Open Time (HH:MM)", width="medium"),
                'Close_Time': st.column_config.TextColumn("Close Time (HH:MM)", width="medium"),
            },
        )

        if st.button("💾 Save HOOPS", key="save_hoops", type="primary"):
            edited_hoops['ClientCode'] = selected_client
            edited_hoops['DayOfWeek'] = edited_hoops['DayOfWeek'].astype(str)
            edited_hoops = edited_hoops[
                (edited_hoops['Open_Time'].notna()) & (edited_hoops['Open_Time'].astype(str).str.strip() != '') &
                (edited_hoops['Close_Time'].notna()) & (edited_hoops['Close_Time'].astype(str).str.strip() != '')
            ]
            other_hoops = hoops[hoops['ClientCode'] != selected_client]
            full_hoops = pd.concat([other_hoops, edited_hoops], ignore_index=True)
            if save_data("client_hoops", full_hoops):
                st.success(f"Saved HOOPS for {selected_client}")
                st.rerun()

        with st.expander("View all clients HOOPS"):
            pivot = hoops.pivot(index='ClientCode', columns='DayOfWeek', values='Open_Time').fillna('')
            pivot_close = hoops.pivot(index='ClientCode', columns='DayOfWeek', values='Close_Time').fillna('')
            display = pivot.astype(str) + ' - ' + pivot_close.astype(str)
            display = display.replace(' - ', 'CLOSED').replace('nan - nan', 'CLOSED')
            cols_order = [d for d in DAY_OPTIONS if d in display.columns]
            st.dataframe(display[cols_order], use_container_width=True)

    else:
        st.info("No HOOPS data loaded. Upload client_hoops.xlsx in the Upload Data page first.")


# ============================================================================
# TAB 2: AGENTS / EMPLOYEES
# ============================================================================
with tab_agents:
    st.subheader("Agents / Employees")
    st.caption("Edit employee details: employment type, WOTC eligibility, weekly hours cap, WFM settings.")

    employees = load_data("employees")
    if employees is not None and not employees.empty:
        col_f1, col_f2 = st.columns(2)
        with col_f1:
            dept_filter = st.selectbox("Filter by Department", ["All"] + sorted(employees['Department'].dropna().unique().tolist()), key="emp_dept")
        with col_f2:
            type_filter = st.selectbox("Filter by Type", ["All", "Full-Time", "Part-Time"], key="emp_type")

        display_emp = employees.copy()
        if dept_filter != "All":
            display_emp = display_emp[display_emp['Department'] == dept_filter]
        if type_filter != "All":
            display_emp = display_emp[display_emp.get('EmploymentType', '') == type_filter]

        # Drop TerminationDate if it's all NaN (causes editor issues)
        if 'TerminationDate' in display_emp.columns and display_emp['TerminationDate'].isna().all():
            display_emp = display_emp.drop(columns=['TerminationDate'])

        display_emp = sanitize_for_editor(display_emp)

        edited_emp = st.data_editor(
            display_emp,
            use_container_width=True,
            num_rows="dynamic",
            key="emp_editor",
            column_config={
                'MemberID': st.column_config.NumberColumn("MemberID"),
                'EmploymentType': st.column_config.SelectboxColumn("Employment Type", options=["Full-Time", "Part-Time"], default="Full-Time"),
                'WOTC_Eligible': st.column_config.SelectboxColumn("WOTC", options=["Y", "N"], default="N"),
                'WFMOverride': st.column_config.SelectboxColumn("WFM Override", options=[0, 1], default=1),
                'WFMDoNotSchedule': st.column_config.SelectboxColumn("Do Not Schedule", options=[0, 1], default=0),
                'MaxWeeklyHours': st.column_config.NumberColumn("Max Weekly Hrs", min_value=0, max_value=60),
            },
            height=min(600, len(display_emp) * 35 + 80),
        )

        if st.button("💾 Save Employees", key="save_emp", type="primary"):
            if dept_filter != "All" or type_filter != "All":
                edited_ids = edited_emp['MemberID'].tolist()
                unchanged = employees[~employees['MemberID'].isin(edited_ids)]
                full_emp = pd.concat([unchanged, edited_emp], ignore_index=True)
            else:
                full_emp = edited_emp
            if save_data("employees", full_emp):
                st.success(f"Saved {len(full_emp)} employees")
                st.rerun()

        c1, c2, c3 = st.columns(3)
        c1.metric("Total", len(employees))
        c2.metric("Full-Time", (employees.get('EmploymentType', pd.Series()) == 'Full-Time').sum())
        c3.metric("WOTC Eligible", (employees.get('WOTC_Eligible', pd.Series()) == 'Y').sum())
    else:
        st.info("No employee data loaded.")


# ============================================================================
# TAB 3: CLIENTS
# ============================================================================
with tab_clients:
    st.subheader("Clients / Projects")
    st.caption("Set **UniformShift = Y** to force all agents for that client to the same start/end time.")

    clients = load_data("clients")
    if clients is not None and not clients.empty:
        for col, default in [('UniformShift', 'N'), ('UniformStart', ''), ('UniformEnd', '')]:
            if col not in clients.columns:
                clients[col] = default

        clients = sanitize_for_editor(clients)

        edited_clients = st.data_editor(
            clients,
            use_container_width=True,
            num_rows="dynamic",
            key="clients_editor",
            column_config={
                'Active': st.column_config.SelectboxColumn("Active", options=[0, 1], default=1),
                'UniformShift': st.column_config.SelectboxColumn("Uniform Shift", options=["Y", "N"], default="N",
                    help="Y = all agents for this client start and end at the same time"),
                'UniformStart': st.column_config.TextColumn("Uniform Start (HH:MM)",
                    help="e.g. 08:00 — only used when UniformShift=Y"),
                'UniformEnd': st.column_config.TextColumn("Uniform End (HH:MM)",
                    help="e.g. 17:00 — only used when UniformShift=Y"),
            },
        )
        if st.button("💾 Save Clients", key="save_clients", type="primary"):
            if save_data("clients", edited_clients):
                st.success(f"Saved {len(edited_clients)} clients")
                st.rerun()

        uniform_on = clients[clients['UniformShift'] == 'Y']
        if not uniform_on.empty:
            st.info("**Uniform shift clients:** " + ", ".join(
                f"{r['ClientCode']} ({r['UniformStart']}-{r['UniformEnd']})" for _, r in uniform_on.iterrows()
            ))
    else:
        st.info("No client data loaded.")


# ============================================================================
# TAB 4: AGENT TRAINING
# ============================================================================
with tab_training:
    st.subheader("Agent Training / Skills")
    st.caption("Which agents are trained for which client projects. Ranking 1 = primary assignment.")

    training = load_data("agent_training")
    employees = load_data("employees")
    clients = load_data("clients")

    if training is not None and not training.empty:
        display_train = training.copy()
        if employees is not None:
            name_map = employees.set_index('MemberID')['FullName'].to_dict()
            display_train.insert(1, 'AgentName', display_train['MemberID'].map(name_map).fillna(''))
        if clients is not None:
            client_map = clients.set_index('ProjectID')['ClientCode'].to_dict()
            display_train['Client'] = display_train['ProjectID'].map(client_map).fillna('')

        filter_options = ["All"] + sorted(display_train['Client'].dropna().unique().tolist()) if 'Client' in display_train.columns else ["All"]
        train_filter = st.selectbox("Filter by Client", filter_options, key="train_filter")
        if train_filter != "All" and 'Client' in display_train.columns:
            display_train = display_train[display_train['Client'] == train_filter]

        display_train = sanitize_for_editor(display_train)

        edited_train = st.data_editor(
            display_train,
            use_container_width=True,
            num_rows="dynamic",
            key="train_editor",
            disabled=['AgentName', 'Client'],
            column_config={
                'Ranking': st.column_config.NumberColumn("Ranking", min_value=1, max_value=10, default=1),
            },
        )

        if st.button("💾 Save Training", key="save_training", type="primary"):
            save_cols = [c for c in ['MemberID', 'ProjectID', 'TypeID', 'Ranking'] if c in edited_train.columns]
            if save_data("agent_training", edited_train[save_cols]):
                st.success(f"Saved {len(edited_train)} training records")
                st.rerun()
    else:
        st.info("No training data loaded.")


# ============================================================================
# TAB 5: MEMBER OVERRIDES
# ============================================================================
with tab_overrides:
    st.subheader("Member Override Settings")
    st.caption("Per-member overrides for breaks, lunch, and full schedule.")

    overrides = load_data("member_overrides")
    employees = load_data("employees")

    if overrides is not None and not overrides.empty:
        display_ov = overrides.copy()
        if employees is not None:
            name_map = employees.set_index('MemberID')['FullName'].to_dict()
            display_ov.insert(1, 'AgentName', display_ov['MemberID'].map(name_map).fillna(''))

        display_ov = sanitize_for_editor(display_ov)

        edited_ov = st.data_editor(
            display_ov,
            use_container_width=True,
            num_rows="dynamic",
            key="overrides_editor",
            disabled=['AgentName'],
            column_config={
                'Override_breakA': st.column_config.SelectboxColumn("Override Break A", options=["Y", "N"], default="N"),
                'Override_breakB': st.column_config.SelectboxColumn("Override Break B", options=["Y", "N"], default="N"),
                'Override_Lunch': st.column_config.SelectboxColumn("Override Lunch", options=["Y", "N"], default="N"),
                'Override_FullSchedule': st.column_config.SelectboxColumn("Full Override", options=["Y", "N"], default="N"),
                'Lunch_Duration': st.column_config.SelectboxColumn("Custom Lunch", options=["Y", "N"], default="N"),
                'breakA_Duration': st.column_config.SelectboxColumn("Custom Break A", options=["Y", "N"], default="N"),
                'breakB_Duration': st.column_config.SelectboxColumn("Custom Break B", options=["Y", "N"], default="N"),
            },
        )

        if st.button("💾 Save Overrides", key="save_overrides", type="primary"):
            save_cols = [c for c in edited_ov.columns if c != 'AgentName']
            if save_data("member_overrides", edited_ov[save_cols]):
                st.success(f"Saved {len(edited_ov)} override records")
                st.rerun()
    else:
        st.info("No override data loaded. You can add new rows here.")
        if employees is not None and not employees.empty:
            st.markdown("**Add a new override:**")
            new_mid = st.selectbox("Agent", employees[['MemberID', 'FullName']].apply(lambda r: f"{r['MemberID']} - {r['FullName']}", axis=1).tolist())
            if st.button("Add Override"):
                mid = int(new_mid.split(' - ')[0])
                new_ov = pd.DataFrame([{
                    'MemberID': mid, 'Override_breakA': 'N', 'Override_breakB': 'N',
                    'Override_Lunch': 'N', 'Override_FullSchedule': 'N',
                    'Lunch_Duration': 'N', 'Lunch_Duration_Min': 30,
                    'breakA_Duration': 'N', 'breakA_Duration_Min': 15,
                    'breakB_Duration': 'N', 'breakB_Duration_Min': 15,
                }])
                save_data("member_overrides", new_ov)
                st.rerun()
