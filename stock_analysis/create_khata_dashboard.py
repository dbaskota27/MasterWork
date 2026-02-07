import os
from pathlib import Path

PROJECT = "khata_dashboard"

FILES = {
    "app.py": """import streamlit as st
from core.loader import load_all_csvs
from core.option_parser import parse_option_details
from core.trade_matcher import match_trades
from core.metrics import trade_metrics
from analytics.strategy import assign_strategy
from analytics.calendar_view import render_calendar

st.set_page_config(page_title="Khata Trading Dashboard", layout="wide", page_icon="📈")
st.title("Khata Trading Dashboard")

df = load_all_csvs()
if df.empty:
    st.stop()

parsed = df["Description"].apply(parse_option_details)
df["Option Type"] = [p[0] for p in parsed]
df["Expiration"] = [p[1] for p in parsed]
df["Strike"] = [p[2] for p in parsed]
df["Strategy"] = df["Description"].apply(assign_strategy)

trades, open_positions = match_trades(df)
metrics = trade_metrics(trades)

tab1, tab2 = st.tabs(["Overview", "Calendar"])

with tab1:
    st.metric("Total Realized P/L", f"${metrics.get('Total P/L', 0):,.2f}")
    st.metric("Closed Trades", metrics.get("Closed Trades", 0))
    st.dataframe(trades, use_container_width=True)

with tab2:
    render_calendar(trades)
""",

    "core/loader.py": """import os, glob
import pandas as pd
import numpy as np
import streamlit as st

@st.cache_data
def load_all_csvs():
    csvs = glob.glob(os.path.join(os.getcwd(), "*.csv"))
    if not csvs:
        st.error("No CSV files found")
        return pd.DataFrame()

    frames = []
    for f in csvs:
        try:
            frames.append(pd.read_csv(f, on_bad_lines="warn", encoding="utf-8"))
        except Exception as e:
            st.warning(f"Skipped {f}: {e}")

    df = pd.concat(frames, ignore_index=True)
    df.columns = df.columns.str.strip().str.lower().str.replace(" ", "_")

    df.rename(columns={
        "process_date": "Process Date",
        "trade_date": "Process Date",
        "instrument": "Instrument",
        "description": "Description",
        "quantity": "Quantity",
        "price": "Price",
        "amount": "Amount",
        "trans_code": "trans_code"
    }, inplace=True)

    df["Process Date"] = pd.to_datetime(df["Process Date"], errors="coerce")

    def clean_amount(v):
        s = str(v).replace("$","").replace(",","")
        if s.startswith("("):
            s = "-" + s[1:-1]
        try:
            return float(s)
        except:
            return np.nan

    df["Amount"] = df["Amount"].apply(clean_amount)
    df["Quantity"] = pd.to_numeric(df["Quantity"], errors="coerce").abs()
    df["Price"] = pd.to_numeric(df["Price"], errors="coerce")

    df.sort_values("Process Date", inplace=True)
    return df
""",

    "core/option_parser.py": """import re
import pandas as pd

def parse_option_details(desc):
    if pd.isna(desc):
        return "Other", None, None

    d = str(desc).lower()
    opt = "Put" if "put" in d else "Call" if "call" in d else "Other"
    exp = re.search(r"\\d{1,2}/\\d{1,2}/\\d{4}", d)
    strike = re.search(r"\\$(\\d+\\.?\\d*)", d)

    return opt, exp.group(0) if exp else None, float(strike.group(1)) if strike else None
""",

    "core/trade_matcher.py": """import pandas as pd

def match_trades(df):
    trades, open_pos = [], []
    keys = ["Instrument","Option Type","Expiration","Strike"]

    for k, g in df.groupby(keys, dropna=False):
        g = g.sort_values("Process Date")
        longs, shorts = [], []

        for _, r in g.iterrows():
            qty, price = int(r["Quantity"]), float(r["Price"])
            date, code = r["Process Date"], str(r.get("trans_code","")).upper()

            if "BTO" in code:
                longs.append(dict(q=qty,p=price,d=date))
            elif "STC" in code:
                while qty and longs:
                    e = longs[0]
                    m = min(qty, e["q"])
                    trades.append({**dict(zip(keys,k)),
                        "Position Type":"Long",
                        "Entry Date":e["d"],
                        "Exit Date":date,
                        "Quantity Closed":m,
                        "PL":(price-e["p"])*m*100})
                    e["q"] -= m
                    qty -= m
                    if e["q"] == 0: longs.pop(0)
            elif "STO" in code:
                shorts.append(dict(q=qty,p=price,d=date))
            elif "BTC" in code:
                while qty and shorts:
                    e = shorts[0]
                    m = min(qty, e["q"])
                    trades.append({**dict(zip(keys,k)),
                        "Position Type":"Short",
                        "Entry Date":e["d"],
                        "Exit Date":date,
                        "Quantity Closed":m,
                        "PL":(e["p"]-price)*m*100})
                    e["q"] -= m
                    qty -= m
                    if e["q"] == 0: shorts.pop(0)

        for l in longs:
            open_pos.append({**dict(zip(keys,k)),
                "Position Type":"Long","Quantity Open":l["q"],"Avg Entry Price":l["p"]})
        for s in shorts:
            open_pos.append({**dict(zip(keys,k)),
                "Position Type":"Short","Quantity Open":s["q"],"Avg Entry Price":s["p"]})

    return pd.DataFrame(trades), pd.DataFrame(open_pos)
""",

    "core/metrics.py": """import numpy as np

def trade_metrics(df):
    if df.empty:
        return {}
    wins = df[df.PL > 0]
    losses = df[df.PL < 0]
    return {
        "Total P/L": df.PL.sum(),
        "Closed Trades": len(df),
        "Win Rate %": len(wins)/len(df)*100 if len(df) else 0,
        "Avg Win": wins.PL.mean() if not wins.empty else 0,
        "Avg Loss": losses.PL.mean() if not losses.empty else 0,
        "Profit Factor": abs(wins.PL.sum()/losses.PL.sum()) if not losses.empty else np.inf
    }
""",

    "analytics/strategy.py": """import re

def assign_strategy(desc):
    d = str(desc).lower()
    if re.search("scalp|0dte", d): return "Scalp"
    if "swing" in d: return "Swing"
    if "lotto" in d: return "Lotto"
    if "hedge" in d: return "Hedge"
    return "Other"
""",

    "analytics/calendar_view.py": """import calendar, datetime
import streamlit as st

def render_calendar(df):
    if df.empty:
        st.info("No trades")
        return

    df = df.copy()
    df["Date"] = df["Exit Date"].dt.date
    year, month = df["Date"].iloc[0].year, df["Date"].iloc[0].month

    cal = calendar.monthcalendar(year, month)
    daily = df.groupby("Date")["PL"].sum().to_dict()

    st.subheader(f"{calendar.month_name[month]} {year}")
    cols = st.columns(7)
    for d in ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"]:
        cols[["Mon","Tue","Wed","Thu","Fri","Sat","Sun"].index(d)].markdown(f"**{d}**")

    for week in cal:
        cols = st.columns(7)
        for i, day in enumerate(week):
            if day == 0:
                cols[i].write("")
            else:
                val = daily.get(datetime.date(year,month,day),0)
                cols[i].metric(day, f"${val:,.2f}")
"""
}

def main():
    for path, content in FILES.items():
        full_path = Path(PROJECT) / path
        full_path.parent.mkdir(parents=True, exist_ok=True)
        full_path.write_text(content)

    Path(PROJECT, "requirements.txt").write_text(
        "streamlit\npandas\nnumpy\nplotly\nyfinance\n"
    )

    print("✅ khata_dashboard created successfully")

if __name__ == "__main__":
    main()
