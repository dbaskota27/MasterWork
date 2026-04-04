import os

APP_NAME = "WFM Block Scheduler"
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.path.join(BASE_DIR, "data")
TEMPLATES_DIR = os.path.join(BASE_DIR, "templates")

# Ensure data directory exists
os.makedirs(DATA_DIR, exist_ok=True)
os.makedirs(TEMPLATES_DIR, exist_ok=True)

# Excel file names for each data entity
DATA_FILES = {
    "employees": os.path.join(DATA_DIR, "employees.xlsx"),
    "schedules": os.path.join(DATA_DIR, "schedules.xlsx"),
    "pto_requests": os.path.join(DATA_DIR, "pto_requests.xlsx"),
    "clients": os.path.join(DATA_DIR, "clients.xlsx"),
    "dept_client_map": os.path.join(DATA_DIR, "dept_client_map.xlsx"),
    "agent_training": os.path.join(DATA_DIR, "agent_training.xlsx"),
    "break_lunch_rules": os.path.join(DATA_DIR, "break_lunch_rules.xlsx"),
    "block_dates": os.path.join(DATA_DIR, "block_dates.xlsx"),
    "member_overrides": os.path.join(DATA_DIR, "member_overrides.xlsx"),
    "fte_requirements": os.path.join(DATA_DIR, "fte_requirements.xlsx"),
    "client_hoops": os.path.join(DATA_DIR, "client_hoops.xlsx"),
}

# Required columns for each data entity
REQUIRED_COLUMNS = {
    "employees": ["MemberID", "FullName", "Department", "EmploymentType"],
    "schedules": ["MemberID"],  # Plus day columns or Schedule JSON
    "pto_requests": ["MemberID", "ScheduleDate", "PaidHours", "UnpaidHours", "ApprovedStatus"],
    "clients": ["ProjectID", "ClientCode"],
    "dept_client_map": ["Department", "ClientCode"],
    "agent_training": ["MemberID", "ProjectID", "TypeID", "Ranking"],
    "break_lunch_rules": ["Shift_Length_hrs", "Lunch_Option", "BreakA_Option", "BreakB_Option"],
    "block_dates": ["Date_Blocked", "ClientCode"],
    "member_overrides": ["MemberID"],
    "fte_requirements": ["ClientCode", "Role", "RequiredFTE", "Period"],
    "client_hoops": ["ClientCode", "DayOfWeek", "Open_Time", "Close_Time"],
}

# Default scheduling parameters
DEFAULT_MAX_ROUND_ROBINS = 3
DEFAULT_RANKING_ID = 1
DEFAULT_TRAINING_TYPE_ID = 1

# Generated schedule output
GENERATED_SCHEDULE_FILE = os.path.join(DATA_DIR, "generated_schedule.xlsx")
