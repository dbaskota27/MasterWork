"""Generate sample Excel templates with example data for testing."""
import pandas as pd
import json
import os

TEMPLATES_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "templates")
os.makedirs(TEMPLATES_DIR, exist_ok=True)


def generate_all_templates():
    # 1. Employees
    employees = pd.DataFrame({
        'MemberID': [101, 102, 103, 104, 105, 106, 107, 108],
        'FullName': ['Alice Johnson', 'Bob Smith', 'Carol Davis', 'Dan Wilson',
                     'Eva Martinez', 'Frank Lee', 'Grace Kim', 'Henry Brown'],
        'Department': ['Support', 'Support', 'Sales', 'Sales',
                       'Support', 'Tech', 'Tech', 'Support'],
        'TerminationDate': [None, None, None, None, None, None, None, None],
        'WFMOverride': [1, 1, 1, 1, 1, 1, 1, 1],
        'WFMDoNotSchedule': [0, 0, 0, 0, 0, 0, 0, 0],
    })
    employees.to_excel(os.path.join(TEMPLATES_DIR, "employees.xlsx"), index=False)

    # 2. Schedules (JSON format)
    schedules_data = []
    default_schedules = [
        {"Monday": [["08:00", "17:00"]], "Tuesday": [["08:00", "17:00"]], "Wednesday": [["08:00", "17:00"]],
         "Thursday": [["08:00", "17:00"]], "Friday": [["08:00", "17:00"]]},
        {"Monday": [["09:00", "18:00"]], "Tuesday": [["09:00", "18:00"]], "Wednesday": [["09:00", "18:00"]],
         "Thursday": [["09:00", "18:00"]], "Friday": [["09:00", "18:00"]]},
        {"Monday": [["07:00", "16:00"]], "Tuesday": [["07:00", "16:00"]], "Wednesday": [["07:00", "16:00"]],
         "Thursday": [["07:00", "16:00"]], "Friday": [["07:00", "16:00"]], "Saturday": [["08:00", "12:00"]]},
        {"Monday": [["10:00", "19:00"]], "Tuesday": [["10:00", "19:00"]], "Wednesday": [["10:00", "19:00"]],
         "Thursday": [["10:00", "19:00"]], "Friday": [["10:00", "19:00"]]},
        {"Monday": [["06:00", "15:00"]], "Tuesday": [["06:00", "15:00"]], "Wednesday": [["06:00", "15:00"]],
         "Thursday": [["06:00", "15:00"]], "Friday": [["06:00", "15:00"]]},
        {"Monday": [["14:00", "23:00"]], "Tuesday": [["14:00", "23:00"]], "Wednesday": [["14:00", "23:00"]],
         "Thursday": [["14:00", "23:00"]], "Friday": [["14:00", "23:00"]]},
        {"Monday": [["22:00", "24:00"], ["00:00", "06:00"]], "Tuesday": [["22:00", "24:00"], ["00:00", "06:00"]],
         "Wednesday": [["22:00", "24:00"], ["00:00", "06:00"]], "Thursday": [["22:00", "24:00"], ["00:00", "06:00"]]},
        {"Monday": [["08:00", "17:00"]], "Tuesday": [["08:00", "17:00"]], "Wednesday": [["08:00", "17:00"]],
         "Thursday": [["08:00", "17:00"]], "Friday": [["08:00", "12:00"]]},
    ]
    for mid, sched in zip([101, 102, 103, 104, 105, 106, 107, 108], default_schedules):
        schedules_data.append({'MemberID': mid, 'Schedule': json.dumps(sched)})

    schedules = pd.DataFrame(schedules_data)
    schedules.to_excel(os.path.join(TEMPLATES_DIR, "schedules.xlsx"), index=False)

    # 3. PTO Requests
    pto = pd.DataFrame({
        'MemberID': [102, 105],
        'ScheduleDate': ['2026-04-07', '2026-04-09'],
        'PaidHours': [8, 4],
        'UnpaidHours': [0, 0],
        'ApprovedStatus': ['Approved', 'Approved'],
    })
    pto.to_excel(os.path.join(TEMPLATES_DIR, "pto_requests.xlsx"), index=False)

    # 4. Clients
    clients = pd.DataFrame({
        'ProjectID': [10, 20, 30],
        'ClientCode': ['ACME', 'GLOBEX', 'INITECH'],
        'ClientName': ['Acme Corp', 'Globex Inc', 'Initech LLC'],
        'Active': [1, 1, 1],
    })
    clients.to_excel(os.path.join(TEMPLATES_DIR, "clients.xlsx"), index=False)

    # 5. Department-Client Mapping
    dept_map = pd.DataFrame({
        'Department': ['Support', 'Sales', 'Tech'],
        'ClientCode': ['ACME', 'GLOBEX', 'INITECH'],
    })
    dept_map.to_excel(os.path.join(TEMPLATES_DIR, "dept_client_map.xlsx"), index=False)

    # 6. Agent Training
    training = pd.DataFrame({
        'MemberID': [101, 102, 103, 104, 105, 106, 107, 108],
        'ProjectID': [10, 10, 20, 20, 10, 30, 30, 10],
        'TypeID': [1, 1, 1, 1, 1, 1, 1, 1],
        'Ranking': [1, 1, 1, 1, 1, 1, 1, 1],
    })
    training.to_excel(os.path.join(TEMPLATES_DIR, "agent_training.xlsx"), index=False)

    # 7. Break/Lunch Rules
    rules = pd.DataFrame({
        'Shift_Length_hrs': [4, 5, 6, 7, 8, 9, 10],
        'Lunch_Option': ['N', 'N', 'Y', 'Y', 'Y', 'Y', 'Y'],
        'Lunch_start_window': [0, 0, 40, 40, 40, 40, 40],
        'Lunch_end_window': [0, 0, 65, 65, 65, 65, 65],
        'Expected_Lunch_Time': [0, 0, 30, 30, 30, 30, 30],
        'BreakA_Option': ['N', 'Y', 'Y', 'Y', 'Y', 'Y', 'Y'],
        'BreakA_Start': [0, 20, 20, 20, 20, 20, 20],
        'BreakA_End': [0, 40, 40, 40, 40, 40, 40],
        'Expected_BreakA_Time': [0, 15, 15, 15, 15, 15, 15],
        'BreakB_Option': ['N', 'N', 'N', 'N', 'Y', 'Y', 'Y'],
        'BreakB_Start': [0, 0, 0, 0, 65, 65, 65],
        'BreakB_End': [0, 0, 0, 0, 85, 85, 85],
        'Expected_BreakB_Time': [0, 0, 0, 0, 15, 15, 15],
    })
    rules.to_excel(os.path.join(TEMPLATES_DIR, "break_lunch_rules.xlsx"), index=False)

    # 8. Block Dates
    block_dates = pd.DataFrame({
        'Date_Blocked': ['2026-04-10'],
        'ClientCode': ['ACME'],
    })
    block_dates.to_excel(os.path.join(TEMPLATES_DIR, "block_dates.xlsx"), index=False)

    # 9. Member Overrides
    overrides = pd.DataFrame({
        'MemberID': [106],
        'Override_breakA': ['N'],
        'Override_breakB': ['N'],
        'Override_Lunch': ['Y'],
        'Override_FullSchedule': ['N'],
        'Lunch_Duration': ['N'],
        'Lunch_Duration_Min': [30],
        'breakA_Duration': ['N'],
        'breakA_Duration_Min': [15],
        'breakB_Duration': ['N'],
        'breakB_Duration_Min': [15],
    })
    overrides.to_excel(os.path.join(TEMPLATES_DIR, "member_overrides.xlsx"), index=False)

    # 10. FTE Requirements
    fte = pd.DataFrame({
        'ClientCode': ['ACME', 'ACME', 'GLOBEX', 'GLOBEX', 'INITECH'],
        'Role': ['Agent', 'Agent', 'Agent', 'Agent', 'Agent'],
        'RequiredFTE': [3, 2, 2, 1, 2],
        'Period': ['Weekday', 'Weekend', 'Weekday', 'Weekend', 'Weekday'],
    })
    fte.to_excel(os.path.join(TEMPLATES_DIR, "fte_requirements.xlsx"), index=False)

    print("All templates generated in:", TEMPLATES_DIR)
    return TEMPLATES_DIR


if __name__ == "__main__":
    generate_all_templates()
