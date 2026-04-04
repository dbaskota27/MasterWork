import pandas as pd
import numpy as np
from datetime import datetime, timedelta

from shift_parser import generate_metrics, consolidate_overnight_shifts, adjust_sunday_shifts
from break_assigner import assign_breaks
from overlap_checker import (
    apply_member_overrides,
    split_overnight_shifts,
    check_schedule_overlap,
    apply_block_dates,
    handle_midnight_block_dates,
    filter_final_schedule,
)


def _enforce_client_hoops(schedule_df, hoops_df, clients_df, training_df):
    """Trim or remove shifts that fall outside client Hours of Operation.

    For each shift, look up the client's HOOPS for that day. If the shift
    extends beyond the HOOPS window, clamp it. If it falls entirely outside,
    remove it.
    """
    if hoops_df is None or hoops_df.empty:
        return schedule_df

    df = schedule_df.copy()
    df['Start_DateTime'] = pd.to_datetime(df['Start_DateTime'])
    df['End_DateTime'] = pd.to_datetime(df['End_DateTime'])

    # We need MemberID → ProjectID to know which client's HOOPS to use.
    # If ProjectID isn't on the df yet, temporarily merge from training.
    has_project = 'ProjectID' in df.columns and df['ProjectID'].notna().any()
    if not has_project and training_df is not None and not training_df.empty:
        train = training_df.copy()
        if 'Ranking' in train.columns:
            train = train[train['Ranking'] == 1]
        train = train[['MemberID', 'ProjectID']].drop_duplicates(subset='MemberID')
        df = pd.merge(df, train, on='MemberID', how='left')
        temp_project = True
    else:
        temp_project = False

    if 'ProjectID' not in df.columns:
        return schedule_df

    # Map ProjectID → ClientCode
    if clients_df is not None and not clients_df.empty:
        cmap = clients_df[['ProjectID', 'ClientCode']].drop_duplicates()
        cmap['ProjectID'] = cmap['ProjectID'].astype(str)
        df['ProjectID'] = df['ProjectID'].astype(str)
        df = pd.merge(df, cmap, on='ProjectID', how='left', suffixes=('', '_hoops'))

    if 'ClientCode' not in df.columns:
        return schedule_df

    # Build HOOPS lookup: (ClientCode, DayOfWeek) → (open_time, close_time)
    hoops = hoops_df.copy()
    hoops_lookup = {}
    for _, row in hoops.iterrows():
        key = (str(row['ClientCode']), str(row['DayOfWeek']))
        hoops_lookup[key] = (str(row['Open_Time']).strip(), str(row['Close_Time']).strip())

    rows_to_drop = []
    for idx, row in df.iterrows():
        client = str(row.get('ClientCode', ''))
        day = str(row.get('Scheduled_Day', ''))
        key = (client, day)

        if key not in hoops_lookup:
            continue  # No HOOPS defined = no restriction

        open_t, close_t = hoops_lookup[key]
        sched_date = pd.to_datetime(row['Scheduled_Date']).date()

        # Parse open/close into datetimes on the scheduled date
        try:
            open_dt = datetime.combine(sched_date, datetime.strptime(open_t, "%H:%M").time())
            if close_t == '24:00':
                close_dt = datetime.combine(sched_date + timedelta(days=1), datetime.min.time())
            else:
                close_dt = datetime.combine(sched_date, datetime.strptime(close_t, "%H:%M").time())
                if close_dt <= open_dt:
                    close_dt += timedelta(days=1)
        except ValueError:
            continue

        shift_start = row['Start_DateTime']
        shift_end = row['End_DateTime']

        # If shift is entirely outside HOOPS → drop
        if shift_end <= open_dt or shift_start >= close_dt:
            rows_to_drop.append(idx)
            continue

        # Clamp shift to HOOPS window
        if shift_start < open_dt:
            df.at[idx, 'Start_DateTime'] = open_dt
        if shift_end > close_dt:
            df.at[idx, 'End_DateTime'] = close_dt

        # Recalculate shift length
        new_start = df.at[idx, 'Start_DateTime']
        new_end = df.at[idx, 'End_DateTime']
        df.at[idx, 'Shift_Length'] = (new_end - new_start).total_seconds()
        df.at[idx, 'ShiftMinutes'] = (new_end - new_start).total_seconds() / 60

    if rows_to_drop:
        df = df.drop(index=rows_to_drop).reset_index(drop=True)

    # Remove zero/negative length shifts from clamping
    df = df[df['Shift_Length'] > 0].reset_index(drop=True)

    # Clean up temp columns
    if temp_project:
        df = df.drop(columns=['ProjectID'], errors='ignore')
    if 'ClientCode_hoops' in df.columns:
        df = df.drop(columns=['ClientCode_hoops'], errors='ignore')

    return df


