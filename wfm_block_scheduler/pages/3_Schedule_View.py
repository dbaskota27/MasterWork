import streamlit as st
import pandas as pd
import sys, os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from data_manager import load_generated_schedule, load_data

st.set_page_config(page_title="Schedule View", page_icon="📅", layout="wide")

# ============================================================================
# COLOR PALETTES
# ============================================================================
CLIENT_COLORS = {
    'ACME':      {'bg': '#4CAF50', 'text': '#fff'},
    'GLOBEX':    {'bg': '#FF9800', 'text': '#fff'},
    'INITECH':   {'bg': '#2196F3', 'text': '#fff'},
    'UMBRELLA':  {'bg': '#9C27B0', 'text': '#fff'},
    'STARK':     {'bg': '#F44336', 'text': '#fff'},
}
DEPT_COLORS = {
    'Support - Tier 1': {'bg': '#4CAF50', 'text': '#fff'},
    'Support - Tier 2': {'bg': '#66BB6A', 'text': '#fff'},
    'Sales':            {'bg': '#FF9800', 'text': '#fff'},
    'Tech Support':     {'bg': '#2196F3', 'text': '#fff'},
    'Billing':          {'bg': '#FFEB3B', 'text': '#333'},
    'After Hours':      {'bg': '#9C27B0', 'text': '#fff'},
}
DEFAULT_COLOR = {'bg': '#78909C', 'text': '#fff'}
PTO_COLOR = {'bg': '#616161', 'text': '#fff'}
UNAVAIL_COLOR = {'bg': '#9E9E9E', 'text': '#fff'}

DAY_ORDER = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
DAY_SHORT = {'Monday': 'MON', 'Tuesday': 'TUE', 'Wednesday': 'WED', 'Thursday': 'THU',
             'Friday': 'FRI', 'Saturday': 'SAT', 'Sunday': 'SUN'}


def format_time_short(dt):
    """Format datetime to '8a', '5p', '12p' style."""
    if pd.isna(dt):
        return ''
    h = dt.hour
    m = dt.minute
    ampm = 'a' if h < 12 else 'p'
    h12 = h if h <= 12 else h - 12
    if h12 == 0:
        h12 = 12
    if m == 0:
        return f"{h12}{ampm}"
    return f"{h12}:{m:02d}{ampm}"


def get_color(row, color_mode, client_col):
    """Get background/text color for a shift cell."""
    if color_mode == 'Client':
        client = str(row.get(client_col, ''))
        return CLIENT_COLORS.get(client, DEFAULT_COLOR)
    elif color_mode == 'Department':
        dept = str(row.get('Department', ''))
        return DEPT_COLORS.get(dept, DEFAULT_COLOR)
    else:  # Employment type
        if row.get('WOTC_Eligible') == 'Y':
            return {'bg': '#00C853', 'text': '#fff'}
        if row.get('EmploymentType') == 'Part-Time':
            return {'bg': '#FFB74D', 'text': '#333'}
        return {'bg': '#42A5F5', 'text': '#fff'}


