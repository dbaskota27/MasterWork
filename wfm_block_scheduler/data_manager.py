import pandas as pd
import os
import streamlit as st
from config import DATA_FILES, REQUIRED_COLUMNS, DATA_DIR, GENERATED_SCHEDULE_FILE


def load_data(entity_name: str) -> pd.DataFrame | None:
    """Load an Excel data file. Returns DataFrame or None if not found."""
    file_path = DATA_FILES.get(entity_name)
    if file_path and os.path.exists(file_path):
        try:
            return pd.read_excel(file_path)
        except Exception as e:
            st.error(f"Error loading {entity_name}: {e}")
            return None
    return None


def save_data(entity_name: str, df: pd.DataFrame) -> bool:
    """Save a DataFrame to the corresponding Excel file."""
    file_path = DATA_FILES.get(entity_name)
    if file_path:
        try:
            df.to_excel(file_path, index=False)
            return True
        except Exception as e:
            st.error(f"Error saving {entity_name}: {e}")
            return False
    return False


def validate_columns(entity_name: str, df: pd.DataFrame) -> tuple[bool, list[str]]:
    """Check if required columns are present. Returns (valid, missing_cols)."""
    required = REQUIRED_COLUMNS.get(entity_name, [])
    df_cols = [c.strip() for c in df.columns]
    missing = [c for c in required if c not in df_cols]
    return len(missing) == 0, missing


def get_data_status() -> dict:
    """Return load status for all data entities."""
    status = {}
    for name, path in DATA_FILES.items():
        if os.path.exists(path):
            try:
                df = pd.read_excel(path)
                status[name] = {"loaded": True, "rows": len(df), "cols": list(df.columns)}
            except Exception:
                status[name] = {"loaded": False, "rows": 0, "cols": []}
        else:
            status[name] = {"loaded": False, "rows": 0, "cols": []}
    return status


def load_all_data() -> dict[str, pd.DataFrame]:
    """Load all data entities into a dict of DataFrames."""
    data = {}
    for name in DATA_FILES:
        df = load_data(name)
        if df is not None:
            data[name] = df
    return data


def save_generated_schedule(df: pd.DataFrame) -> str:
    """Save the generated schedule to Excel. Returns file path."""
    df.to_excel(GENERATED_SCHEDULE_FILE, index=False)
    return GENERATED_SCHEDULE_FILE


def load_generated_schedule() -> pd.DataFrame | None:
    """Load the most recent generated schedule."""
    if os.path.exists(GENERATED_SCHEDULE_FILE):
        try:
            return pd.read_excel(GENERATED_SCHEDULE_FILE)
        except Exception:
            return None
    return None


def delete_data(entity_name: str) -> bool:
    """Delete a data file."""
    file_path = DATA_FILES.get(entity_name)
    if file_path and os.path.exists(file_path):
        os.remove(file_path)
        return True
    return False