def _enforce_weekly_hours_cap(schedule_df, employees_df):
    """Remove shifts that would push part-time workers over their MaxWeeklyHours.

    Processes shifts in chronological order per member, dropping any shift
    that would exceed the cap.
    """
    if employees_df is None or 'MaxWeeklyHours' not in employees_df.columns:
        return schedule_df

    df = schedule_df.copy()
    df['Start_DateTime'] = pd.to_datetime(df['Start_DateTime'])

    # Build lookup: MemberID → MaxWeeklyHours
    emp = employees_df[['MemberID', 'MaxWeeklyHours']].dropna(subset=['MaxWeeklyHours']).copy()
    emp['MaxWeeklyHours'] = emp['MaxWeeklyHours'].astype(float)
    caps = dict(zip(emp['MemberID'], emp['MaxWeeklyHours']))

    if not caps:
        return schedule_df

    df = df.sort_values(['MemberID', 'Start_DateTime']).reset_index(drop=True)

    rows_to_drop = []
    accumulated = {}  # MemberID → total hours assigned so far

    for idx, row in df.iterrows():
        mid = row['MemberID']
        if mid not in caps:
            continue  # No cap for this member (full-time with no limit)

        cap = caps[mid]
        shift_hours = row.get('Shift_Length', 0) / 3600

        current = accumulated.get(mid, 0)
        if current + shift_hours > cap:
            rows_to_drop.append(idx)
        else:
            accumulated[mid] = current + shift_hours

    if rows_to_drop:
        df = df.drop(index=rows_to_drop).reset_index(drop=True)

    return df


def _apply_wotc_priority(schedule_df, employees_df):
    """Sort schedule so WOTC-eligible workers are scheduled first.

    This ensures that when there are capacity constraints (HOOPS, FTE caps),
    WOTC workers get priority. We sort the full DataFrame so WOTC=Y agents
    come first per day, then the weekly hours cap and HOOPS trim from the
    bottom (non-WOTC first to be dropped).
    """
    if employees_df is None or 'WOTC_Eligible' not in employees_df.columns:
        return schedule_df

    df = schedule_df.copy()

    wotc_map = employees_df[['MemberID', 'WOTC_Eligible']].drop_duplicates(subset='MemberID')
    if 'WOTC_Eligible' in df.columns:
        df = df.drop(columns=['WOTC_Eligible'])
    df = pd.merge(df, wotc_map, on='MemberID', how='left')
    df['WOTC_Eligible'] = df['WOTC_Eligible'].fillna('N')

    # Sort: WOTC=Y first (0 sorts before 1), then by Scheduled_Date, Start_DateTime
    df['_wotc_sort'] = df['WOTC_Eligible'].map({'Y': 0, 'N': 1}).fillna(1)
    df = df.sort_values(['Scheduled_Date', '_wotc_sort', 'Start_DateTime']).reset_index(drop=True)
    df = df.drop(columns=['_wotc_sort'], errors='ignore')

    return df


