import pandas as pd
import numpy as np
from datetime import timedelta


def apply_member_overrides(agent_df, overrides_df):
    """Apply member-level overrides for breaks and full schedule."""
    if overrides_df is None or overrides_df.empty:
        return agent_df

    df = pd.merge(agent_df, overrides_df[['MemberID', 'Override_breakA', 'Override_breakB',
                                           'Override_Lunch', 'Override_FullSchedule']].drop_duplicates(),
                  on='MemberID', how='left')

    for col in ['Override_breakA', 'Override_breakB', 'Override_Lunch', 'Override_FullSchedule']:
        if col in df.columns:
            df[col] = df[col].fillna('N')

    # Zero out breaks where override is set
    if 'Override_Lunch' in df.columns:
        df['Lunch_Option'] = np.where(df['Override_Lunch'] == 'Y', 'N', df.get('Lunch_Option', 'N'))
        df['Lunch_Seconds'] = np.where(df['Override_Lunch'] == 'Y', 0, df.get('Lunch_Seconds', 0))
    if 'Override_breakA' in df.columns:
        df['BreakA_Option'] = np.where(df['Override_breakA'] == 'Y', 'N', df.get('BreakA_Option', 'N'))
        df['BreakA_Seconds'] = np.where(df['Override_breakA'] == 'Y', 0, df.get('BreakA_Seconds', 0))
    if 'Override_breakB' in df.columns:
        df['BreakB_Option'] = np.where(df['Override_breakB'] == 'Y', 'N', df.get('BreakB_Option', 'N'))
        df['BreakB_Seconds'] = np.where(df['Override_breakB'] == 'Y', 0, df.get('BreakB_Seconds', 0))

    # Remove fully overridden schedules
    if 'Override_FullSchedule' in df.columns:
        df = df[df['Override_FullSchedule'] != 'Y'].reset_index(drop=True)

    df = df.drop(columns=['Override_breakA', 'Override_breakB', 'Override_Lunch', 'Override_FullSchedule'],
                 errors='ignore')
    return df


def split_overnight_shifts(all_assigned_df):
    """Split overnight shifts at midnight into two parts, allocating breaks correctly."""
    if all_assigned_df.empty:
        return all_assigned_df

    df = all_assigned_df.copy()
    datetime_cols = ['Start_DateTime', 'End_DateTime',
                     'Lunch_Start_DateTime', 'Lunch_End_DateTime',
                     'BreakA_Start_DateTime', 'BreakA_End_DateTime',
                     'BreakB_Start_DateTime', 'BreakB_End_DateTime']
    for col in datetime_cols:
        if col in df.columns:
            df[col] = pd.to_datetime(df[col], errors='coerce')

    split_data = []
    for _, row in df.iterrows():
        if row.get('Overnight', 'N') == 'Y':
            split_time = (row['Start_DateTime'] + pd.DateOffset(days=1)).normalize()

            first_part = row.copy()
            first_part['End_DateTime'] = split_time
            first_part['Shift_Length'] = (split_time - row['Start_DateTime']).total_seconds()
            first_part['ShiftMinutes'] = first_part['Shift_Length'] / 60

            second_part = row.copy()
            second_part['Start_DateTime'] = split_time
            second_part['End_DateTime'] = row['End_DateTime']
            second_part['Shift_Length'] = (row['End_DateTime'] - split_time).total_seconds()
            second_part['ShiftMinutes'] = second_part['Shift_Length'] / 60
            second_part['Scheduled_Date'] = (pd.Timestamp(row['Scheduled_Date']) + pd.DateOffset(days=1)).strftime('%Y-%m-%d')
            second_part['Scheduled_Day'] = (pd.Timestamp(row['Scheduled_Date']) + pd.DateOffset(days=1)).day_name()

            # Allocate breaks to the correct part
            for break_prefix in ['Lunch', 'BreakA', 'BreakB']:
                start_col = f'{break_prefix}_Start_DateTime'
                end_col = f'{break_prefix}_End_DateTime'
                sec_col = f'{break_prefix}_Seconds'

                if start_col in row and pd.notna(row[start_col]):
                    break_dt = row[start_col]
                    if break_dt < split_time:
                        # Break belongs to first part
                        second_part[start_col] = pd.NaT
                        second_part[end_col] = pd.NaT
                        second_part[sec_col] = 0
                    else:
                        # Break belongs to second part
                        first_part[start_col] = pd.NaT
                        first_part[end_col] = pd.NaT
                        first_part[sec_col] = 0

            split_data.append(first_part)
            split_data.append(second_part)
        else:
            split_data.append(row)

    return pd.DataFrame(split_data).reset_index(drop=True)


