import streamlit as st
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
from plotly.subplots import make_subplots
import sys, os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from data_manager import load_generated_schedule, load_data

st.set_page_config(page_title="Client Coverage", page_icon="📈", layout="wide")
st.title("📈 Client Coverage & FTE Analysis")

schedule = load_generated_schedule()
fte_req = load_data("fte_requirements")
hoops = load_data("client_hoops")

if schedule is None or schedule.empty:
    st.warning("No generated schedule found. Run the scheduler first.")
    st.stop()

for col in ['Start_DateTime', 'End_DateTime']:
    if col in schedule.columns:
        schedule[col] = pd.to_datetime(schedule[col], errors='coerce')

client_col = 'ClientCode' if 'ClientCode' in schedule.columns else 'ProjectID'
DAY_ORDER = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']

# ============================================================================
# CLIENT SELECTOR
# ============================================================================
clients = sorted(schedule[client_col].dropna().unique().tolist())
selected_client = st.selectbox("Select Client", ["All Clients"] + clients)

if selected_client != "All Clients":
    filtered = schedule[schedule[client_col] == selected_client]
else:
    filtered = schedule

# ============================================================================
# TOP-LEVEL METRICS
# ============================================================================
m1, m2, m3, m4, m5 = st.columns(5)
m1.metric("Total Shifts", len(filtered))
m2.metric("Unique Agents", filtered['MemberID'].nunique())
total_hours = filtered['Shift_Length'].sum() / 3600 if 'Shift_Length' in filtered.columns else 0
m3.metric("Total Hours", f"{total_hours:,.1f}")
actual_fte = round(total_hours / 40, 1) if total_hours > 0 else 0
m4.metric("Effective FTE", actual_fte)
if 'WOTC_Eligible' in filtered.columns:
    wotc_count = (filtered.drop_duplicates('MemberID')['WOTC_Eligible'] == 'Y').sum()
    m5.metric("WOTC Agents", wotc_count)

st.divider()

# ============================================================================
# 1. FTE ACTUAL vs REQUIRED — per client per day (the main view)
# ============================================================================
st.subheader("FTE: Scheduled vs Required — by Client & Day")