def run_scheduling_pipeline(
    employees_df,
    schedules_df,
    pto_df=None,
    clients_df=None,
    dept_client_map_df=None,
    training_df=None,
    rules_df=None,
    block_dates_df=None,
    overrides_df=None,
    hoops_df=None,
    existing_schedules_df=None,
    start_date=None,
    client_filter='ALL',
    max_round_robins=3,
    prioritize_wotc=True,
    progress_callback=None,
):
    """Run the full scheduling pipeline. Returns (final_df, log_messages).

    progress_callback: optional callable(step_number, total_steps, message)
    """
    log = []
    total_steps = 18

    def update(step, msg):
        log.append(msg)
        if progress_callback:
            progress_callback(step, total_steps, msg)

    if start_date is None:
        today = datetime.now().date()
        start_date = today - timedelta(days=today.weekday()) + timedelta(7)

    # --- Step 1: Merge employees + schedules ---
    update(1, "Loading employees and schedules...")
    emp = employees_df.copy()

    # Fill defaults for new columns
    if 'EmploymentType' not in emp.columns:
        emp['EmploymentType'] = 'Full-Time'
    if 'MaxWeeklyHours' not in emp.columns:
        emp['MaxWeeklyHours'] = None
    if 'WOTC_Eligible' not in emp.columns:
        emp['WOTC_Eligible'] = 'N'

    emp['EmploymentType'] = emp['EmploymentType'].fillna('Full-Time')
    emp['WOTC_Eligible'] = emp['WOTC_Eligible'].fillna('N')

    # Auto-set MaxWeeklyHours for part-time without explicit cap
    emp.loc[
        (emp['EmploymentType'] == 'Part-Time') & (emp['MaxWeeklyHours'].isna()),
        'MaxWeeklyHours'
    ] = 30  # default part-time cap

    ft_count = (emp['EmploymentType'] == 'Full-Time').sum()
    pt_count = (emp['EmploymentType'] == 'Part-Time').sum()
    wotc_count = (emp['WOTC_Eligible'] == 'Y').sum()
    update(1, f"Employees: {len(emp)} total ({ft_count} FT, {pt_count} PT, {wotc_count} WOTC)")

    # Filter active, WFM-eligible employees
    if 'TerminationDate' in emp.columns:
        emp = emp[emp['TerminationDate'].isna()].reset_index(drop=True)
    if 'WFMOverride' in emp.columns:
        emp = emp[emp['WFMOverride'] == 1].reset_index(drop=True)
    if 'WFMDoNotSchedule' in emp.columns:
        emp = emp[emp['WFMDoNotSchedule'] == 0].reset_index(drop=True)

    # Merge with schedules
    sched = schedules_df.copy()
    if 'Schedule' in sched.columns or any(c for c in sched.columns if '_Start' in c):
        schedule_merged = pd.merge(emp, sched, on='MemberID', how='inner', suffixes=('', '_sched'))
    else:
        schedule_merged = emp.copy()

    if schedule_merged.empty:
        update(1, "No eligible employees with schedules found.")
        return pd.DataFrame(), log

    update(1, f"Found {len(schedule_merged)} employee-schedule records.")

    # --- Step 2: Filter by client ---
    update(2, "Filtering by client...")
    if client_filter != 'ALL' and dept_client_map_df is not None and not dept_client_map_df.empty:
        dept_map = dept_client_map_df[dept_client_map_df['ClientCode'] == client_filter]
        schedule_merged = schedule_merged[
            schedule_merged['Department'].isin(dept_map['Department'])
        ].reset_index(drop=True)
        update(2, f"Filtered to {len(schedule_merged)} records for client {client_filter}.")
    else:
        update(2, f"Running for ALL clients. {len(schedule_merged)} records.")

    if schedule_merged.empty:
        return pd.DataFrame(), log

    # Ensure Name column exists
    if 'Name' not in schedule_merged.columns and 'FullName' in schedule_merged.columns:
        schedule_merged['Name'] = schedule_merged['FullName']

    # --- Step 3: Parse shifts ---
    update(3, "Parsing shift schedules...")
    metrics_df = generate_metrics(schedule_merged, start_date)
    if metrics_df.empty:
        update(3, "No shifts parsed from schedules.")
        return pd.DataFrame(), log
    update(3, f"Parsed {len(metrics_df)} shift entries.")

    # --- Step 4: Consolidate overnight shifts ---
    update(4, "Consolidating overnight shifts...")
    consolidated_df = consolidate_overnight_shifts(metrics_df)
    update(4, f"{len(consolidated_df)} shifts after consolidation.")

    # --- Step 5: Adjust Sunday shifts ---
    update(5, "Adjusting Sunday-to-Monday crossover shifts...")
    adjusted_df = adjust_sunday_shifts(consolidated_df)
    update(5, f"{len(adjusted_df)} shifts after Sunday adjustment.")

    # --- Step 6: WOTC priority sort ---
    update(6, "Applying WOTC priority sort...")
    if prioritize_wotc:
        adjusted_df = _apply_wotc_priority(adjusted_df, emp)
        wotc_counts = adjusted_df['WOTC_Eligible'].value_counts().to_dict() if 'WOTC_Eligible' in adjusted_df.columns else {}
        update(6, f"WOTC priority applied. WOTC: {wotc_counts.get('Y', 0)}, Non-WOTC: {wotc_counts.get('N', 0)}")
    else:
        update(6, "WOTC priority disabled.")

    # --- Step 7: Enforce Client HOOPS ---
    update(7, "Enforcing Client Hours of Operation (HOOPS)...")
    before_hoops = len(adjusted_df)
    adjusted_df = _enforce_client_hoops(adjusted_df, hoops_df, clients_df, training_df)
    trimmed = before_hoops - len(adjusted_df)
    update(7, f"HOOPS applied: {trimmed} shifts trimmed/removed. {len(adjusted_df)} remaining.")

    # --- Step 8: Exclude PTO ---
    update(8, "Checking PTO requests...")
    if pto_df is not None and not pto_df.empty:
        pto = pto_df.copy()
        pto = pto[pto['ApprovedStatus'] == 'Approved']
        if not pto.empty:
            pto['MemberID'] = pto['MemberID'].astype(int)
            pto['ScheduleDate'] = pd.to_datetime(pto['ScheduleDate']).dt.date
            pto_agg = pto.groupby(['MemberID', 'ScheduleDate']).agg(
                PTO_Mins=('PaidHours', lambda x: (x.sum() + pto.loc[x.index, 'UnpaidHours'].sum()) * 60)
            ).reset_index()
            pto_agg = pto_agg[pto_agg['PTO_Mins'] > 0]

            adjusted_df['MemberID'] = adjusted_df['MemberID'].astype(int)
            adjusted_df['_sched_date'] = pd.to_datetime(adjusted_df['Scheduled_Date']).dt.date
            before_count = len(adjusted_df)
            merged = adjusted_df.merge(pto_agg, left_on=['MemberID', '_sched_date'],
                                       right_on=['MemberID', 'ScheduleDate'], how='left')
            merged['PTO_Mins'] = merged['PTO_Mins'].fillna(0)
            adjusted_df = merged[merged['PTO_Mins'] == 0].drop(
                columns=['PTO_Mins', 'ScheduleDate', '_sched_date'], errors='ignore'
            ).reset_index(drop=True)
            excluded = before_count - len(adjusted_df)
            update(8, f"Excluded {excluded} shifts due to PTO. {len(adjusted_df)} remaining.")
        else:
            update(8, "No approved PTO found.")
    else:
        update(8, "No PTO data provided.")

    if adjusted_df.empty:
        return pd.DataFrame(), log

    # --- Step 9: Enforce weekly hours cap (part-time) ---
    update(9, "Enforcing weekly hours cap for part-time workers...")
    before_cap = len(adjusted_df)
    adjusted_df = _enforce_weekly_hours_cap(adjusted_df, emp)
    capped = before_cap - len(adjusted_df)
    update(9, f"Hours cap applied: {capped} shifts removed. {len(adjusted_df)} remaining.")

    # --- Step 10: Assign Lunch ---
    update(10, "Assigning lunch breaks...")
    lunch_df = assign_breaks(adjusted_df, rules_df, overrides_df, 'Lunch', max_round_robins)
    update(10, f"Lunch assigned to {len(lunch_df)} shifts.")

    # --- Step 11: Assign Break A ---
    update(11, "Assigning Break A...")
    break_a_df = assign_breaks(lunch_df, rules_df, overrides_df, 'BreakA', max_round_robins)
    update(11, f"Break A assigned to {len(break_a_df)} shifts.")

    # --- Step 12: Assign Break B ---
    update(12, "Assigning Break B...")
    break_b_df = assign_breaks(break_a_df, rules_df, overrides_df, 'BreakB', max_round_robins)
    update(12, f"Break B assigned to {len(break_b_df)} shifts.")

    # --- Step 13: Split overnight shifts ---
    update(13, "Splitting overnight shifts at midnight...")
    split_df = split_overnight_shifts(break_b_df)
    update(13, f"{len(split_df)} shifts after overnight split.")

    # --- Step 14: Attach training/client assignment ---
    update(14, "Assigning agent training/client...")
    if training_df is not None and not training_df.empty:
        train = training_df.copy()
        if 'Ranking' in train.columns:
            train = train[train['Ranking'] == 1]
        train = train[['MemberID', 'ProjectID', 'TypeID']].drop_duplicates()
        split_df = pd.merge(split_df, train, on='MemberID', how='left')
        split_df = split_df[split_df['ProjectID'].notna()].reset_index(drop=True)
        update(14, f"{len(split_df)} shifts with training assignment.")
    else:
        split_df['ProjectID'] = None
        split_df['TypeID'] = None
        update(14, "No training data provided. ProjectID not assigned.")

    # --- Step 14b: Enforce uniform shifts ---
    if clients_df is not None and 'UniformShift' in clients_df.columns:
        uniform = clients_df[clients_df['UniformShift'] == 'Y'].copy()
        if not uniform.empty and 'ProjectID' in split_df.columns:
            uniform['ProjectID'] = uniform['ProjectID'].astype(str)
            split_df['ProjectID'] = split_df['ProjectID'].astype(str)
            before = len(split_df)
            for _, uclient in uniform.iterrows():
                pid = str(uclient['ProjectID'])
                u_start = str(uclient.get('UniformStart', '')).strip()
                u_end = str(uclient.get('UniformEnd', '')).strip()
                if not u_start or not u_end:
                    continue
                mask = split_df['ProjectID'] == pid
                for idx in split_df[mask].index:
                    sched_date = pd.to_datetime(split_df.at[idx, 'Scheduled_Date']).date()
                    try:
                        new_start = datetime.combine(sched_date, datetime.strptime(u_start, "%H:%M").time())
                        if u_end == '24:00':
                            new_end = datetime.combine(sched_date + timedelta(days=1), datetime.min.time())
                        else:
                            new_end = datetime.combine(sched_date, datetime.strptime(u_end, "%H:%M").time())
                        if new_end <= new_start:
                            new_end += timedelta(days=1)
                    except ValueError:
                        continue
                    split_df.at[idx, 'Start_DateTime'] = new_start
                    split_df.at[idx, 'End_DateTime'] = new_end
                    split_df.at[idx, 'Shift_Length'] = (new_end - new_start).total_seconds()
                    split_df.at[idx, 'ShiftMinutes'] = (new_end - new_start).total_seconds() / 60
            affected = split_df[split_df['ProjectID'].isin(uniform['ProjectID'].tolist())]
            update(14, f"Uniform shifts applied to {len(affected)} shifts across {len(uniform)} clients.")

    # --- Step 15: Apply member overrides ---
    update(15, "Applying member overrides...")
    overridden_df = apply_member_overrides(split_df, overrides_df)
    update(15, f"{len(overridden_df)} shifts after overrides.")

    # --- Step 16: Check schedule overlaps ---
    update(16, "Checking for schedule overlaps...")
    checked_df = check_schedule_overlap(overridden_df, existing_schedules_df)
    update(16, f"{len(checked_df)} shifts after overlap check.")

    # --- Step 17: Apply client block dates ---
    update(17, "Applying client block dates...")
    blocked_df = apply_block_dates(checked_df, block_dates_df, clients_df)
    blocked_df = handle_midnight_block_dates(blocked_df)
    update(17, f"{len(blocked_df)} shifts after block date check.")

    # --- Step 18: Final filter ---
    update(18, "Finalizing schedule...")
    final_df = filter_final_schedule(blocked_df)

    # Add clientCode if clients data available
    if clients_df is not None and not clients_df.empty and 'ProjectID' in final_df.columns:
        client_map = clients_df[['ProjectID', 'ClientCode']].drop_duplicates()
        client_map['ProjectID'] = client_map['ProjectID'].astype(str)
        final_df['ProjectID'] = final_df['ProjectID'].astype(str)
        if 'ClientCode' in final_df.columns:
            final_df = final_df.drop(columns=['ClientCode'])
        final_df = pd.merge(final_df, client_map, on='ProjectID', how='left')

    # Add employment info to output
    emp_info = emp[['MemberID', 'EmploymentType', 'WOTC_Eligible']].drop_duplicates(subset='MemberID')
    for col in ['EmploymentType', 'WOTC_Eligible']:
        if col in final_df.columns:
            final_df = final_df.drop(columns=[col])
    final_df = pd.merge(final_df, emp_info, on='MemberID', how='left')

    # Select and order output columns
    output_cols = [
        'MemberID', 'Name', 'Department', 'EmploymentType', 'WOTC_Eligible',
        'ProjectID', 'ClientCode', 'TypeID',
        'Scheduled_Date', 'Scheduled_Day',
        'Start_DateTime', 'End_DateTime', 'Shift_Length', 'ShiftMinutes',
        'Lunch_Option', 'Lunch_Start_DateTime', 'Lunch_End_DateTime', 'Lunch_Seconds',
        'BreakA_Option', 'BreakA_Start_DateTime', 'BreakA_End_DateTime', 'BreakA_Seconds',
        'BreakB_Option', 'BreakB_Start_DateTime', 'BreakB_End_DateTime', 'BreakB_Seconds',
        'Overnight',
    ]
    available_cols = [c for c in output_cols if c in final_df.columns]
    final_df = final_df[available_cols].reset_index(drop=True)

    update(18, f"Schedule complete: {len(final_df)} total shifts generated.")
    return final_df, log
