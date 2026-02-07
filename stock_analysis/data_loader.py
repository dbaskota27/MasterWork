import os
import glob
import re
import pandas as pd
import numpy as np
import streamlit as st

from utils import clean_amount

@st.cache_data
def load_all_csvs():
    folder = os.getcwd()
    csv_files = glob.glob(os.path.join(folder, "*.csv"))

    if not csv_files:
        st.error("No .csv files found in: " + folder)
        return pd.DataFrame()

    st.sidebar.write(f"**Found {len(csv_files)} CSVs**")

    combined = []
    for f in csv_files:
        try:
            temp = pd.read_csv(f, on_bad_lines='warn', encoding='utf-8')
            combined.append(temp)
        except Exception as e:
            st.sidebar.warning(f"Skipped {os.path.basename(f)}: {e}")

    if not combined:
        return pd.DataFrame()

    df = pd.concat(combined, ignore_index=True)
    st.sidebar.success(f"Combined {len(df)} rows")
    return df


def normalize_dataframe(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()
    df.columns = df.columns.str.strip().str.lower().str.replace(' ', '_')

    column_map = {
        'process_date': 'Process Date', 'trade_date': 'Process Date',
        'instrument': 'Instrument', 'description': 'Description',
        'trans_code': 'trans_code', 'quantity': 'Quantity',
        'price': 'Price', 'amount': 'Amount'
    }
    df = df.rename(columns=column_map)

    df['Process Date'] = pd.to_datetime(df['Process Date'], errors='coerce')

    df['Amount'] = df['Amount'].apply(clean_amount)
    df['Quantity'] = pd.to_numeric(df['Quantity'], errors='coerce').abs()
    df['Price'] = pd.to_numeric(df['Price'], errors='coerce')

    mask_exp = (
        df['trans_code'].astype(str).str.upper().str.contains('OEXP|EXP', na=False) |
        df['Description'].astype(str).str.lower().str.contains('expiration', na=False)
    )
    df.loc[mask_exp & df['Amount'].isna(), 'Amount'] = 0.0
    df.loc[mask_exp & df['Price'].isna(), 'Price'] = 0.0

    df['Price'] = df['Price'].fillna(abs(df['Amount']) / (df['Quantity'] * 100 + 1e-6))

    df = df.sort_values('Process Date').reset_index(drop=True)
    return df


def parse_option_details(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()

    def parse(desc):
        if pd.isna(desc):
            return 'Unknown', None, None
        desc = str(desc).lower()
        opt_type = 'Put' if 'put' in desc else 'Call' if 'call' in desc else 'Other'
        exp = re.search(r'(\d{1,2}/\d{1,2}/\d{4})', desc)
        exp = exp.group(1) if exp else None
        strike = re.search(r'\$(\d+\.?\d*)', desc)
        strike = float(strike.group(1)) if strike else None
        return opt_type, exp, strike

    parsed = df['Description'].apply(parse)
    df['Option Type'] = [p[0] for p in parsed]
    df['Expiration'] = [p[1] for p in parsed]
    df['Strike'] = [p[2] for p in parsed]

    return df
