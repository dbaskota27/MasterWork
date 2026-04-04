import pandas as pd
import numpy as np
from datetime import timedelta
from utils import round_to_nearest_interval


def _generate_break_start(start_dt, end_dt, start_window, end_window,
                           break_option, overnight_flag, break_duration,
                           round_robin_list, max_round_robins):
    """Generic break/lunch time placement within a shift window.

    Returns (break_start_datetime, break_end_datetime) or (None, None).
    """
    if break_option == 'N':
        return None, None

    shift_duration = (end_dt - start_dt).total_seconds()
    if shift_duration <= 0:
        return None, None

    start_seconds = start_window * (shift_duration / 100)
    end_seconds = end_window * (shift_duration / 100)

    window_start = start_dt + timedelta(seconds=start_seconds)
    window_end = start_dt + timedelta(seconds=end_seconds)

    duration_seconds = break_duration * 60

    # Expand window if too narrow
    if (end_seconds - duration_seconds - start_seconds) < 0:
        start_seconds = start_seconds - 900
        if (end_seconds - duration_seconds - start_seconds) < 0:
            end_seconds = end_seconds + 900

    low = int(start_seconds)
    high = int(end_seconds - duration_seconds)
    if high <= low:
        high = low + 1

    break_start_seconds = np.random.randint(low, high)
    break_start = start_dt + timedelta(seconds=break_start_seconds)
    break_end = break_start + timedelta(minutes=break_duration)

    # Adjust if break exceeds window
    if break_end > window_end:
        break_start = window_end - timedelta(minutes=break_duration)
        break_end = window_end

    # Collision handling via round-robin
    break_start_secs = int((break_start - start_dt).total_seconds())
    attempts = 0
    while break_start_secs in round_robin_list and attempts < 10:
        break_start_secs = (break_start_secs + 900) % 86400
        break_start = start_dt + timedelta(seconds=break_start_secs)
        break_end = break_start + timedelta(minutes=break_duration)
        if break_end > window_end:
            break
        attempts += 1

    round_robin_list.append(break_start_secs)
    if len(round_robin_list) > max_round_robins:
        round_robin_list.pop(0)

    # Round to nearest interval
    break_start = round_to_nearest_interval(break_start, overnight_flag)
    break_end = break_start + timedelta(minutes=break_duration)

    # Final boundary check
    if break_start < window_start:
        break_start = window_start
        break_end = break_start + timedelta(minutes=break_duration)
    if break_end > window_end:
        break_end = window_end
        break_start = break_end - timedelta(minutes=break_duration)

    break_start = round_to_nearest_interval(break_start, overnight_flag)
    break_end = break_start + timedelta(minutes=break_duration)

    return break_start, break_end


