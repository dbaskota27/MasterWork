import pandas as pd
import numpy as np
import json
from datetime import datetime, timedelta
from utils import convert_time_to_datetime


def calculate_shift_metrics(member_id, name, department, start_date, day_name, shift):
    """Calculate shift metrics from a single shift entry [start_time, end_time]."""
    start_time, end_time = shift
    start_datetime = convert_time_to_datetime(start_date, start_time)
    end_datetime = convert_time_to_datetime(start_date, end_time)

    if start_datetime is None or end_datetime is None:
        return None

    scheduled_datetime = datetime.strptime(start_date, "%Y-%m-%d")
    start_seconds = (start_datetime - scheduled_datetime).total_seconds()
    end_seconds = (end_datetime - scheduled_datetime).total_seconds()

    if end_datetime < start_datetime:
        end_datetime += timedelta(days=1)

    shift_length = (end_datetime - start_datetime).total_seconds()
    shift_minutes = shift_length / 60

    return {
        'MemberID': member_id,
        'Name': name,
        'Department': department,
        'Scheduled_Date': start_date,
        'Scheduled_Day': day_name,
        'Start_Time': start_time,
        'End_Time': end_time,
        'Start_DateTime': start_datetime,
        'End_DateTime': end_datetime,
        'Shift_Length': shift_length,
        'Start': start_seconds,
        'End': end_seconds,
        'ShiftMinutes': shift_minutes,
    }


def find_monday(date_obj):
    """Find the Monday of the week for a given date."""
    return date_obj - timedelta(days=date_obj.weekday())


def parse_schedule_json(schedule):
    """Ensure Schedule column is in dictionary format."""
    if isinstance(schedule, str):
        try:
            return json.loads(schedule)
        except (json.JSONDecodeError, ValueError):
            return {}
    elif isinstance(schedule, dict):
        return schedule
    return {}


def generate_metrics(schedule_df, reference_date):
    """Parse schedule JSON into flat shift rows for the target week.

    Supports two schedule formats:
    1. JSON dict: {"Monday": [["08:00","17:00"]], ...}
    2. Column-based: Monday_Start, Monday_End, Tuesday_Start, ...
    """
    all_metrics = []
    days_of_week = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    if isinstance(reference_date, str):
        reference_date = datetime.strptime(reference_date, "%Y-%m-%d").date()
    start_of_week = find_monday(reference_date)

    # Detect format: JSON-based vs column-based
    has_schedule_col = 'Schedule' in schedule_df.columns
    has_day_cols = any(f'{d}_Start' in schedule_df.columns for d in days_of_week)

    if has_schedule_col:
        schedule_df = schedule_df.copy()
        schedule_df['Schedule'] = schedule_df['Schedule'].apply(parse_schedule_json)

        for _, row in schedule_df.iterrows():
            member_id = row['MemberID']
            name = row.get('Name', row.get('FullName', ''))
            department = row.get('Department', '')
            weekly_schedule = row['Schedule']

            if not isinstance(weekly_schedule, dict):
                continue

            for day_index, day_name in enumerate(days_of_week):
                if day_name in weekly_schedule:
                    shifts = weekly_schedule[day_name]
                    if not isinstance(shifts, list):
                        continue
                    date_str = (start_of_week + timedelta(days=day_index)).strftime("%Y-%m-%d")
                    for shift in shifts:
                        if not isinstance(shift, list) or len(shift) != 2:
                            continue
                        metrics = calculate_shift_metrics(member_id, name, department, date_str, day_name, shift)
                        if metrics:
                            all_metrics.append(metrics)

    elif has_day_cols:
        for _, row in schedule_df.iterrows():
            member_id = row['MemberID']
            name = row.get('Name', row.get('FullName', ''))
            department = row.get('Department', '')

            for day_index, day_name in enumerate(days_of_week):
                start_col = f'{day_name}_Start'
                end_col = f'{day_name}_End'
                if start_col in row and end_col in row:
                    start_time = row[start_col]
                    end_time = row[end_col]
                    if pd.notna(start_time) and pd.notna(end_time) and str(start_time).strip() and str(end_time).strip():
                        date_str = (start_of_week + timedelta(days=day_index)).strftime("%Y-%m-%d")
                        shift = [str(start_time).strip(), str(end_time).strip()]
                        metrics = calculate_shift_metrics(member_id, name, department, date_str, day_name, shift)
                        if metrics:
                            all_metrics.append(metrics)

    if not all_metrics:
        return pd.DataFrame()
    return pd.DataFrame(all_metrics)


