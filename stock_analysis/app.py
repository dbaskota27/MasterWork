import streamlit as st
import pandas as pd
import numpy as np
import plotly.express as px
import plotly.graph_objects as go
from datetime import datetime

from config import setup_page
from auth_ui import auth_gate, logout_button
from supabase_db import (
    get_supabase, set_auth_session,
    fetch_user_trades, insert_user_trades, delete_user_trades
)
from data_pipeline import normalize_dataframe, add_option_columns
from trade_engine import match_trades, calculate_trade_metrics, calculate_sell_order_stats
from market_data import yfinance_available, fetch_current_option_price, fetch_current_stock_price, calculate_unrealized
from calendar_views import render_calendar_tab

setup_page()

sb = get_supabase()
auth = auth_gate(sb)
if not auth:
    st.stop()

set_auth_session(sb, auth["access_token"], auth["refresh_token"])
logout_button(sb)

user_id = auth["user_id"]

# -----------------------------
# Sidebar: Upload / Replace / Delete
# -----------------------------
st.sidebar.subheader("Your Data")

uploaded = st.sidebar.file_uploader("Upload CSV or Excel", type=["csv", "xlsx"])
replace_on_upload = st.sidebar.checkbox("Replace existing data on upload", value=True)
include_unmatched = st.sidebar.checkbox("Include unmatched sells in P/L?", value=False)

if st.sidebar.button("Delete My Data", use_container_width=True):
    delete_user_trades(sb, user_id)
    st.sidebar.success("Deleted your stored trades. Upload a new file.")
    st.rerun()

if uploaded is not None:
    try:
        if uploaded.name.lower().endswith(".csv"):
            raw = pd.read_csv(uploaded)
        else:
            raw = pd.read_excel(uploaded)

        df_up = normalize_dataframe(raw)
        df_up = add_option_columns(df_up)

        if replace_on_upload:
            delete_user_trades(sb, user_id)

        rows = []
        for _, r in df_up.iterrows():
            dt = None
            if pd.notna(r["Process Date"]):
                dt = r["Process Date"].to_pydatetime().isoformat()

            rows.append({
                "user_id": user_id,
                "process_date": dt,
                "instrument": None if pd.isna(r["Instrument"]) else str(r["Instrument"]),
                "description": None if pd.isna(r["Description"]) else str(r["Description"]),
                "trans_code": None if pd.isna(r["trans_code"]) else str(r["trans_code"]),
                "quantity": None if pd.isna(r["Quantity"]) else float(r["Quantity"]),
                "price": None if pd.isna(r["Price"]) else float(r["Price"]),
                "amount": None if pd.isna(r["Amount"]) else float(r["Amount"]),
            })

        insert_user_trades(sb, rows)
        st.sidebar.success(f"Saved {len(rows)} rows to your account.")
        st.rerun()

    except Exception as e:
        st.sidebar.error(f"Upload failed: {e}")

# -----------------------------
# Load user data from DB
# -----------------------------
data = fetch_user_trades(sb, user_id)
if not data:
    st.warning("No trades saved for your account yet. Upload a CSV/XLSX from the sidebar.")
    st.stop()

df = pd.DataFrame(data).rename(columns={
    "process_date": "Process Date",
    "instrument": "Instrument",
    "description": "Description",
    "trans_code": "trans_code",
    "quantity": "Quantity",
    "price": "Price",
    "amount": "Amount",
})
df["Process Date"] = pd.to_datetime(df["Process Date"], errors="coerce")

# Normalize + parse options
df = normalize_dataframe(df)
df = add_option_columns(df)

# -----------------------------
# Sidebar filters (period + tickers)
# -----------------------------
st.sidebar.header("Filters")

select_all = st.sidebar.checkbox("Select All Tickers", value=True)
instruments = sorted(df["Instrument"].dropna().unique())

if select_all:
    selected_instr = instruments.copy()
else:
    selected_instr = st.sidebar.multiselect("Instruments", instruments, default=instruments[:5])

date_min = df["Process Date"].min().date() if pd.notna(df["Process Date"].min()) else datetime.today().date()
date_max = df["Process Date"].max().date() if pd.notna(df["Process Date"].max()) else datetime.today().date()