def build_schedule_grid(schedule, pto_df, color_mode, client_col):
    """Build the HTML grid table matching the reference screenshot style."""

    schedule['Start_DateTime'] = pd.to_datetime(schedule['Start_DateTime'], errors='coerce')
    schedule['End_DateTime'] = pd.to_datetime(schedule['End_DateTime'], errors='coerce')

    # Get dates for each day
    dates_map = {}
    if 'Scheduled_Date' in schedule.columns:
        for _, row in schedule.iterrows():
            day = row.get('Scheduled_Day', '')
            date = str(row.get('Scheduled_Date', ''))[:10]
            if day and day not in dates_map:
                dates_map[day] = date

    # Get all agents sorted
    agents = schedule.groupby('MemberID').first().reset_index()
    agents = agents.sort_values('Name' if 'Name' in agents.columns else 'MemberID')

    # Build PTO lookup: (MemberID, date_str) -> True
    pto_lookup = set()
    if pto_df is not None and not pto_df.empty:
        approved = pto_df[pto_df['ApprovedStatus'] == 'Approved']
        for _, row in approved.iterrows():
            mid = row['MemberID']
            d = str(row['ScheduleDate'])[:10]
            pto_lookup.add((mid, d))

    # Build shift lookup: (MemberID, day) -> list of shifts
    shift_lookup = {}
    for _, row in schedule.iterrows():
        mid = row['MemberID']
        day = row.get('Scheduled_Day', '')
        key = (mid, day)
        if key not in shift_lookup:
            shift_lookup[key] = []
        shift_lookup[key].append(row)

    # --- Build HTML ---
    html = """
    <style>
    .sched-table { width: 100%%; border-collapse: collapse; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; font-size: 13px; }
    .sched-table th { background: #1a1a2e; color: #aaa; padding: 10px 6px; text-align: center; font-weight: 600; font-size: 11px; text-transform: uppercase; letter-spacing: 0.5px; border-bottom: 2px solid #333; position: sticky; top: 0; z-index: 10; }
    .sched-table th.day-header .day-name { font-size: 12px; }
    .sched-table th.day-header .day-date { font-size: 10px; color: #666; font-weight: 400; }
    .sched-table td { padding: 4px 3px; vertical-align: middle; border-bottom: 1px solid #2a2a3e; min-width: 100px; }
    .sched-table td.staff-cell { padding: 6px 10px; font-weight: 500; color: #e0e0e0; min-width: 140px; white-space: nowrap; position: sticky; left: 0; background: #0e1117; z-index: 5; border-right: 2px solid #333; }
    .sched-table td.staff-cell .staff-name { font-size: 13px; }
    .sched-table td.staff-cell .staff-type { font-size: 9px; color: #888; margin-top: 1px; }
    .sched-table tr:hover td { background-color: rgba(255,255,255,0.03); }
    .sched-table tr:hover td.staff-cell { background-color: #161625; }
    .shift-block { display: inline-block; padding: 5px 8px; border-radius: 4px; margin: 1px 0; font-size: 11px; font-weight: 500; width: calc(100%% - 6px); box-sizing: border-box; line-height: 1.3; }
    .shift-block .shift-time { font-size: 12px; font-weight: 600; }
    .shift-block .shift-label { font-size: 9px; font-weight: 700; letter-spacing: 0.5px; opacity: 0.9; text-transform: uppercase; display: inline-block; margin-left: 4px; padding: 1px 5px; border-radius: 3px; background: rgba(0,0,0,0.2); }
    .pto-block { background: #616161; color: #fff; padding: 6px 8px; border-radius: 4px; font-size: 11px; font-weight: 600; text-align: center; width: calc(100%% - 6px); box-sizing: border-box; }
    .empty-cell { }
    </style>
    """

    html += '<div style="overflow-x: auto; max-height: 75vh; overflow-y: auto;"><table class="sched-table">'

    # Header row
    html += '<tr><th class="staff-cell" style="text-align:left;">STAFF</th>'
    for day in DAY_ORDER:
        date_str = dates_map.get(day, '')
        day_short = DAY_SHORT.get(day, day[:3].upper())
        date_display = ''
        if date_str:
            try:
                dt = pd.to_datetime(date_str)
                date_display = dt.strftime('%b %d')
            except Exception:
                date_display = date_str
        html += f'<th class="day-header"><div class="day-name">{day_short}</div><div class="day-date">{date_display}</div></th>'
    html += '</tr>'

    # Agent rows
    for _, agent in agents.iterrows():
        mid = agent['MemberID']
        name = agent.get('Name', str(mid))
        emp_type = agent.get('EmploymentType', '')
        wotc = ' · WOTC' if agent.get('WOTC_Eligible') == 'Y' else ''
        type_label = f"{emp_type}{wotc}" if emp_type else ''

        html += '<tr>'
        html += f'<td class="staff-cell"><div class="staff-name">{name}</div><div class="staff-type">{type_label}</div></td>'

        for day in DAY_ORDER:
            date_str = dates_map.get(day, '')
            is_pto = (mid, date_str) in pto_lookup
            shifts = shift_lookup.get((mid, day), [])

            html += '<td>'

            if is_pto and not shifts:
                html += '<div class="pto-block">TIME OFF</div>'
            elif shifts:
                for shift in shifts:
                    start_str = format_time_short(shift['Start_DateTime'])
                    end_str = format_time_short(shift['End_DateTime'])
                    colors = get_color(shift, color_mode, client_col)
                    bg = colors['bg']
                    txt = colors['text']

                    # Label based on color mode
                    if color_mode == 'Client':
                        label = str(shift.get(client_col, ''))
                    elif color_mode == 'Department':
                        label = str(shift.get('Department', ''))[:12]
                    else:
                        label = 'WOTC' if shift.get('WOTC_Eligible') == 'Y' else str(shift.get('EmploymentType', ''))[:8]

                    html += f'<div class="shift-block" style="background:{bg};color:{txt};">'
                    html += f'<span class="shift-time">{start_str} - {end_str}</span>'
                    html += f'<span class="shift-label">{label}</span>'
                    html += '</div>'
            else:
                html += '<div class="empty-cell"></div>'

            html += '</td>'

        html += '</tr>'

    html += '</table></div>'
    return html


# ============================================================================
# PAGE LAYOUT
# ============================================================================
schedule = load_generated_schedule()
pto_df = load_data("pto_requests")

if schedule is None or schedule.empty:
    st.warning("No generated schedule found. Run the scheduler first.")
    st.stop()