if 'Scheduled_Day' in filtered.columns:
    # Calculate actual FTE per client per day (8hr = 1 FTE)
    daily_actual = filtered.groupby([client_col, 'Scheduled_Day']).agg(
        Agents=('MemberID', 'nunique'),
        Shifts=('MemberID', 'count'),
        Hours=('Shift_Length', lambda x: x.sum() / 3600),
    ).reset_index()
    daily_actual['Actual_FTE'] = (daily_actual['Hours'] / 8).round(2)
    daily_actual['Scheduled_Day'] = pd.Categorical(daily_actual['Scheduled_Day'], categories=DAY_ORDER, ordered=True)
    daily_actual = daily_actual.sort_values('Scheduled_Day')

    # Merge with FTE requirements if available
    if fte_req is not None and not fte_req.empty:
        # Sum required FTE per client per period
        req_summary = fte_req.groupby(['ClientCode', 'Period']).agg(RequiredFTE=('RequiredFTE', 'sum')).reset_index()

        # Map Period to days
        period_days = {
            'Weekday': ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'],
            'Weekend': ['Saturday', 'Sunday'],
        }
        req_expanded = []
        for _, row in req_summary.iterrows():
            days = period_days.get(row['Period'], [row['Period']])
            for day in days:
                req_expanded.append({client_col: row['ClientCode'], 'Scheduled_Day': day, 'RequiredFTE': row['RequiredFTE']})
        req_df = pd.DataFrame(req_expanded)
        req_df['Scheduled_Day'] = pd.Categorical(req_df['Scheduled_Day'], categories=DAY_ORDER, ordered=True)

        combined = pd.merge(daily_actual, req_df, on=[client_col, 'Scheduled_Day'], how='outer')
        combined['Actual_FTE'] = combined['Actual_FTE'].fillna(0)
        combined['RequiredFTE'] = combined['RequiredFTE'].fillna(0)
        combined['Gap'] = combined['Actual_FTE'] - combined['RequiredFTE']
        combined['Status'] = combined['Gap'].apply(lambda g: 'Over' if g > 0 else ('Met' if g == 0 else 'Under'))
        combined['Scheduled_Day'] = pd.Categorical(combined['Scheduled_Day'], categories=DAY_ORDER, ordered=True)
        combined = combined.sort_values([client_col, 'Scheduled_Day'])

        # --- Grouped bar chart: Actual vs Required per day ---
        display_clients = [selected_client] if selected_client != "All Clients" else clients

        for client in display_clients:
            client_data = combined[combined[client_col] == client].copy()
            if client_data.empty:
                continue

            st.markdown(f"### {client}")

            # HOOPS info
            if hoops is not None and not hoops.empty:
                client_hoops = hoops[hoops['ClientCode'] == client]
                if not client_hoops.empty:
                    hoops_str = " | ".join([f"{r['DayOfWeek'][:3]}: {r['Open_Time']}-{r['Close_Time']}" for _, r in client_hoops.iterrows()])
                    st.caption(f"Hours of Operation: {hoops_str}")

            fig = go.Figure()
            fig.add_trace(go.Bar(
                name='Scheduled FTE',
                x=client_data['Scheduled_Day'].astype(str),
                y=client_data['Actual_FTE'],
                marker_color='#1f77b4',
                text=client_data['Actual_FTE'].round(1),
                textposition='outside',
            ))
            fig.add_trace(go.Bar(
                name='Required FTE',
                x=client_data['Scheduled_Day'].astype(str),
                y=client_data['RequiredFTE'],
                marker_color='rgba(255, 127, 14, 0.6)',
                marker_line_color='#ff7f0e',
                marker_line_width=2,
                text=client_data['RequiredFTE'].round(1),
                textposition='outside',
            ))
            # Add gap indicator line
            colors = ['green' if g >= 0 else 'red' for g in client_data['Gap']]
            fig.add_trace(go.Scatter(
                name='Gap',
                x=client_data['Scheduled_Day'].astype(str),
                y=client_data['Gap'],
                mode='markers+text',
                marker=dict(size=14, color=colors, symbol='diamond'),
                text=[f"{g:+.1f}" for g in client_data['Gap']],
                textposition='top center',
                textfont=dict(size=11),
                yaxis='y2',
            ))

            fig.update_layout(
                barmode='group',
                template='plotly_dark',
                height=350,
                yaxis_title='FTE',
                yaxis2=dict(title='Gap', overlaying='y', side='right', range=[-5, 5]),
                legend=dict(orientation='h', y=1.12),
                margin=dict(t=40),
            )
            st.plotly_chart(fig, use_container_width=True)

            # Gap detail table
            gap_display = client_data[['Scheduled_Day', 'Agents', 'Hours', 'Actual_FTE', 'RequiredFTE', 'Gap', 'Status']].copy()
            gap_display['Scheduled_Day'] = gap_display['Scheduled_Day'].astype(str)
            gap_display['Hours'] = gap_display['Hours'].round(1)
            numeric_cols = ['Agents', 'Hours', 'Actual_FTE', 'RequiredFTE', 'Gap']
            gap_display[numeric_cols] = gap_display[numeric_cols].fillna(0)

            def highlight_gap(row):
                if row['Status'] == 'Under':
                    return ['background-color: rgba(255,0,0,0.15)'] * len(row)
                elif row['Status'] == 'Over':
                    return ['background-color: rgba(0,255,0,0.08)'] * len(row)
                return [''] * len(row)

            st.dataframe(
                gap_display.style.apply(highlight_gap, axis=1),
                use_container_width=True, hide_index=True,
            )
    else:
        # No FTE requirements — just show actual
        fig = px.bar(
            daily_actual, x='Scheduled_Day', y='Actual_FTE', color=client_col,
            barmode='group', title='Scheduled FTE per Day',
            template='plotly_dark',
        )
        st.plotly_chart(fig, use_container_width=True)
        st.info("Upload FTE Requirements data to see gap analysis.")

# ============================================================================
# 2. WHO'S WORKING — agent roster per day per client
# ============================================================================
st.divider()
st.subheader("Who's Working — Agent Roster by Day")

if 'Scheduled_Day' in filtered.columns:
    for day in DAY_ORDER:
        day_data = filtered[filtered['Scheduled_Day'] == day]
        if day_data.empty:
            continue

        agent_count = day_data['MemberID'].nunique()
        total_hrs = day_data['Shift_Length'].sum() / 3600 if 'Shift_Length' in day_data.columns else 0

        with st.expander(f"**{day}** — {agent_count} agents, {total_hrs:.1f} hrs", expanded=(day == 'Monday')):
            roster = day_data[['Name', 'Department', client_col, 'Start_DateTime', 'End_DateTime',
                               'Shift_Length', 'EmploymentType', 'WOTC_Eligible']].copy() \
                if all(c in day_data.columns for c in ['Name', 'EmploymentType', 'WOTC_Eligible']) \
                else day_data[['Name', 'Department', client_col, 'Start_DateTime', 'End_DateTime', 'Shift_Length']].copy()

            if 'Start_DateTime' in roster.columns:
                roster['Shift'] = roster['Start_DateTime'].dt.strftime('%I:%M %p') + ' - ' + roster['End_DateTime'].dt.strftime('%I:%M %p')
            roster['Hours'] = (roster['Shift_Length'] / 3600).round(1)
            roster = roster.drop(columns=['Start_DateTime', 'End_DateTime', 'Shift_Length'], errors='ignore')

            # Color WOTC workers
            if 'WOTC_Eligible' in roster.columns:
                def highlight_wotc(row):
                    if row.get('WOTC_Eligible') == 'Y':
                        return ['background-color: rgba(0,200,100,0.12)'] * len(row)
                    return [''] * len(row)
                st.dataframe(roster.style.apply(highlight_wotc, axis=1), use_container_width=True, hide_index=True)
            else:
                st.dataframe(roster, use_container_width=True, hide_index=True)

            # Mini summary per client for this day
            if client_col in day_data.columns:
                day_client = day_data.groupby(client_col).agg(
                    Agents=('MemberID', 'nunique'),
                    Hours=('Shift_Length', lambda x: round(x.sum() / 3600, 1)),
                ).reset_index()
                cols = st.columns(len(day_client))
                for i, (_, r) in enumerate(day_client.iterrows()):
                    with cols[i]:
                        st.metric(r[client_col], f"{r['Agents']} agents / {r['Hours']}h")