start_date = st.sidebar.date_input("Start Date", value=date_min)
end_date = st.sidebar.date_input("End Date", value=date_max)

# -----------------------------
# Prepare period data
# -----------------------------
df_selected = df[df["Instrument"].isin(selected_instr)].copy()
if df_selected.empty:
    st.error("No data for selected instruments.")
    st.stop()

start_dt = pd.to_datetime(start_date)
end_dt = pd.to_datetime(end_date)

df_for_matching = df_selected[df_selected["Process Date"] <= end_dt].copy()
trades_all_up_to_end, open_at_end = match_trades(df_for_matching, warn_func=st.sidebar.warning)

closed_trades = trades_all_up_to_end[trades_all_up_to_end["Exit Date"] >= start_dt].copy()
if not include_unmatched:
    closed_trades = closed_trades[closed_trades["Match Type"] != "Unmatched Close"]

period_transactions = df_selected[(df_selected["Process Date"] >= start_dt) & (df_selected["Process Date"] <= end_dt)].copy()

period_metrics = calculate_trade_metrics(closed_trades)
total_pl = closed_trades["PL"].sum() if not closed_trades.empty else 0.0

# Unrealized (optional button)
total_unrealized = 0.0
if not open_at_end.empty and st.sidebar.button("Fetch Current Prices → Unrealized P/L (period)"):
    if not yfinance_available():
        st.sidebar.warning("yfinance not available on this server. Live pricing disabled.")
    else:
        open_at_end["Current Price"] = open_at_end.apply(fetch_current_option_price, axis=1)
        open_at_end["Unrealized P/L"] = open_at_end.apply(calculate_unrealized, axis=1)
        total_unrealized = open_at_end["Unrealized P/L"].sum()

# -----------------------------
# Options Summary (table only)
# -----------------------------
group_keys = ["Instrument", "Option Type", "Expiration", "Strike"]
summary = pd.DataFrame()

if not closed_trades.empty:
    summary = closed_trades.groupby(group_keys + ["Position Type"]).agg({
        "Quantity Closed": "sum",
        "PL": "sum",
        "Entry Price": lambda x: np.average(closed_trades.loc[x.index, "Entry Price"], weights=closed_trades.loc[x.index, "Quantity Closed"]),
        "Exit Price": lambda x: np.average(closed_trades.loc[x.index, "Exit Price"], weights=closed_trades.loc[x.index, "Quantity Closed"]),
    }).reset_index()
    summary.rename(columns={
        "Quantity Closed": "Closed Qty",
        "Entry Price": "Avg Entry Price",
        "Exit Price": "Avg Exit Price",
    }, inplace=True)

if not open_at_end.empty:
    open_summary = open_at_end.groupby(group_keys + ["Position Type"]).agg({
        "Quantity Open": "sum",
        "Avg Entry Price": lambda x: np.average(open_at_end.loc[x.index, "Avg Entry Price"], weights=open_at_end.loc[x.index, "Quantity Open"]),
    }).reset_index()
    open_summary["Closed Qty"] = 0
    open_summary["PL"] = 0
    open_summary["Avg Exit Price"] = np.nan
    summary = pd.concat([summary, open_summary], ignore_index=True, sort=False)

buy_filter = period_transactions["Amount"] < 0
sell_filter = period_transactions["Amount"] > 0

if buy_filter.any():
    num_buy_txns = period_transactions[buy_filter].groupby(group_keys).size().rename("Num Debit Txns")
    summary = summary.merge(num_buy_txns, on=group_keys, how="left")

if sell_filter.any():
    num_sell_txns = period_transactions[sell_filter].groupby(group_keys).size().rename("Num Credit Txns")
    summary = summary.merge(num_sell_txns, on=group_keys, how="left")

summary = summary.fillna(0).sort_values(["Instrument", "Option Type", "Expiration", "Strike"])

# -----------------------------
# Tabs order: Data + Options Summary LAST (your request)
# -----------------------------
tab1, tab2, tab3, tab4, tab5, tab6, tab7 = st.tabs([
    "Overview (Period)",
    "Overall",
    "Charts (Period)",
    "Dashboard",
    "Calendar View",
    "Data",
    "Options Summary"
])

