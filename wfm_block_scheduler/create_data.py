"""Create all 10 Excel data files with realistic WFM data."""
import pandas as pd
import json
import os

DATA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
os.makedirs(DATA_DIR, exist_ok=True)


def create_all():

    # =========================================================================
    # 1. EMPLOYEES — 30 agents across 5 departments
    # =========================================================================
    employees = pd.DataFrame([
        # Support Team (10 agents) — mix of FT/PT and WOTC
        {"MemberID": 1001, "FullName": "Alice Johnson", "Department": "Support - Tier 1", "EmploymentType": "Full-Time", "MaxWeeklyHours": 40, "WOTC_Eligible": "Y", "TerminationDate": None, "WFMOverride": 1, "WFMDoNotSchedule": 0},
        {"MemberID": 1002, "FullName": "Bob Smith", "Department": "Support - Tier 1", "EmploymentType": "Full-Time", "MaxWeeklyHours": 40, "WOTC_Eligible": "N", "TerminationDate": None, "WFMOverride": 1, "WFMDoNotSchedule": 0},
        {"MemberID": 1003, "FullName": "Carol Davis", "Department": "Support - Tier 1", "EmploymentType": "Full-Time", "MaxWeeklyHours": 40, "WOTC_Eligible": "Y", "TerminationDate": None, "WFMOverride": 1, "WFMDoNotSchedule": 0},
        {"MemberID": 1004, "FullName": "Dan Wilson", "Department": "Support - Tier 1", "EmploymentType": "Part-Time", "MaxWeeklyHours": 25, "WOTC_Eligible": "N", "TerminationDate": None, "WFMOverride": 1, "WFMDoNotSchedule": 0},
        {"MemberID": 1005, "FullName": "Eva Martinez", "Department": "Support - Tier 2", "EmploymentType": "Full-Time", "MaxWeeklyHours": 40, "WOTC_Eligible": "Y", "TerminationDate": None, "WFMOverride": 1, "WFMDoNotSchedule": 0},
        {"MemberID": 1006, "FullName": "Frank Lee", "Department": "Support - Tier 2", "EmploymentType": "Full-Time", "MaxWeeklyHours": 40, "WOTC_Eligible": "N", "TerminationDate": None, "WFMOverride": 1, "WFMDoNotSchedule": 0},
        {"MemberID": 1007, "FullName": "Grace Kim", "Department": "Support - Tier 2", "EmploymentType": "Part-Time", "MaxWeeklyHours": 20, "WOTC_Eligible": "Y", "TerminationDate": None, "WFMOverride": 1, "WFMDoNotSchedule": 0},
        {"MemberID": 1008, "FullName": "Henry Brown", "Department": "Support - Tier 1", "EmploymentType": "Full-Time", "MaxWeeklyHours": 40, "WOTC_Eligible": "N", "TerminationDate": None, "WFMOverride": 1, "WFMDoNotSchedule": 0},
        {"MemberID": 1009, "FullName": "Irene Chen", "Department": "Support - Tier 1", "EmploymentType": "Full-Time", "MaxWeeklyHours": 40, "WOTC_Eligible": "N", "TerminationDate": None, "WFMOverride": 1, "WFMDoNotSchedule": 0},
        {"MemberID": 1010, "FullName": "Jack Taylor", "Department": "Support - Tier 2", "EmploymentType": "Part-Time", "MaxWeeklyHours": 30, "WOTC_Eligible": "Y", "TerminationDate": None, "WFMOverride": 1, "WFMDoNotSchedule": 0},
        # Sales Team (6 agents)
        {"MemberID": 2001, "FullName": "Karen White", "Department": "Sales", "EmploymentType": "Full-Time", "MaxWeeklyHours": 40, "WOTC_Eligible": "N", "TerminationDate": None, "WFMOverride": 1, "WFMDoNotSchedule": 0},
        {"MemberID": 2002, "FullName": "Leo Garcia", "Department": "Sales", "EmploymentType": "Full-Time", "MaxWeeklyHours": 40, "WOTC_Eligible": "Y", "TerminationDate": None, "WFMOverride": 1, "WFMDoNotSchedule": 0},
        {"MemberID": 2003, "FullName": "Maria Lopez", "Department": "Sales", "EmploymentType": "Full-Time", "MaxWeeklyHours": 40, "WOTC_Eligible": "N", "TerminationDate": None, "WFMOverride": 1, "WFMDoNotSchedule": 0},
        {"MemberID": 2004, "FullName": "Nathan Park", "Department": "Sales", "EmploymentType": "Part-Time", "MaxWeeklyHours": 28, "WOTC_Eligible": "Y", "TerminationDate": None, "WFMOverride": 1, "WFMDoNotSchedule": 0},
        {"MemberID": 2005, "FullName": "Olivia Nguyen", "Department": "Sales", "EmploymentType": "Full-Time", "MaxWeeklyHours": 40, "WOTC_Eligible": "N", "TerminationDate": None, "WFMOverride": 1, "WFMDoNotSchedule": 0},
        {"MemberID": 2006, "FullName": "Patrick O'Brien", "Department": "Sales", "EmploymentType": "Full-Time", "MaxWeeklyHours": 40, "WOTC_Eligible": "N", "TerminationDate": None, "WFMOverride": 1, "WFMDoNotSchedule": 0},
        # Tech Support (6 agents)
        {"MemberID": 3001, "FullName": "Quinn Roberts", "Department": "Tech Support", "EmploymentType": "Full-Time", "MaxWeeklyHours": 40, "WOTC_Eligible": "N", "TerminationDate": None, "WFMOverride": 1, "WFMDoNotSchedule": 0},
        {"MemberID": 3002, "FullName": "Rachel Adams", "Department": "Tech Support", "EmploymentType": "Full-Time", "MaxWeeklyHours": 40, "WOTC_Eligible": "Y", "TerminationDate": None, "WFMOverride": 1, "WFMDoNotSchedule": 0},
        {"MemberID": 3003, "FullName": "Sam Turner", "Department": "Tech Support", "EmploymentType": "Full-Time", "MaxWeeklyHours": 40, "WOTC_Eligible": "N", "TerminationDate": None, "WFMOverride": 1, "WFMDoNotSchedule": 0},
        {"MemberID": 3004, "FullName": "Tina Harris", "Department": "Tech Support", "EmploymentType": "Part-Time", "MaxWeeklyHours": 24, "WOTC_Eligible": "N", "TerminationDate": None, "WFMOverride": 1, "WFMDoNotSchedule": 0},
        {"MemberID": 3005, "FullName": "Uma Patel", "Department": "Tech Support", "EmploymentType": "Full-Time", "MaxWeeklyHours": 40, "WOTC_Eligible": "Y", "TerminationDate": None, "WFMOverride": 1, "WFMDoNotSchedule": 0},
        {"MemberID": 3006, "FullName": "Victor Cruz", "Department": "Tech Support", "EmploymentType": "Full-Time", "MaxWeeklyHours": 40, "WOTC_Eligible": "N", "TerminationDate": None, "WFMOverride": 1, "WFMDoNotSchedule": 0},
        # Billing (4 agents)
        {"MemberID": 4001, "FullName": "Wendy Scott", "Department": "Billing", "EmploymentType": "Full-Time", "MaxWeeklyHours": 40, "WOTC_Eligible": "N", "TerminationDate": None, "WFMOverride": 1, "WFMDoNotSchedule": 0},
        {"MemberID": 4002, "FullName": "Xavier Young", "Department": "Billing", "EmploymentType": "Full-Time", "MaxWeeklyHours": 40, "WOTC_Eligible": "Y", "TerminationDate": None, "WFMOverride": 1, "WFMDoNotSchedule": 0},
        {"MemberID": 4003, "FullName": "Yolanda King", "Department": "Billing", "EmploymentType": "Part-Time", "MaxWeeklyHours": 20, "WOTC_Eligible": "N", "TerminationDate": None, "WFMOverride": 1, "WFMDoNotSchedule": 0},
        {"MemberID": 4004, "FullName": "Zach Miller", "Department": "Billing", "EmploymentType": "Full-Time", "MaxWeeklyHours": 40, "WOTC_Eligible": "N", "TerminationDate": None, "WFMOverride": 1, "WFMDoNotSchedule": 0},
        # After-Hours / Night Shift (4 agents)
        {"MemberID": 5001, "FullName": "Amy Flores", "Department": "After Hours", "EmploymentType": "Full-Time", "MaxWeeklyHours": 40, "WOTC_Eligible": "Y", "TerminationDate": None, "WFMOverride": 1, "WFMDoNotSchedule": 0},
        {"MemberID": 5002, "FullName": "Brian Reed", "Department": "After Hours", "EmploymentType": "Full-Time", "MaxWeeklyHours": 40, "WOTC_Eligible": "N", "TerminationDate": None, "WFMOverride": 1, "WFMDoNotSchedule": 0},
        {"MemberID": 5003, "FullName": "Cindy Morales", "Department": "After Hours", "EmploymentType": "Full-Time", "MaxWeeklyHours": 40, "WOTC_Eligible": "N", "TerminationDate": None, "WFMOverride": 1, "WFMDoNotSchedule": 0},
        {"MemberID": 5004, "FullName": "Derek Chang", "Department": "After Hours", "EmploymentType": "Part-Time", "MaxWeeklyHours": 24, "WOTC_Eligible": "Y", "TerminationDate": None, "WFMOverride": 1, "WFMDoNotSchedule": 0},
    ])
    employees.to_excel(os.path.join(DATA_DIR, "employees.xlsx"), index=False)
    print(f"employees.xlsx: {len(employees)} rows")

    # =========================================================================
    # 2. SCHEDULES — varied shifts: morning, mid, evening, overnight, part-time
    # =========================================================================
    schedules_list = [
        # Support Tier 1 — standard M-F morning shifts
        (1001, {"Monday": [["08:00","17:00"]], "Tuesday": [["08:00","17:00"]], "Wednesday": [["08:00","17:00"]], "Thursday": [["08:00","17:00"]], "Friday": [["08:00","17:00"]]}),
        (1002, {"Monday": [["08:00","17:00"]], "Tuesday": [["08:00","17:00"]], "Wednesday": [["08:00","17:00"]], "Thursday": [["08:00","17:00"]], "Friday": [["08:00","17:00"]]}),
        (1003, {"Monday": [["07:00","16:00"]], "Tuesday": [["07:00","16:00"]], "Wednesday": [["07:00","16:00"]], "Thursday": [["07:00","16:00"]], "Friday": [["07:00","16:00"]]}),
        (1004, {"Monday": [["09:00","18:00"]], "Tuesday": [["09:00","18:00"]], "Wednesday": [["09:00","18:00"]], "Thursday": [["09:00","18:00"]], "Friday": [["09:00","18:00"]]}),
        # Support Tier 2 — staggered + some weekend
        (1005, {"Monday": [["10:00","19:00"]], "Tuesday": [["10:00","19:00"]], "Wednesday": [["10:00","19:00"]], "Thursday": [["10:00","19:00"]], "Friday": [["10:00","19:00"]]}),
        (1006, {"Monday": [["08:00","17:00"]], "Tuesday": [["08:00","17:00"]], "Wednesday": [["08:00","17:00"]], "Thursday": [["08:00","17:00"]], "Saturday": [["09:00","14:00"]]}),
        (1007, {"Tuesday": [["07:00","16:00"]], "Wednesday": [["07:00","16:00"]], "Thursday": [["07:00","16:00"]], "Friday": [["07:00","16:00"]], "Saturday": [["07:00","12:00"]]}),
        (1008, {"Monday": [["06:00","15:00"]], "Tuesday": [["06:00","15:00"]], "Wednesday": [["06:00","15:00"]], "Thursday": [["06:00","15:00"]], "Friday": [["06:00","15:00"]]}),
        (1009, {"Monday": [["08:30","17:30"]], "Tuesday": [["08:30","17:30"]], "Wednesday": [["08:30","17:30"]], "Thursday": [["08:30","17:30"]], "Friday": [["08:30","17:30"]]}),
        (1010, {"Monday": [["11:00","20:00"]], "Tuesday": [["11:00","20:00"]], "Wednesday": [["11:00","20:00"]], "Thursday": [["11:00","20:00"]], "Friday": [["11:00","20:00"]]}),
        # Sales — mid-day + some split
        (2001, {"Monday": [["09:00","18:00"]], "Tuesday": [["09:00","18:00"]], "Wednesday": [["09:00","18:00"]], "Thursday": [["09:00","18:00"]], "Friday": [["09:00","18:00"]]}),
        (2002, {"Monday": [["10:00","19:00"]], "Tuesday": [["10:00","19:00"]], "Wednesday": [["10:00","19:00"]], "Thursday": [["10:00","19:00"]], "Friday": [["10:00","19:00"]]}),
        (2003, {"Monday": [["08:00","17:00"]], "Tuesday": [["08:00","17:00"]], "Wednesday": [["08:00","17:00"]], "Thursday": [["08:00","17:00"]], "Friday": [["08:00","12:00"]]}),
        (2004, {"Monday": [["09:00","18:00"]], "Tuesday": [["09:00","18:00"]], "Wednesday": [["09:00","18:00"]], "Thursday": [["09:00","18:00"]], "Friday": [["09:00","18:00"]], "Saturday": [["10:00","14:00"]]}),
        (2005, {"Monday": [["07:00","16:00"]], "Tuesday": [["07:00","16:00"]], "Wednesday": [["07:00","16:00"]], "Thursday": [["07:00","16:00"]], "Friday": [["07:00","16:00"]]}),
        (2006, {"Monday": [["08:00","17:00"]], "Tuesday": [["08:00","17:00"]], "Wednesday": [["08:00","17:00"]], "Thursday": [["08:00","17:00"]], "Friday": [["08:00","17:00"]]}),
        # Tech Support — varied + weekend coverage
        (3001, {"Monday": [["08:00","17:00"]], "Tuesday": [["08:00","17:00"]], "Wednesday": [["08:00","17:00"]], "Thursday": [["08:00","17:00"]], "Friday": [["08:00","17:00"]]}),
        (3002, {"Monday": [["10:00","19:00"]], "Tuesday": [["10:00","19:00"]], "Wednesday": [["10:00","19:00"]], "Thursday": [["10:00","19:00"]], "Friday": [["10:00","19:00"]]}),
        (3003, {"Monday": [["07:00","16:00"]], "Tuesday": [["07:00","16:00"]], "Wednesday": [["07:00","16:00"]], "Thursday": [["07:00","16:00"]], "Friday": [["07:00","16:00"]], "Saturday": [["08:00","13:00"]]}),
        (3004, {"Tuesday": [["09:00","18:00"]], "Wednesday": [["09:00","18:00"]], "Thursday": [["09:00","18:00"]], "Friday": [["09:00","18:00"]], "Saturday": [["09:00","18:00"]]}),
        (3005, {"Monday": [["12:00","21:00"]], "Tuesday": [["12:00","21:00"]], "Wednesday": [["12:00","21:00"]], "Thursday": [["12:00","21:00"]], "Friday": [["12:00","21:00"]]}),
        (3006, {"Monday": [["08:00","17:00"]], "Tuesday": [["08:00","17:00"]], "Wednesday": [["08:00","17:00"]], "Thursday": [["08:00","17:00"]], "Friday": [["08:00","12:00"]], "Saturday": [["08:00","12:00"]]}),
        # Billing — standard hours
        (4001, {"Monday": [["08:00","17:00"]], "Tuesday": [["08:00","17:00"]], "Wednesday": [["08:00","17:00"]], "Thursday": [["08:00","17:00"]], "Friday": [["08:00","17:00"]]}),
        (4002, {"Monday": [["09:00","18:00"]], "Tuesday": [["09:00","18:00"]], "Wednesday": [["09:00","18:00"]], "Thursday": [["09:00","18:00"]], "Friday": [["09:00","18:00"]]}),
        (4003, {"Monday": [["08:00","16:00"]], "Tuesday": [["08:00","16:00"]], "Wednesday": [["08:00","16:00"]], "Thursday": [["08:00","16:00"]], "Friday": [["08:00","16:00"]]}),
        (4004, {"Monday": [["10:00","19:00"]], "Tuesday": [["10:00","19:00"]], "Wednesday": [["10:00","19:00"]], "Thursday": [["10:00","19:00"]], "Friday": [["10:00","19:00"]]}),
        # After Hours — overnight & evening shifts
        (5001, {"Monday": [["22:00","24:00"],["00:00","06:00"]], "Tuesday": [["22:00","24:00"],["00:00","06:00"]], "Wednesday": [["22:00","24:00"],["00:00","06:00"]], "Thursday": [["22:00","24:00"],["00:00","06:00"]]}),
        (5002, {"Monday": [["18:00","24:00"]], "Tuesday": [["18:00","24:00"]], "Wednesday": [["18:00","24:00"]], "Thursday": [["18:00","24:00"]], "Friday": [["18:00","24:00"]]}),
        (5003, {"Sunday": [["20:00","24:00"],["00:00","04:00"]], "Monday": [["20:00","24:00"],["00:00","04:00"]], "Tuesday": [["20:00","24:00"],["00:00","04:00"]], "Wednesday": [["20:00","24:00"],["00:00","04:00"]], "Thursday": [["20:00","24:00"],["00:00","04:00"]]}),
        (5004, {"Friday": [["22:00","24:00"],["00:00","06:00"]], "Saturday": [["22:00","24:00"],["00:00","06:00"]], "Sunday": [["18:00","24:00"]]}),
    ]
    schedules = pd.DataFrame([
        {"MemberID": mid, "Schedule": json.dumps(sched)} for mid, sched in schedules_list
    ])
    schedules.to_excel(os.path.join(DATA_DIR, "schedules.xlsx"), index=False)
    print(f"schedules.xlsx: {len(schedules)} rows")

    # =========================================================================
    # 3. PTO REQUESTS — mix of approved, pending, denied for the week of Apr 6
    # =========================================================================
    pto = pd.DataFrame([
        {"MemberID": 1002, "ScheduleDate": "2026-04-07", "PaidHours": 8, "UnpaidHours": 0, "ApprovedStatus": "Approved"},
        {"MemberID": 1002, "ScheduleDate": "2026-04-08", "PaidHours": 8, "UnpaidHours": 0, "ApprovedStatus": "Approved"},
        {"MemberID": 1005, "ScheduleDate": "2026-04-09", "PaidHours": 4, "UnpaidHours": 4, "ApprovedStatus": "Approved"},
        {"MemberID": 2003, "ScheduleDate": "2026-04-06", "PaidHours": 8, "UnpaidHours": 0, "ApprovedStatus": "Approved"},
        {"MemberID": 2003, "ScheduleDate": "2026-04-07", "PaidHours": 8, "UnpaidHours": 0, "ApprovedStatus": "Approved"},
        {"MemberID": 2003, "ScheduleDate": "2026-04-08", "PaidHours": 8, "UnpaidHours": 0, "ApprovedStatus": "Approved"},
        {"MemberID": 2003, "ScheduleDate": "2026-04-09", "PaidHours": 8, "UnpaidHours": 0, "ApprovedStatus": "Approved"},
        {"MemberID": 2003, "ScheduleDate": "2026-04-10", "PaidHours": 8, "UnpaidHours": 0, "ApprovedStatus": "Approved"},
        {"MemberID": 3004, "ScheduleDate": "2026-04-10", "PaidHours": 8, "UnpaidHours": 0, "ApprovedStatus": "Approved"},
        {"MemberID": 3004, "ScheduleDate": "2026-04-11", "PaidHours": 8, "UnpaidHours": 0, "ApprovedStatus": "Approved"},
        {"MemberID": 4001, "ScheduleDate": "2026-04-08", "PaidHours": 4, "UnpaidHours": 0, "ApprovedStatus": "Approved"},
        {"MemberID": 5002, "ScheduleDate": "2026-04-06", "PaidHours": 6, "UnpaidHours": 0, "ApprovedStatus": "Approved"},
        # Pending — should NOT exclude
        {"MemberID": 1001, "ScheduleDate": "2026-04-10", "PaidHours": 8, "UnpaidHours": 0, "ApprovedStatus": "Pending"},
        {"MemberID": 3001, "ScheduleDate": "2026-04-07", "PaidHours": 8, "UnpaidHours": 0, "ApprovedStatus": "Pending"},
        # Denied — should NOT exclude
        {"MemberID": 2004, "ScheduleDate": "2026-04-09", "PaidHours": 8, "UnpaidHours": 0, "ApprovedStatus": "Denied"},
    ])
    pto.to_excel(os.path.join(DATA_DIR, "pto_requests.xlsx"), index=False)
    print(f"pto_requests.xlsx: {len(pto)} rows")

    # =========================================================================
    # 4. CLIENTS — 5 active clients
    # =========================================================================
    # UniformShift: Y = all agents for this client start/end at same time
    clients = pd.DataFrame([
        {"ProjectID": 10, "ClientCode": "ACME", "ClientName": "Acme Corporation", "Active": 1, "UniformShift": "N", "UniformStart": "", "UniformEnd": ""},
        {"ProjectID": 20, "ClientCode": "GLOBEX", "ClientName": "Globex International", "Active": 1, "UniformShift": "N", "UniformStart": "", "UniformEnd": ""},
        {"ProjectID": 30, "ClientCode": "INITECH", "ClientName": "Initech Solutions", "Active": 1, "UniformShift": "N", "UniformStart": "", "UniformEnd": ""},
        {"ProjectID": 40, "ClientCode": "UMBRELLA", "ClientName": "Umbrella Healthcare", "Active": 1, "UniformShift": "Y", "UniformStart": "08:00", "UniformEnd": "17:00"},
        {"ProjectID": 50, "ClientCode": "STARK", "ClientName": "Stark Industries", "Active": 1, "UniformShift": "Y", "UniformStart": "09:00", "UniformEnd": "18:00"},
    ])
    clients.to_excel(os.path.join(DATA_DIR, "clients.xlsx"), index=False)
    print(f"clients.xlsx: {len(clients)} rows")

    # =========================================================================
    # 5. DEPARTMENT-CLIENT MAPPING
    # =========================================================================
    dept_map = pd.DataFrame([
        {"Department": "Support - Tier 1", "ClientCode": "ACME"},
        {"Department": "Support - Tier 1", "ClientCode": "GLOBEX"},
        {"Department": "Support - Tier 2", "ClientCode": "ACME"},
        {"Department": "Support - Tier 2", "ClientCode": "INITECH"},
        {"Department": "Sales", "ClientCode": "GLOBEX"},
        {"Department": "Sales", "ClientCode": "UMBRELLA"},
        {"Department": "Tech Support", "ClientCode": "INITECH"},
        {"Department": "Tech Support", "ClientCode": "STARK"},
        {"Department": "Billing", "ClientCode": "UMBRELLA"},
        {"Department": "Billing", "ClientCode": "ACME"},
        {"Department": "After Hours", "ClientCode": "ACME"},
        {"Department": "After Hours", "ClientCode": "GLOBEX"},
        {"Department": "After Hours", "ClientCode": "INITECH"},
    ])
    dept_map.to_excel(os.path.join(DATA_DIR, "dept_client_map.xlsx"), index=False)
    print(f"dept_client_map.xlsx: {len(dept_map)} rows")

    # =========================================================================
    # 6. AGENT TRAINING — maps each agent to their primary client project
    # =========================================================================
    training = pd.DataFrame([
        # Support T1 → ACME
        {"MemberID": 1001, "ProjectID": 10, "TypeID": 1, "Ranking": 1},
        {"MemberID": 1002, "ProjectID": 10, "TypeID": 1, "Ranking": 1},
        {"MemberID": 1003, "ProjectID": 20, "TypeID": 1, "Ranking": 1},
        {"MemberID": 1004, "ProjectID": 20, "TypeID": 1, "Ranking": 1},
        # Support T2 → ACME/INITECH
        {"MemberID": 1005, "ProjectID": 10, "TypeID": 1, "Ranking": 1},
        {"MemberID": 1006, "ProjectID": 30, "TypeID": 1, "Ranking": 1},
        {"MemberID": 1007, "ProjectID": 30, "TypeID": 1, "Ranking": 1},
        {"MemberID": 1008, "ProjectID": 10, "TypeID": 1, "Ranking": 1},
        {"MemberID": 1009, "ProjectID": 10, "TypeID": 1, "Ranking": 1},
        {"MemberID": 1010, "ProjectID": 30, "TypeID": 1, "Ranking": 1},
        # Sales → GLOBEX/UMBRELLA
        {"MemberID": 2001, "ProjectID": 20, "TypeID": 2, "Ranking": 1},
        {"MemberID": 2002, "ProjectID": 20, "TypeID": 2, "Ranking": 1},
        {"MemberID": 2003, "ProjectID": 40, "TypeID": 2, "Ranking": 1},
        {"MemberID": 2004, "ProjectID": 40, "TypeID": 2, "Ranking": 1},
        {"MemberID": 2005, "ProjectID": 20, "TypeID": 2, "Ranking": 1},
        {"MemberID": 2006, "ProjectID": 40, "TypeID": 2, "Ranking": 1},
        # Tech Support → INITECH/STARK
        {"MemberID": 3001, "ProjectID": 30, "TypeID": 3, "Ranking": 1},
        {"MemberID": 3002, "ProjectID": 50, "TypeID": 3, "Ranking": 1},
        {"MemberID": 3003, "ProjectID": 30, "TypeID": 3, "Ranking": 1},
        {"MemberID": 3004, "ProjectID": 50, "TypeID": 3, "Ranking": 1},
        {"MemberID": 3005, "ProjectID": 50, "TypeID": 3, "Ranking": 1},
        {"MemberID": 3006, "ProjectID": 30, "TypeID": 3, "Ranking": 1},
        # Billing → UMBRELLA/ACME
        {"MemberID": 4001, "ProjectID": 40, "TypeID": 4, "Ranking": 1},
        {"MemberID": 4002, "ProjectID": 10, "TypeID": 4, "Ranking": 1},
        {"MemberID": 4003, "ProjectID": 40, "TypeID": 4, "Ranking": 1},
        {"MemberID": 4004, "ProjectID": 10, "TypeID": 4, "Ranking": 1},
        # After Hours → ACME/GLOBEX/INITECH
        {"MemberID": 5001, "ProjectID": 10, "TypeID": 5, "Ranking": 1},
        {"MemberID": 5002, "ProjectID": 20, "TypeID": 5, "Ranking": 1},
        {"MemberID": 5003, "ProjectID": 30, "TypeID": 5, "Ranking": 1},
        {"MemberID": 5004, "ProjectID": 10, "TypeID": 5, "Ranking": 1},
        # Secondary training (Ranking 2 — won't be used as primary)
        {"MemberID": 1001, "ProjectID": 20, "TypeID": 1, "Ranking": 2},
        {"MemberID": 1005, "ProjectID": 30, "TypeID": 1, "Ranking": 2},
        {"MemberID": 3001, "ProjectID": 50, "TypeID": 3, "Ranking": 2},
        {"MemberID": 2001, "ProjectID": 40, "TypeID": 2, "Ranking": 2},
    ])
    training.to_excel(os.path.join(DATA_DIR, "agent_training.xlsx"), index=False)
    print(f"agent_training.xlsx: {len(training)} rows")

    # =========================================================================
    # 7. BREAK & LUNCH RULES — based on shift length in hours
    # =========================================================================
    rules = pd.DataFrame([
        {"Shift_Length_hrs": 4, "Lunch_Option": "N", "Lunch_start_window": 0, "Lunch_end_window": 0, "Expected_Lunch_Time": 0,
         "BreakA_Option": "Y", "BreakA_Start": 40, "BreakA_End": 60, "Expected_BreakA_Time": 15,
         "BreakB_Option": "N", "BreakB_Start": 0, "BreakB_End": 0, "Expected_BreakB_Time": 0},
        {"Shift_Length_hrs": 5, "Lunch_Option": "N", "Lunch_start_window": 0, "Lunch_end_window": 0, "Expected_Lunch_Time": 0,
         "BreakA_Option": "Y", "BreakA_Start": 30, "BreakA_End": 50, "Expected_BreakA_Time": 15,
         "BreakB_Option": "Y", "BreakB_Start": 60, "BreakB_End": 80, "Expected_BreakB_Time": 15},
        {"Shift_Length_hrs": 6, "Lunch_Option": "Y", "Lunch_start_window": 40, "Lunch_end_window": 65, "Expected_Lunch_Time": 30,
         "BreakA_Option": "Y", "BreakA_Start": 15, "BreakA_End": 35, "Expected_BreakA_Time": 15,
         "BreakB_Option": "N", "BreakB_Start": 0, "BreakB_End": 0, "Expected_BreakB_Time": 0},
        {"Shift_Length_hrs": 7, "Lunch_Option": "Y", "Lunch_start_window": 38, "Lunch_end_window": 62, "Expected_Lunch_Time": 30,
         "BreakA_Option": "Y", "BreakA_Start": 15, "BreakA_End": 33, "Expected_BreakA_Time": 15,
         "BreakB_Option": "Y", "BreakB_Start": 67, "BreakB_End": 85, "Expected_BreakB_Time": 15},
        {"Shift_Length_hrs": 8, "Lunch_Option": "Y", "Lunch_start_window": 35, "Lunch_end_window": 60, "Expected_Lunch_Time": 30,
         "BreakA_Option": "Y", "BreakA_Start": 15, "BreakA_End": 30, "Expected_BreakA_Time": 15,
         "BreakB_Option": "Y", "BreakB_Start": 65, "BreakB_End": 85, "Expected_BreakB_Time": 15},
        {"Shift_Length_hrs": 9, "Lunch_Option": "Y", "Lunch_start_window": 33, "Lunch_end_window": 55, "Expected_Lunch_Time": 30,
         "BreakA_Option": "Y", "BreakA_Start": 12, "BreakA_End": 28, "Expected_BreakA_Time": 15,
         "BreakB_Option": "Y", "BreakB_Start": 60, "BreakB_End": 82, "Expected_BreakB_Time": 15},
        {"Shift_Length_hrs": 10, "Lunch_Option": "Y", "Lunch_start_window": 30, "Lunch_end_window": 50, "Expected_Lunch_Time": 30,
         "BreakA_Option": "Y", "BreakA_Start": 10, "BreakA_End": 25, "Expected_BreakA_Time": 15,
         "BreakB_Option": "Y", "BreakB_Start": 55, "BreakB_End": 80, "Expected_BreakB_Time": 15},
    ])
    rules.to_excel(os.path.join(DATA_DIR, "break_lunch_rules.xlsx"), index=False)
    print(f"break_lunch_rules.xlsx: {len(rules)} rows")

    # =========================================================================
    # 8. BLOCK DATES — holidays and client-specific blackout dates
    # =========================================================================
    block_dates = pd.DataFrame([
        # Good Friday 2026 — ACME closed
        {"Date_Blocked": "2026-04-03", "ClientCode": "ACME"},
        # Company training day — all clients
        {"Date_Blocked": "2026-04-10", "ClientCode": "ACME"},
        {"Date_Blocked": "2026-04-10", "ClientCode": "GLOBEX"},
        # UMBRELLA system maintenance
        {"Date_Blocked": "2026-04-08", "ClientCode": "UMBRELLA"},
        # STARK client holiday
        {"Date_Blocked": "2026-04-11", "ClientCode": "STARK"},
    ])
    block_dates.to_excel(os.path.join(DATA_DIR, "block_dates.xlsx"), index=False)
    print(f"block_dates.xlsx: {len(block_dates)} rows")

    # =========================================================================
    # 9. MEMBER OVERRIDES — special rules for specific agents
    # =========================================================================
    overrides = pd.DataFrame([
        # Frank Lee — no lunch break (medical accommodation, eats at desk)
        {"MemberID": 1006, "Override_breakA": "N", "Override_breakB": "N", "Override_Lunch": "Y", "Override_FullSchedule": "N",
         "Lunch_Duration": "N", "Lunch_Duration_Min": 30, "breakA_Duration": "N", "breakA_Duration_Min": 15, "breakB_Duration": "N", "breakB_Duration_Min": 15},
        # Uma Patel — custom 45-min lunch
        {"MemberID": 3005, "Override_breakA": "N", "Override_breakB": "N", "Override_Lunch": "N", "Override_FullSchedule": "N",
         "Lunch_Duration": "Y", "Lunch_Duration_Min": 45, "breakA_Duration": "N", "breakA_Duration_Min": 15, "breakB_Duration": "N", "breakB_Duration_Min": 15},
        # Zach Miller — no breaks at all (part-time manager, exempt)
        {"MemberID": 4004, "Override_breakA": "Y", "Override_breakB": "Y", "Override_Lunch": "Y", "Override_FullSchedule": "N",
         "Lunch_Duration": "N", "Lunch_Duration_Min": 30, "breakA_Duration": "N", "breakA_Duration_Min": 15, "breakB_Duration": "N", "breakB_Duration_Min": 15},
        # Brian Reed — 20-min breaks (union agreement)
        {"MemberID": 5002, "Override_breakA": "N", "Override_breakB": "N", "Override_Lunch": "N", "Override_FullSchedule": "N",
         "Lunch_Duration": "N", "Lunch_Duration_Min": 30, "breakA_Duration": "Y", "breakA_Duration_Min": 20, "breakB_Duration": "Y", "breakB_Duration_Min": 20},
        # Derek Chang — fully overridden (manual schedule, do not auto-schedule)
        {"MemberID": 5004, "Override_breakA": "N", "Override_breakB": "N", "Override_Lunch": "N", "Override_FullSchedule": "Y",
         "Lunch_Duration": "N", "Lunch_Duration_Min": 30, "breakA_Duration": "N", "breakA_Duration_Min": 15, "breakB_Duration": "N", "breakB_Duration_Min": 15},
    ])
    overrides.to_excel(os.path.join(DATA_DIR, "member_overrides.xlsx"), index=False)
    print(f"member_overrides.xlsx: {len(overrides)} rows")

    # =========================================================================
    # 10. FTE REQUIREMENTS — staffing targets per client per period
    # =========================================================================
    fte = pd.DataFrame([
        # ACME — high volume
        {"ClientCode": "ACME", "Role": "Support Agent", "RequiredFTE": 4.0, "Period": "Weekday"},
        {"ClientCode": "ACME", "Role": "Support Agent", "RequiredFTE": 1.5, "Period": "Weekend"},
        {"ClientCode": "ACME", "Role": "After Hours Agent", "RequiredFTE": 1.0, "Period": "Weekday"},
        # GLOBEX
        {"ClientCode": "GLOBEX", "Role": "Support Agent", "RequiredFTE": 2.0, "Period": "Weekday"},
        {"ClientCode": "GLOBEX", "Role": "Sales Agent", "RequiredFTE": 3.0, "Period": "Weekday"},
        {"ClientCode": "GLOBEX", "Role": "Sales Agent", "RequiredFTE": 1.0, "Period": "Weekend"},
        # INITECH
        {"ClientCode": "INITECH", "Role": "Tech Support Agent", "RequiredFTE": 3.0, "Period": "Weekday"},
        {"ClientCode": "INITECH", "Role": "Tech Support Agent", "RequiredFTE": 1.0, "Period": "Weekend"},
        {"ClientCode": "INITECH", "Role": "After Hours Agent", "RequiredFTE": 1.0, "Period": "Weekday"},
        # UMBRELLA
        {"ClientCode": "UMBRELLA", "Role": "Billing Agent", "RequiredFTE": 2.0, "Period": "Weekday"},
        {"ClientCode": "UMBRELLA", "Role": "Sales Agent", "RequiredFTE": 2.0, "Period": "Weekday"},
        {"ClientCode": "UMBRELLA", "Role": "Sales Agent", "RequiredFTE": 0.5, "Period": "Weekend"},
        # STARK
        {"ClientCode": "STARK", "Role": "Tech Support Agent", "RequiredFTE": 2.5, "Period": "Weekday"},
        {"ClientCode": "STARK", "Role": "Tech Support Agent", "RequiredFTE": 1.0, "Period": "Weekend"},
    ])
    fte.to_excel(os.path.join(DATA_DIR, "fte_requirements.xlsx"), index=False)
    print(f"fte_requirements.xlsx: {len(fte)} rows")

    # =========================================================================
    # 11. CLIENT HOOPS — Hours of Operation per client per day
    # =========================================================================
    hoops_rows = []
    # ACME — M-F 7am-9pm, Sat 8am-2pm, closed Sunday
    for day in ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]:
        hoops_rows.append({"ClientCode": "ACME", "DayOfWeek": day, "Open_Time": "07:00", "Close_Time": "21:00"})
    hoops_rows.append({"ClientCode": "ACME", "DayOfWeek": "Saturday", "Open_Time": "08:00", "Close_Time": "14:00"})

    # GLOBEX — M-F 8am-8pm, Sat 9am-3pm, closed Sunday
    for day in ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]:
        hoops_rows.append({"ClientCode": "GLOBEX", "DayOfWeek": day, "Open_Time": "08:00", "Close_Time": "20:00"})
    hoops_rows.append({"ClientCode": "GLOBEX", "DayOfWeek": "Saturday", "Open_Time": "09:00", "Close_Time": "15:00"})

    # INITECH — M-F 6am-10pm, Sat-Sun 8am-6pm (extended support)
    for day in ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]:
        hoops_rows.append({"ClientCode": "INITECH", "DayOfWeek": day, "Open_Time": "06:00", "Close_Time": "22:00"})
    for day in ["Saturday", "Sunday"]:
        hoops_rows.append({"ClientCode": "INITECH", "DayOfWeek": day, "Open_Time": "08:00", "Close_Time": "18:00"})

    # UMBRELLA — M-F 8am-6pm only (strict healthcare hours)
    for day in ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]:
        hoops_rows.append({"ClientCode": "UMBRELLA", "DayOfWeek": day, "Open_Time": "08:00", "Close_Time": "18:00"})

    # STARK — M-F 7am-11pm, Sat 9am-5pm (tech company, long hours)
    for day in ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]:
        hoops_rows.append({"ClientCode": "STARK", "DayOfWeek": day, "Open_Time": "07:00", "Close_Time": "23:00"})
    hoops_rows.append({"ClientCode": "STARK", "DayOfWeek": "Saturday", "Open_Time": "09:00", "Close_Time": "17:00"})

    hoops = pd.DataFrame(hoops_rows)
    hoops.to_excel(os.path.join(DATA_DIR, "client_hoops.xlsx"), index=False)
    print(f"client_hoops.xlsx: {len(hoops)} rows")

    print("\n=== All 11 data files created in:", DATA_DIR, "===")


if __name__ == "__main__":
    create_all()