# ============================================================================
# 3. EMPLOYMENT TYPE & WOTC BREAKDOWN
# ============================================================================
st.divider()
st.subheader("Workforce Composition")

col1, col2 = st.columns(2)

with col1:
    if 'EmploymentType' in filtered.columns:
        emp_breakdown = filtered.drop_duplicates('MemberID').groupby('EmploymentType').agg(
            Agents=('MemberID', 'count'),
        ).reset_index()
        fig_emp = px.pie(emp_breakdown, names='EmploymentType', values='Agents',
                         title='Full-Time vs Part-Time', template='plotly_dark',
                         color_discrete_map={'Full-Time': '#1f77b4', 'Part-Time': '#ff7f0e'})
        st.plotly_chart(fig_emp, use_container_width=True)

with col2:
    if 'WOTC_Eligible' in filtered.columns:
        wotc_breakdown = filtered.drop_duplicates('MemberID').groupby('WOTC_Eligible').agg(
            Agents=('MemberID', 'count'),
        ).reset_index()
        wotc_breakdown['Label'] = wotc_breakdown['WOTC_Eligible'].map({'Y': 'WOTC Eligible', 'N': 'Not WOTC'})
        fig_wotc = px.pie(wotc_breakdown, names='Label', values='Agents',
                          title='WOTC Eligibility', template='plotly_dark',
                          color_discrete_map={'WOTC Eligible': '#2ca02c', 'Not WOTC': '#7f7f7f'})
        st.plotly_chart(fig_wotc, use_container_width=True)

# ============================================================================
# 4. AGENT HOURS HEATMAP — hours per agent per day
# ============================================================================
st.divider()
st.subheader("Agent Hours Heatmap")

if 'Scheduled_Day' in filtered.columns and 'Name' in filtered.columns:
    heatmap_data = filtered.groupby(['Name', 'Scheduled_Day']).agg(
        Hours=('Shift_Length', lambda x: round(x.sum() / 3600, 1))
    ).reset_index()
    heatmap_pivot = heatmap_data.pivot(index='Name', columns='Scheduled_Day', values='Hours').fillna(0)
    # Reorder columns
    heatmap_pivot = heatmap_pivot.reindex(columns=[d for d in DAY_ORDER if d in heatmap_pivot.columns])
    heatmap_pivot['Total'] = heatmap_pivot.sum(axis=1)
    heatmap_pivot = heatmap_pivot.sort_values('Total', ascending=False)

    display_pivot = heatmap_pivot.drop(columns=['Total'])

    fig_heat = px.imshow(
        display_pivot.values,
        x=display_pivot.columns.tolist(),
        y=display_pivot.index.tolist(),
        color_continuous_scale='Blues',
        aspect='auto',
        text_auto=True,
        title='Hours per Agent per Day',
    )
    fig_heat.update_layout(
        template='plotly_dark',
        height=max(400, len(display_pivot) * 28),
        xaxis_title='Day',
        yaxis_title='',
    )
    st.plotly_chart(fig_heat, use_container_width=True)

    # Weekly totals table
    totals = heatmap_pivot[['Total']].reset_index()
    totals = totals.rename(columns={'Name': 'Agent', 'Total': 'Weekly Hours'})
    if 'EmploymentType' in filtered.columns:
        emp_type = filtered.drop_duplicates('MemberID')[['Name', 'EmploymentType', 'WOTC_Eligible']]
        totals = pd.merge(totals, emp_type, left_on='Agent', right_on='Name', how='left').drop(columns='Name', errors='ignore')
    st.dataframe(totals, use_container_width=True, hide_index=True)