# ---- Tab 1: Overview (Period)
with tab1:
    st.header(f"Overview — {start_date} to {end_date}")
    cols = st.columns(5)
    cols[0].metric("Realized P/L", f"${total_pl:,.2f}")
    cols[1].metric("Unrealized P/L", f"${total_unrealized:,.2f}")
    cols[2].metric("Closed Trades", period_metrics.get("Closed Trades", 0))
    cols[3].metric("Profitable Trades", period_metrics.get("Profitable Trades", 0))
    cols[4].metric("Losing Trades", period_metrics.get("Losing Trades", 0))

    if not closed_trades.empty:
        daily = closed_trades.groupby(["Exit Date", "Instrument"])["PL"].sum().reset_index()
        fig = px.bar(daily, x="Exit Date", y="PL", color="Instrument", title="Daily P/L (stacked by ticker)")
        st.plotly_chart(fig, use_container_width=True)

    if not open_at_end.empty and "Current Price" in open_at_end.columns:
        st.subheader("Open Positions at Period End")
        st.dataframe(open_at_end.style.format({
            "Avg Entry Price": "${:,.2f}",
            "Current Price": "${:,.2f}",
            "Unrealized P/L": "${:,.2f}",
            "Quantity Open": "{:.0f}"
        }), use_container_width=True)

# ---- Tab 2: Overall (date-selectable, sell order stats updates with those dates)
with tab2:
    st.header("Overall")

    data_min = df["Process Date"].min().date()
    data_max = df["Process Date"].max().date()

    c1, c2 = st.columns(2)
    with c1:
        overall_start_date = st.date_input("Overall Start Date", value=data_min, min_value=data_min, max_value=data_max, key="overall_start")
    with c2:
        overall_end_date = st.date_input("Overall End Date", value=data_max, min_value=data_min, max_value=data_max, key="overall_end")

    if overall_start_date > overall_end_date:
        st.error("Overall Start Date must be on or before Overall End Date.")
    else:
        overall_start_dt = pd.to_datetime(overall_start_date)
        overall_end_dt = pd.to_datetime(overall_end_date)

        # full history up to end date for correct matching
        df_overall_match = df[df["Process Date"] <= overall_end_dt].copy()
        trades_overall, _ = match_trades(df_overall_match)

        closed_overall = trades_overall[
            (trades_overall["Exit Date"] >= overall_start_dt) &
            (trades_overall["Exit Date"] <= overall_end_dt)
        ].copy()

        if not include_unmatched:
            closed_overall = closed_overall[closed_overall["Match Type"] != "Unmatched Close"]

        overall_metrics = calculate_trade_metrics(closed_overall)
        overall_realized = closed_overall["PL"].sum() if not closed_overall.empty else 0.0

        cols = st.columns(5)
        cols[0].metric("Overall Realized", f"${overall_realized:,.2f}")
        cols[1].metric("Overall Trades", overall_metrics.get("Closed Trades", 0))
        cols[2].metric("Overall Profitable Trades", overall_metrics.get("Profitable Trades", 0))
        cols[3].metric("Overall Losing Trades", overall_metrics.get("Losing Trades", 0))
        cols[4].metric("Profit Factor", f"{overall_metrics.get('Profit Factor', 0):.2f}")

        if not closed_overall.empty:
            daily_overall = closed_overall.groupby("Exit Date")["PL"].sum().reset_index()
            fig = px.bar(daily_overall, x="Exit Date", y="PL", title="Overall Daily P/L (for selected date range)")
            st.plotly_chart(fig, use_container_width=True)

        st.subheader("Sell Order Statistics (Long Positions) — Overall Date Range")
        sell_stats = calculate_sell_order_stats(closed_overall)
        if not sell_stats.empty:
            st.dataframe(sell_stats.style.format({
                "Avg Quantity Sold": "{:.2f}",
                "Avg Profit": "${:,.2f}",
                "Count": "{:.0f}",
            }), use_container_width=True)
        else:
            st.info("No matched long sells found for sell-order analysis in this date range.")