def consolidate_overnight_shifts(metrics_df):
    """Merge adjacent shifts where one ends at 24:00 and next starts at 00:00."""
    if metrics_df.empty:
        return metrics_df

    df = metrics_df.copy()
    df['Start_DateTime'] = pd.to_datetime(df['Start_DateTime'])
    df['End_DateTime'] = pd.to_datetime(df['End_DateTime'])
    df['Scheduled_DateTime'] = pd.to_datetime(df['Scheduled_Date'])
    df.sort_values(by=['MemberID', 'Start_DateTime'], inplace=True)

    consolidated_shifts = []

    for member_id, group in df.groupby('MemberID'):
        prev_row = None
        for _, row in group.iterrows():
            if prev_row is not None:
                if prev_row['End_Time'] == '24:00' and row['Start_Time'] == '00:00':
                    consolidated_shifts.append({
                        'MemberID': member_id,
                        'Name': prev_row['Name'],
                        'Department': prev_row['Department'],
                        'Scheduled_Date': prev_row['Scheduled_Date'],
                        'Scheduled_Day': prev_row['Scheduled_Day'],
                        'Start_DateTime': prev_row['Start_DateTime'],
                        'End_DateTime': row['End_DateTime'],
                        'Shift_Length': (row['End_DateTime'] - prev_row['Start_DateTime']).total_seconds(),
                        'ShiftMinutes': (row['End_DateTime'] - prev_row['Start_DateTime']).total_seconds() / 60,
                        'Start': (prev_row['Start_DateTime'] - prev_row['Scheduled_DateTime']).total_seconds(),
                        'End': (row['End_DateTime'] - prev_row['Scheduled_DateTime']).total_seconds(),
                        'Overnight': 'Y',
                    })
                    prev_row = None
                else:
                    overnight = 'Y' if prev_row['Start_DateTime'].date() != prev_row['End_DateTime'].date() else 'N'
                    consolidated_shifts.append({
                        'MemberID': member_id,
                        'Name': prev_row['Name'],
                        'Department': prev_row['Department'],
                        'Scheduled_Date': prev_row['Scheduled_Date'],
                        'Scheduled_Day': prev_row['Scheduled_Day'],
                        'Start_DateTime': prev_row['Start_DateTime'],
                        'End_DateTime': prev_row['End_DateTime'],
                        'Shift_Length': (prev_row['End_DateTime'] - prev_row['Start_DateTime']).total_seconds(),
                        'ShiftMinutes': (prev_row['End_DateTime'] - prev_row['Start_DateTime']).total_seconds() / 60,
                        'Start': (prev_row['Start_DateTime'] - prev_row['Scheduled_DateTime']).total_seconds(),
                        'End': (prev_row['End_DateTime'] - prev_row['Scheduled_DateTime']).total_seconds(),
                        'Overnight': overnight,
                    })
                    prev_row = row
            else:
                prev_row = row

        if prev_row is not None:
            overnight = 'Y' if prev_row['Start_DateTime'].date() != prev_row['End_DateTime'].date() else 'N'
            consolidated_shifts.append({
                'MemberID': member_id,
                'Name': prev_row['Name'],
                'Department': prev_row['Department'],
                'Scheduled_Date': prev_row['Scheduled_Date'],
                'Scheduled_Day': prev_row['Scheduled_Day'],
                'Start_DateTime': prev_row['Start_DateTime'],
                'End_DateTime': prev_row['End_DateTime'],
                'Shift_Length': (prev_row['End_DateTime'] - prev_row['Start_DateTime']).total_seconds(),
                'ShiftMinutes': (prev_row['End_DateTime'] - prev_row['Start_DateTime']).total_seconds() / 60,
                'Start': (prev_row['Start_DateTime'] - prev_row['Scheduled_DateTime']).total_seconds(),
                'End': (prev_row['End_DateTime'] - prev_row['Scheduled_DateTime']).total_seconds(),
                'Overnight': overnight,
            })

    return pd.DataFrame(consolidated_shifts)


def adjust_sunday_shifts(consolidated_df):
    """Fix Sunday shifts that continue into Monday."""
    if consolidated_df.empty:
        return consolidated_df

    df = consolidated_df.copy()
    df['Start_DateTime'] = pd.to_datetime(df['Start_DateTime'])
    df['End_DateTime'] = pd.to_datetime(df['End_DateTime'])

    sunday_shift = df[(df['Scheduled_Day'] == 'Sunday') & (df['End_DateTime'].dt.weekday == 0)]

    for idx, shift in sunday_shift.iterrows():
        member_id = shift['MemberID']
        monday_shift = df[
            (df['MemberID'] == member_id)
            & (df['Scheduled_Day'] == 'Monday')
            & (df['Start_DateTime'].dt.time == datetime.strptime("00:00:00", "%H:%M:%S").time())
        ]
        if not monday_shift.empty:
            monday_end_time = monday_shift.iloc[0]['End_DateTime'].time()
            new_end = shift['End_DateTime'].replace(
                hour=monday_end_time.hour,
                minute=monday_end_time.minute,
                second=monday_end_time.second,
                microsecond=0,
            )
            df.at[idx, 'End_DateTime'] = new_end
            df.at[idx, 'Shift_Length'] = (new_end - shift['Start_DateTime']).total_seconds()
            df.at[idx, 'ShiftMinutes'] = (new_end - shift['Start_DateTime']).total_seconds() / 60

    return df