def check_schedule_overlap(new_df, existing_df):
    """Check new schedules against existing ones, removing exact matches and overlaps.

    If existing_df is None or empty, returns new_df unchanged.
    """
    if existing_df is None or existing_df.empty:
        return new_df

    df1 = new_df.copy()
    df2 = existing_df.copy()

    df1['Start_DateTime'] = pd.to_datetime(df1['Start_DateTime'])
    df1['End_DateTime'] = pd.to_datetime(df1['End_DateTime'])
    df1['Duration'] = df1['End_DateTime'] - df1['Start_DateTime']

    # Determine column names in existing schedule
    shift_start_col = 'ShiftStart' if 'ShiftStart' in df2.columns else 'Start_DateTime'
    shift_stop_col = 'ShiftStop' if 'ShiftStop' in df2.columns else 'End_DateTime'

    df2[shift_start_col] = pd.to_datetime(df2[shift_start_col])
    df2[shift_stop_col] = pd.to_datetime(df2[shift_stop_col])
    df2['Duration'] = df2[shift_stop_col] - df2[shift_start_col]

    rows_to_drop = []
    for member_id in df1['MemberID'].unique():
        df1_member = df1[df1['MemberID'] == member_id]
        df2_member = df2[df2['MemberID'] == member_id]

        for idx1, row1 in df1_member.iterrows():
            start1 = row1['Start_DateTime']
            end1 = row1['End_DateTime']
            date1 = start1.date()

            for _, row2 in df2_member.iterrows():
                start2 = row2[shift_start_col]
                end2 = row2[shift_stop_col]
                date2 = start2.date()

                if date1 == date2:
                    # Exact match
                    if start1 == start2 and end1 == end2:
                        rows_to_drop.append(idx1)
                        break
                    # Overlap
                    if start1 < end2 and end1 > start2:
                        rows_to_drop.append(idx1)
                        break

    df1 = df1.drop(index=rows_to_drop).reset_index(drop=True)
    df1 = df1.drop(columns=['Duration'], errors='ignore')
    return df1


def apply_block_dates(schedules_df, block_dates_df, clients_df):
    """Mark schedules on blocked client dates."""
    if block_dates_df is None or block_dates_df.empty:
        return schedules_df

    df = schedules_df.copy()
    block = block_dates_df.copy()

    # Map ClientCode to ProjectID if clients provided
    if clients_df is not None and not clients_df.empty:
        block = pd.merge(block, clients_df[['ProjectID', 'ClientCode']].drop_duplicates(),
                         on='ClientCode', how='left')
    else:
        block['ProjectID'] = None

    block = block.rename(columns={'Date_Blocked': 'Scheduled_Date'})
    block['Block_Date'] = 'Y'
    block['Scheduled_Date'] = block['Scheduled_Date'].astype(str)
    block['ProjectID'] = block['ProjectID'].fillna(0).astype(str)

    df['Scheduled_Date'] = df['Scheduled_Date'].astype(str)
    df['ProjectID'] = df['ProjectID'].fillna(0).astype(str)

    block_subset = block[['Scheduled_Date', 'ProjectID', 'Block_Date']].drop_duplicates()
    df = pd.merge(df, block_subset, on=['Scheduled_Date', 'ProjectID'], how='left')
    df['Block_Date'] = df['Block_Date'].fillna('N')

    return df


def handle_midnight_block_dates(schedules_df):
    """Remove adjacent midnight-split rows when one part is blocked."""
    if schedules_df.empty or 'Block_Date' not in schedules_df.columns:
        return schedules_df

    df = schedules_df.copy()
    df['Start_DateTime'] = pd.to_datetime(df['Start_DateTime'])
    df['End_DateTime'] = pd.to_datetime(df['End_DateTime'])
    df['Scheduled_Date'] = pd.to_datetime(df['Scheduled_Date'])
    df = df.sort_values(by=['MemberID', 'Scheduled_Date', 'Start_DateTime'])

    rows_to_remove = []
    for member_id in df['MemberID'].unique():
        group = df[df['MemberID'] == member_id].copy()
        for i in range(len(group)):
            current = group.iloc[i]
            if current.get('Block_Date') == 'Y':
                # Check next row
                if i + 1 < len(group):
                    next_row = group.iloc[i + 1]
                    if next_row['End_DateTime'].strftime('%H:%M:%S') == '00:00:00':
                        rows_to_remove.append(next_row.name)
                # Check row after next
                if i + 2 < len(group):
                    after_next = group.iloc[i + 2]
                    if after_next['Start_DateTime'].strftime('%H:%M:%S') == '00:00:00':
                        rows_to_remove.append(after_next.name)

    if rows_to_remove:
        df = df.drop(index=rows_to_remove).reset_index(drop=True)
    return df


def filter_final_schedule(schedules_df):
    """Remove blocked rows and invalid ProjectID rows."""
    df = schedules_df.copy()

    if 'Block_Date' in df.columns:
        df = df[df['Block_Date'] != 'Y'].reset_index(drop=True)

    if 'ProjectID' in df.columns:
        df['ProjectID'] = df['ProjectID'].fillna(0).astype(str)
        df = df[df['ProjectID'] != '0'].reset_index(drop=True)
        df = df[df['ProjectID'] != '0.0'].reset_index(drop=True)

    # Remove zero-length shifts
    if 'Shift_Length' in df.columns:
        df = df[df['Shift_Length'] > 0].reset_index(drop=True)
    elif 'Start_DateTime' in df.columns and 'End_DateTime' in df.columns:
        df['Start_DateTime'] = pd.to_datetime(df['Start_DateTime'])
        df['End_DateTime'] = pd.to_datetime(df['End_DateTime'])
        df = df[df['Start_DateTime'] != df['End_DateTime']].reset_index(drop=True)

    # Zero out break seconds where option is N
    for prefix in ['Lunch', 'BreakA', 'BreakB']:
        opt_col = f'{prefix}_Option'
        sec_col = f'{prefix}_Seconds'
        if opt_col in df.columns and sec_col in df.columns:
            df[sec_col] = np.where(df[opt_col] == 'N', 0, df[sec_col])

    return df