# ---- Tab 3: Charts (Period)
with tab3:
    st.header("Charts — Selected Period & Tickers")
    if closed_trades.empty:
        st.info("No closed trades in selected period")
    else:
        by_ticker = closed_trades.groupby("Instrument")["PL"].sum().reset_index()
        fig_bar = px.bar(by_ticker, x="Instrument", y="PL", title="Realized P/L by Ticker")
        st.plotly_chart(fig_bar, use_container_width=True)

        fig_box = px.box(closed_trades, y="PL", points="all", title="Trade P/L Distribution")
        st.plotly_chart(fig_box, use_container_width=True)

        tree = by_ticker.copy()
        tree["Abs"] = tree["PL"].abs()
        tree["Sign"] = tree["PL"].apply(lambda x: "Profit" if x > 0 else "Loss")
        fig_tree = px.treemap(tree, path=["Sign", "Instrument"], values="Abs", color="PL",
                              color_continuous_scale="RdYlGn", title="P/L Treemap by Ticker")
        st.plotly_chart(fig_tree, use_container_width=True)

# ---- Tab 4: Dashboard (NO calendar here)
with tab4:
    st.header("Dashboard")

    cols = st.columns(4)
    cols[0].metric("Profit factor", f"{period_metrics.get('Profit Factor', 0):.2f}")
    cols[1].metric("Winning VS Losing Trades", f"{period_metrics.get('Profitable Trades', 0)} VS {period_metrics.get('Losing Trades', 0)}")
    cols[2].metric("Avg Win VS Avg Loss", f"${period_metrics.get('Avg Win', 0):.2f} VS ${period_metrics.get('Avg Loss', 0):.2f}")
    cols[3].metric("Largest Gain", f"${(closed_trades['PL'].max() if not closed_trades.empty else 0):,.2f}")

    if not closed_trades.empty:
        tmp = closed_trades.copy()
        tmp["Hour"] = tmp["Exit Date"].dt.hour
        hourly_pl = tmp.groupby("Hour")["PL"].sum().reset_index()
    else:
        hourly_pl = pd.DataFrame(columns=["Hour", "PL"])

    fig_hourly = px.bar(hourly_pl, x="Hour", y="PL", title="Hourly P/L")
    st.plotly_chart(fig_hourly, use_container_width=True)

    st.subheader("Live Market Prices")
    if not yfinance_available():
        st.info("yfinance not installed on server. Live prices disabled.")
    else:
        if not closed_trades.empty:
            unique_symbols = closed_trades["Instrument"].unique()
            live_prices = {}
            for symbol in unique_symbols:
                if " " in str(symbol) or "/" in str(symbol):
                    live_prices[symbol] = np.nan
                else:
                    live_prices[symbol] = fetch_current_stock_price(symbol)

            live_df = pd.DataFrame(list(live_prices.items()), columns=["Symbol", "Current Price"])
            live_df["Current Price"] = live_df["Current Price"].apply(lambda x: f"${x:,.2f}" if not np.isnan(x) else "N/A")
            st.dataframe(live_df, use_container_width=True)
        else:
            st.info("No symbols to fetch live prices for.")

# ---- Tab 5: Calendar View
with tab5:
    render_calendar_tab(closed_trades)

# ---- Tab 6: Data (last)
with tab6:
    st.subheader("Transactions in Period")
    st.dataframe(period_transactions.style.format({"Amount": "${:,.2f}", "Process Date": "{:%Y-%m-%d}"}), use_container_width=True)

    if not closed_trades.empty:
        st.subheader("Matched Closed Trades in Period")
        st.dataframe(closed_trades.style.format({
            "PL": "${:,.2f}",
            "Entry Price": "${:,.2f}",
            "Exit Price": "${:,.2f}",
            "Holding Hours": "{:.1f}",
        }), use_container_width=True)

# ---- Tab 7: Options Summary (last)
with tab7:
    st.header("Options Summary — Selected Period & Tickers")
    if summary.empty:
        st.info("No options transactions in the selected period.")
    else:
        st.dataframe(summary.style.format({
            "Strike": "${:,.2f}",
            "Closed Qty": "{:.0f}",
            "PL": "${:,.2f}",
            "Avg Entry Price": "${:,.2f}",
            "Avg Exit Price": "${:,.2f}",
            "Num Debit Txns": "{:.0f}",
            "Num Credit Txns": "{:.0f}",
        }), use_container_width=True)

st.markdown("---")
st.markdown("[Support by Grok](https://x.com/grok)", unsafe_allow_html=True)
