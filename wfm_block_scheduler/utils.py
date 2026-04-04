import pandas as pd
import numpy as np
from datetime import datetime, timedelta
import math


def convert_time_to_datetime(date_str: str, time_str: str) -> datetime | None:
    """Convert date + time string to datetime. Handles '24:00' edge case."""
    if time_str == '24:00':
        time_str = '00:00'
        date_str = (datetime.strptime(date_str, "%Y-%m-%d") + timedelta(days=1)).strftime("%Y-%m-%d")
    try:
        return datetime.strptime(f"{date_str} {time_str}", "%Y-%m-%d %H:%M")
    except ValueError:
        return None


def round_to_nearest_interval(dt: datetime, overnight: str = 'N') -> datetime:
    """Round datetime to nearest 15-min interval (30-min if overnight)."""
    interval = 30 if overnight == 'Y' else 15
    minutes = dt.minute
    rounded = round(minutes / interval) * interval
    if rounded >= 60:
        dt = dt.replace(minute=0) + timedelta(hours=1)
    else:
        dt = dt.replace(minute=rounded, second=0, microsecond=0)
    return dt


def get_week_dates(start_date) -> list:
    """Generate list of 7 dates starting from start_date (Monday)."""
    if isinstance(start_date, str):
        start_date = datetime.strptime(start_date, "%Y-%m-%d").date()
    return [start_date + timedelta(days=x) for x in range(7)]


def get_day_name(date_obj) -> str:
    """Return day name (Monday, Tuesday, etc.) from a date."""
    return date_obj.strftime("%A")


def seconds_to_hhmm(seconds: float) -> str:
    """Convert seconds to HH:MM format."""
    if pd.isna(seconds) or seconds <= 0:
        return "00:00"
    h = int(seconds // 3600)
    m = int((seconds % 3600) // 60)
    return f"{h:02d}:{m:02d}"