for col in ['Start_DateTime', 'End_DateTime']:
    if col in schedule.columns:
        schedule[col] = pd.to_datetime(schedule[col], errors='coerce')

client_col = 'ClientCode' if 'ClientCode' in schedule.columns else 'ProjectID'

# --- Header bar ---
col_title, col_nav = st.columns([3, 2])
with col_title:
    st.title("📅 Schedule View")
    if 'Scheduled_Date' in schedule.columns:
        dates = pd.to_datetime(schedule['Scheduled_Date']).dt.date
        st.caption(f"**{dates.min().strftime('%B %d')} - {dates.max().strftime('%B %d, %Y')}**")

# --- Sidebar filters ---
st.sidebar.header("Filters")

# Color mode
color_mode = st.sidebar.radio("Color Code By", ['Client', 'Department', 'Employment'], index=0)

# Color legend
st.sidebar.markdown("---")
st.sidebar.markdown("**Legend**")
if color_mode == 'Client':
    for name, c in CLIENT_COLORS.items():
        st.sidebar.markdown(f'<span style="background:{c["bg"]};color:{c["text"]};padding:2px 10px;border-radius:3px;font-size:12px;font-weight:600;">{name}</span>', unsafe_allow_html=True)
elif color_mode == 'Department':
    for name, c in DEPT_COLORS.items():
        st.sidebar.markdown(f'<span style="background:{c["bg"]};color:{c["text"]};padding:2px 10px;border-radius:3px;font-size:12px;font-weight:600;">{name}</span>', unsafe_allow_html=True)
else:
    st.sidebar.markdown('<span style="background:#00C853;color:#fff;padding:2px 10px;border-radius:3px;font-size:12px;">WOTC Eligible</span>', unsafe_allow_html=True)
    st.sidebar.markdown('<span style="background:#42A5F5;color:#fff;padding:2px 10px;border-radius:3px;font-size:12px;">Full-Time</span>', unsafe_allow_html=True)
    st.sidebar.markdown('<span style="background:#FFB74D;color:#333;padding:2px 10px;border-radius:3px;font-size:12px;">Part-Time</span>', unsafe_allow_html=True)

st.sidebar.markdown(f'<span style="background:#616161;color:#fff;padding:2px 10px;border-radius:3px;font-size:12px;">TIME OFF</span>', unsafe_allow_html=True)

st.sidebar.markdown("---")

# Department filter
if 'Department' in schedule.columns:
    depts = ['All'] + sorted(schedule['Department'].dropna().unique().tolist())
    dept_filter = st.sidebar.selectbox("Department", depts)
    if dept_filter != 'All':
        schedule = schedule[schedule['Department'] == dept_filter]

# Client filter
if client_col in schedule.columns:
    clients = ['All'] + sorted(schedule[client_col].dropna().unique().tolist())
    client_filter = st.sidebar.selectbox("Client", clients)
    if client_filter != 'All':
        schedule = schedule[schedule[client_col] == client_filter]

# Employment type filter
if 'EmploymentType' in schedule.columns:
    emp_types = ['All'] + sorted(schedule['EmploymentType'].dropna().unique().tolist())
    emp_filter = st.sidebar.selectbox("Employment Type", emp_types)
    if emp_filter != 'All':
        schedule = schedule[schedule['EmploymentType'] == emp_filter]

# WOTC filter
if 'WOTC_Eligible' in schedule.columns:
    wotc_filter = st.sidebar.selectbox("WOTC Status", ['All', 'WOTC Only', 'Non-WOTC'])
    if wotc_filter == 'WOTC Only':
        schedule = schedule[schedule['WOTC_Eligible'] == 'Y']
    elif wotc_filter == 'Non-WOTC':
        schedule = schedule[schedule['WOTC_Eligible'] == 'N']

if schedule.empty:
    st.warning("No shifts match the current filters.")
    st.stop()

# --- Summary metrics ---
m1, m2, m3, m4, m5 = st.columns(5)
m1.metric("Agents", schedule['MemberID'].nunique())
m2.metric("Shifts", len(schedule))
total_hrs = schedule['Shift_Length'].sum() / 3600 if 'Shift_Length' in schedule.columns else 0
m3.metric("Total Hours", f"{total_hrs:,.0f}")
if 'EmploymentType' in schedule.columns:
    ft = schedule.drop_duplicates('MemberID')['EmploymentType'].value_counts()
    m4.metric("Full-Time", ft.get('Full-Time', 0))
    m5.metric("Part-Time", ft.get('Part-Time', 0))

# --- The Grid ---
grid_html = build_schedule_grid(schedule, pto_df, color_mode, client_col)
st.components.v1.html(grid_html, height=max(500, schedule['MemberID'].nunique() * 52 + 80), scrolling=True)

# --- Expandable data table ---
with st.expander("View raw data table"):
    st.dataframe(schedule, use_container_width=True, height=400)