def assign_breaks(schedule_df, rules_df, overrides_df, break_type, max_round_robins=3):
    """Assign lunch or breaks to all agents.

    break_type: 'Lunch', 'BreakA', or 'BreakB'
    rules_df: break_lunch_rules with columns for this break type
    overrides_df: member_overrides (optional)

    Returns DataFrame with new columns: {break_type}_Start_DateTime, {break_type}_End_DateTime, {break_type}_Seconds
    """
    df = schedule_df.copy()

    # Map break_type to rule columns
    if break_type == 'Lunch':
        option_col = 'Lunch_Option'
        start_window_col = 'Lunch_start_window'
        end_window_col = 'Lunch_end_window'
        expected_time_col = 'Expected_Lunch_Time'
        default_duration = 30
        override_duration_flag = 'Lunch_Duration'
        override_duration_min = 'Lunch_Duration_Min'
    elif break_type == 'BreakA':
        option_col = 'BreakA_Option'
        start_window_col = 'BreakA_Start'
        end_window_col = 'BreakA_End'
        expected_time_col = 'Expected_BreakA_Time'
        default_duration = 15
        override_duration_flag = 'breakA_Duration'
        override_duration_min = 'breakA_Duration_Min'
    elif break_type == 'BreakB':
        option_col = 'BreakB_Option'
        start_window_col = 'BreakB_Start'
        end_window_col = 'BreakB_End'
        expected_time_col = 'Expected_BreakB_Time'
        default_duration = 15
        override_duration_flag = 'breakB_Duration'
        override_duration_min = 'breakB_Duration_Min'
    else:
        raise ValueError(f"Unknown break_type: {break_type}")

    # Build rules lookup: ShiftMinutes -> (start_window, end_window, option, expected_time)
    if rules_df is not None and not rules_df.empty:
        rules = rules_df.copy()
        rules['ShiftMinutes'] = rules['Shift_Length_hrs'] * 60

        # For Lunch, the start window is always 48% (as in notebook)
        if break_type == 'Lunch':
            if 'Lunch_start_window' not in rules.columns:
                rules['Lunch_start_window'] = 48
            if 'Lunch_end_window' not in rules.columns:
                rules['Lunch_end_window'] = rules.get('Lunch_end_window', 70)
            rules['Expected_Lunch_Time'] = np.where(
                rules[option_col] == 'Y', default_duration, 0
            )
            if expected_time_col not in rules.columns:
                rules[expected_time_col] = default_duration

        merge_cols = ['ShiftMinutes']
        keep_cols = [c for c in [option_col, start_window_col, end_window_col, expected_time_col, 'ShiftMinutes']
                     if c in rules.columns]
        rules_subset = rules[keep_cols].drop_duplicates()

        df = pd.merge(df, rules_subset, how='left', on='ShiftMinutes')

    # Fill defaults
    if option_col not in df.columns:
        df[option_col] = 'N'
    if start_window_col not in df.columns:
        df[start_window_col] = 48 if break_type == 'Lunch' else 0
    if end_window_col not in df.columns:
        df[end_window_col] = 70
    if expected_time_col not in df.columns:
        df[expected_time_col] = default_duration

    df[option_col] = df[option_col].fillna('N')
    df[start_window_col] = df[start_window_col].fillna(0)
    df[end_window_col] = df[end_window_col].fillna(70)
    df[expected_time_col] = df[expected_time_col].fillna(default_duration)

    # Apply member overrides for duration
    if overrides_df is not None and not overrides_df.empty:
        if override_duration_flag in overrides_df.columns and override_duration_min in overrides_df.columns:
            duration_overrides = overrides_df[
                overrides_df[override_duration_flag] == 'Y'
            ][['MemberID', override_duration_flag, override_duration_min]].copy()
            if not duration_overrides.empty:
                df = pd.merge(df, duration_overrides, on='MemberID', how='left')
                df[override_duration_flag] = df[override_duration_flag].fillna('N')
                df[expected_time_col] = np.where(
                    df[override_duration_flag] == 'Y',
                    df[override_duration_min],
                    df[expected_time_col],
                )
                df = df.drop(columns=[override_duration_flag, override_duration_min], errors='ignore')

    df[expected_time_col] = df[expected_time_col].fillna(default_duration).astype(int)

    # Assign breaks
    round_robin_list = []
    start_col = f'{break_type}_Start_DateTime'
    end_col = f'{break_type}_End_DateTime'
    seconds_col = f'{break_type}_Seconds'

    starts = []
    ends = []
    secs = []

    for _, row in df.iterrows():
        bs, be = _generate_break_start(
            row['Start_DateTime'], row['End_DateTime'],
            row[start_window_col], row[end_window_col],
            row[option_col], row.get('Overnight', 'N'),
            row[expected_time_col], round_robin_list, max_round_robins,
        )
        if bs and be:
            secs.append((be - bs).total_seconds())
        else:
            secs.append(0)
        starts.append(bs)
        ends.append(be)

    df[start_col] = starts
    df[end_col] = ends
    df[seconds_col] = secs
    df[f'{break_type}_Option'] = df[option_col]

    # Clean up intermediate rule columns
    drop_cols = [c for c in [start_window_col, end_window_col, expected_time_col]
                 if c in df.columns and c not in schedule_df.columns]
    df = df.drop(columns=drop_cols, errors='ignore')

    return df
