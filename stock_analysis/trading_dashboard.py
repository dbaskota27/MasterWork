import streamlit as st
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
import numpy as np
import re
import os
import glob
import yfinance as yf
from datetime import datetime, timedelta

st.set_page_config(page_title="Khata Dashboard", layout="wide", page_icon="📈")
st.title("Khata Trading Dashboard - Chakra Mystic Capital")
st.markdown("""
Auto-loads **all .csv files** from the current folder, fixes parentheses in Amount, sorts by date,  
matches BTO (negative) with STC (positive) using **full history** for accurate P/L even when date range is limited.  
Buys before sells on same day • Accurate realized P/L for selected period & tickers
""")

# ── Trade Matching Function ──────────────────────────────────────────────────
def match_trades(df):
    df = df.dropna(subset=['Quantity', 'Instrument', 'Process Date']).copy()
    trades = []
    open_positions = []
    group_keys = ['Instrument', 'Option Type', 'Expiration', 'Strike']
    
    for keys, group in df.groupby(group_keys, dropna=False):
        group = group.sort_values(by=['Process Date', 'Amount'], ascending=[True, True])
        long_entry_queue = []
        short_entry_queue = []
        
        for _, row in group.iterrows():
            qty = row['Quantity']
            price = row.get('Price', 0.0)
            date = row['Process Date']
            amount = row.get('Amount', 0.0)
            trans_code = str(row.get('trans_code', '')).upper()
            desc = str(row.get('Description', '')).lower()
            is_exp = 'OEXP' in trans_code or 'EXP' in trans_code or 'expiration' in desc
            
            if is_exp:
                price = 0.0
                qty_to_match = qty
                i = 0
                while qty_to_match > 0 and i < len(long_entry_queue):
                    entry = long_entry_queue[i]
                    match_qty = min(qty_to_match, entry['qty'])
                    pl = (price - entry['price']) * match_qty * 100
                    trades.append({**dict(zip(group_keys, keys)),
                                   'Position Type': 'Long',
                                   'Entry Date': entry['date'],
                                   'Entry Price': entry['price'],
                                   'Exit Date': date,
                                   'Exit Price': price,
                                   'Quantity Closed': match_qty,
                                   'PL': pl,
                                   'Holding Hours': (date - entry['date']).total_seconds() / 3600,
                                   'Match Type': 'Expired'})
                    entry['qty'] -= match_qty
                    qty_to_match -= match_qty
                    if entry['qty'] <= 0:
                        long_entry_queue.pop(i)
                    else:
                        i += 1
                i = 0
                while qty_to_match > 0 and i < len(short_entry_queue):
                    entry = short_entry_queue[i]
                    match_qty = min(qty_to_match, entry['qty'])
                    pl = (entry['price'] - price) * match_qty * 100
                    trades.append({**dict(zip(group_keys, keys)),
                                   'Position Type': 'Short',
                                   'Entry Date': entry['date'],
                                   'Entry Price': entry['price'],
                                   'Exit Date': date,
                                   'Exit Price': price,
                                   'Quantity Closed': match_qty,
                                   'PL': pl,
                                   'Holding Hours': (date - entry['date']).total_seconds() / 3600,
                                   'Match Type': 'Expired'})
                    entry['qty'] -= match_qty
                    qty_to_match -= match_qty
                    if entry['qty'] <= 0:
                        short_entry_queue.pop(i)
                    else:
                        i += 1
                if qty_to_match > 0:
                    st.sidebar.warning(f"Unmatched expiration qty for {keys}: {qty_to_match}")
                continue
            
            if 'BTO' in trans_code or (amount < 0 and 'STO' not in trans_code and 'BTC' not in trans_code):
                long_entry_queue.append({'qty': qty, 'price': price, 'date': date})
            elif 'STC' in trans_code or (amount > 0 and 'STO' not in trans_code and 'BTC' not in trans_code):
                qty_to_match = qty
                i = 0
                while qty_to_match > 0 and i < len(long_entry_queue):
                    entry = long_entry_queue[i]
                    match_qty = min(qty_to_match, entry['qty'])
                    pl = (price - entry['price']) * match_qty * 100
                    trades.append({**dict(zip(group_keys, keys)),
                                   'Position Type': 'Long',
                                   'Entry Date': entry['date'],
                                   'Entry Price': entry['price'],
                                   'Exit Date': date,
                                   'Exit Price': price,
                                   'Quantity Closed': match_qty,
                                   'PL': pl,
                                   'Holding Hours': (date - entry['date']).total_seconds() / 3600,
                                   'Match Type': 'Matched'})
                    entry['qty'] -= match_qty
                    qty_to_match -= match_qty
                    if entry['qty'] <= 0:
                        long_entry_queue.pop(i)
                    else:
                        i += 1
                if qty_to_match > 0:
                    trades.append({**dict(zip(group_keys, keys)),
                                   'Position Type': 'Long',
                                   'Entry Date': None,
                                   'Entry Price': None,
                                   'Exit Date': date,
                                   'Exit Price': price,
                                   'Quantity Closed': qty_to_match,
                                   'PL': qty_to_match * price * 100,
                                   'Holding Hours': None,
                                   'Match Type': 'Unmatched Close'})
            elif 'STO' in trans_code:
                short_entry_queue.append({'qty': qty, 'price': price, 'date': date})
            elif 'BTC' in trans_code:
                qty_to_match = qty
                i = 0
                while qty_to_match > 0 and i < len(short_entry_queue):
                    entry = short_entry_queue[i]
                    match_qty = min(qty_to_match, entry['qty'])
                    pl = (entry['price'] - price) * match_qty * 100
                    trades.append({**dict(zip(group_keys, keys)),
                                   'Position Type': 'Short',
                                   'Entry Date': entry['date'],
                                   'Entry Price': entry['price'],
                                   'Exit Date': date,
                                   'Exit Price': price,
                                   'Quantity Closed': match_qty,
                                   'PL': pl,
                                   'Holding Hours': (date - entry['date']).total_seconds() / 3600,
                                   'Match Type': 'Matched'})
                    entry['qty'] -= match_qty
                    qty_to_match -= match_qty
                    if entry['qty'] <= 0:
                        short_entry_queue.pop(i)
                    else:
                        i += 1
                if qty_to_match > 0:
                    trades.append({**dict(zip(group_keys, keys)),
                                   'Position Type': 'Short',
                                   'Entry Date': None,
                                   'Entry Price': None,
                                   'Exit Date': date,
                                   'Exit Price': price,
                                   'Quantity Closed': qty_to_match,
                                   'PL': -qty_to_match * price * 100,
                                   'Holding Hours': None,
                                   'Match Type': 'Unmatched Close'})
        
        for entry in long_entry_queue:
            open_positions.append({**dict(zip(group_keys, keys)),
                                   'Position Type': 'Long',
                                   'Entry Date': entry['date'],
                                   'Quantity Open': entry['qty'],
                                   'Avg Entry Price': entry['price']})
        for entry in short_entry_queue:
            open_positions.append({**dict(zip(group_keys, keys)),
                                   'Position Type': 'Short',
                                   'Entry Date': entry['date'],
                                   'Quantity Open': entry['qty'],
                                   'Avg Entry Price': entry['price']})
    
    trades_df = pd.DataFrame(trades)
    open_df = pd.DataFrame(open_positions)
    return trades_df, open_df

# ── Metrics Function ─────────────────────────────────────────────────────────
def calculate_trade_metrics(trades_df):
    if trades_df.empty:
        return {'Status': 'No closed trades'}
    
    total_pl = trades_df['PL'].sum()
    trades = len(trades_df)
    wins = trades_df[trades_df['PL'] > 0]
    losses = trades_df[trades_df['PL'] < 0]
    win_rate = len(wins) / trades * 100 if trades > 0 else 0
    avg_win = wins['PL'].mean() if len(wins) > 0 else 0
    avg_loss = losses['PL'].mean() if len(losses) > 0 else 0
    risk_reward = abs(avg_win / avg_loss) if avg_loss != 0 else np.inf
    profit_factor = abs(wins['PL'].sum() / losses['PL'].sum()) if len(losses) > 0 and losses['PL'].sum() != 0 else np.inf
    cum_pl = trades_df['PL'].cumsum()
    max_dd = (cum_pl - cum_pl.cummax()).min() if not cum_pl.empty else 0
    expectancy = (win_rate/100 * avg_win) + ((1 - win_rate/100) * avg_loss)
    
    return {
        'Total P/L': total_pl, 'Closed Trades': trades, 'Win Rate %': win_rate,
        'Avg Win': avg_win, 'Avg Loss': avg_loss, 'Risk-Reward Ratio': risk_reward,
        'Profit Factor': profit_factor, 'Max Drawdown': max_dd, 'Expectancy': expectancy,
        'Profitable Trades': len(wins), 'Losing Trades': len(losses)
    }

# ── Live Price Functions ─────────────────────────────────────────────────────
def fetch_current_option_price(row):
    if pd.isna(row['Instrument']) or pd.isna(row['Option Type']) or pd.isna(row['Expiration']) or pd.isna(row['Strike']):
        return np.nan
    try:
        exp_date = datetime.strptime(row['Expiration'], '%m/%d/%Y').strftime('%Y-%m-%d')
        ticker = yf.Ticker(row['Instrument'])
        chain = ticker.option_chain(exp_date)
        opts = chain.calls if row['Option Type'] == 'Call' else chain.puts
        opt = opts[opts['strike'] == row['Strike']]
        return opt['lastPrice'].values[0] if not opt.empty else np.nan
    except:
        return np.nan

def fetch_current_stock_price(symbol):
    try:
        ticker = yf.Ticker(symbol)
        hist = ticker.history(period="1d")
        if not hist.empty:
            return hist['Close'].iloc[-1]
        else:
            return np.nan
    except:
        return np.nan

def calculate_unrealized(row):
    current = row.get('Current Price', np.nan)
    if np.isnan(current):
        return 0.0
    entry = row['Avg Entry Price']
    qty = row['Quantity Open']
    multiplier = 100
    if row['Position Type'] == 'Short':
        return (entry - current) * qty * multiplier
    else:
        return (current - entry) * qty * multiplier

# ── Sell Order Stats for MTD ─────────────────────────────────────────────────
def calculate_sell_order_stats_mtd(closed_trades):
    if closed_trades.empty:
        return pd.DataFrame()
    
    longs = closed_trades[closed_trades['Position Type'] == 'Long'].copy()
    if longs.empty:
        return pd.DataFrame()
    
    longs['Buy Key'] = (
        longs['Entry Date'].astype(str) + '_' +
        longs['Instrument'] + '_' +
        longs['Expiration'].astype(str) + '_' +
        longs['Strike'].astype(str) + '_' +
        longs['Entry Price'].astype(str)
    )
    
    stats = []
    for buy_key, group in longs.groupby('Buy Key'):
        sells = group.sort_values('Exit Date')
        for order, (_, sell) in enumerate(sells.iterrows(), 1):
            stats.append({
                'Sell Order': order,
                'Quantity Closed': sell['Quantity Closed'],
                'PL': sell['PL']
            })
    
    stats_df = pd.DataFrame(stats)
    if stats_df.empty:
        return pd.DataFrame()
    
    agg = stats_df.groupby('Sell Order').agg({
        'Quantity Closed': 'mean',
        'PL': 'mean',
        'Sell Order': 'count'
    }).rename(columns={'Sell Order': 'Count'}).round(2)
    
    agg = agg.reset_index()
    agg.columns = ['Sell Order', 'Avg Quantity Sold', 'Avg Profit', 'Count']
    
    return agg

# ── Load ALL CSVs ────────────────────────────────────────────────────────────
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

df = load_all_csvs()
if df.empty:
    st.stop()

# ── Clean ────────────────────────────────────────────────────────────────────
df.columns = df.columns.str.strip().str.lower().str.replace(' ', '_')
column_map = {
    'process_date': 'Process Date', 'trade_date': 'Process Date',
    'instrument': 'Instrument', 'description': 'Description',
    'trans_code': 'trans_code', 'quantity': 'Quantity',
    'price': 'Price', 'amount': 'Amount'
}
df = df.rename(columns=column_map)

df['Process Date'] = pd.to_datetime(df['Process Date'], errors='coerce')

def clean_amount(val):
    s = str(val).strip()
    if s.startswith('(') and s.endswith(')'):
        s = '-' + s[1:-1]
    s = s.replace('$', '').replace(',', '')
    try:
        return float(s)
    except:
        return np.nan

df['Amount'] = df['Amount'].apply(clean_amount)
df['Quantity'] = pd.to_numeric(df['Quantity'], errors='coerce').abs()
df['Price'] = pd.to_numeric(df['Price'], errors='coerce')

mask_exp = df['trans_code'].str.upper().str.contains('OEXP|EXP', na=False) | df['Description'].str.lower().str.contains('expiration', na=False)
df.loc[mask_exp & df['Amount'].isna(), 'Amount'] = 0.0
df.loc[mask_exp & df['Price'].isna(), 'Price'] = 0.0

df['Price'] = df['Price'].fillna(abs(df['Amount']) / (df['Quantity'] * 100 + 1e-6))
df = df.sort_values('Process Date').reset_index(drop=True)

# ── Parse Option Details ─────────────────────────────────────────────────────
def parse_option_details(desc):
    if pd.isna(desc):
        return 'Unknown', None, None
    desc = str(desc).lower()
    opt_type = 'Put' if 'put' in desc else 'Call' if 'call' in desc else 'Other'
    exp = re.search(r'(\d{1,2}/\d{1,2}/\d{4})', desc)
    exp = exp.group(1) if exp else None
    strike = re.search(r'\$(\d+\.?\d*)', desc)
    strike = float(strike.group(1)) if strike else None
    return opt_type, exp, strike

parsed = df['Description'].apply(parse_option_details)
df['Option Type'] = [p[0] for p in parsed]
df['Expiration'] = [p[1] for p in parsed]
df['Strike'] = [p[2] for p in parsed]

# ── Sidebar Filters ──────────────────────────────────────────────────────────
st.sidebar.header("Filters")

# "Select All Tickers" checkbox
select_all = st.sidebar.checkbox("Select All Tickers", value=True)

instruments = sorted(df['Instrument'].dropna().unique())

if select_all:
    selected_instr = instruments.copy()
else:
    selected_instr = st.sidebar.multiselect("Instruments", instruments, default=instruments[:5])  # default first 5

date_min = df['Process Date'].min().date() if pd.notna(df['Process Date'].min()) else datetime.today().date()
date_max = df['Process Date'].max().date() if pd.notna(df['Process Date'].max()) else datetime.today().date()
start_date = st.sidebar.date_input("Start Date", value=date_min)
end_date   = st.sidebar.date_input("End Date", value=date_max)

include_unmatched = st.sidebar.checkbox("Include unmatched sells in P/L?", value=False)

# ── Prepare data ─────────────────────────────────────────────────────────────
df_selected = df[df['Instrument'].isin(selected_instr)].copy()
if df_selected.empty:
    st.error("No data for selected instruments")
    st.stop()

start_dt = pd.to_datetime(start_date)
end_dt = pd.to_datetime(end_date)

df_for_matching = df_selected[df_selected['Process Date'] <= end_dt].copy()
trades_all_up_to_end, open_at_end = match_trades(df_for_matching)

closed_trades = trades_all_up_to_end[trades_all_up_to_end['Exit Date'] >= start_dt].copy()

if not include_unmatched:
    closed_trades = closed_trades[closed_trades['Match Type'] != 'Unmatched Close']

period_transactions = df_selected[(df_selected['Process Date'] >= start_dt) & (df_selected['Process Date'] <= end_dt)].copy()

period_metrics = calculate_trade_metrics(closed_trades)

# ── Calculate aggregates ─────────────────────────────────────────────────────
total_pl = closed_trades['PL'].sum() if not closed_trades.empty else 0.0

# ── Options Summary ──────────────────────────────────────────────────────────
group_keys = ['Instrument', 'Option Type', 'Expiration', 'Strike']

summary = pd.DataFrame()

if not closed_trades.empty:
    summary = closed_trades.groupby(group_keys + ['Position Type']).agg({
        'Quantity Closed': 'sum',
        'PL': 'sum',
        'Entry Price': lambda x: np.average(closed_trades.loc[x.index, 'Entry Price'], weights=closed_trades.loc[x.index, 'Quantity Closed']),
        'Exit Price': lambda x: np.average(closed_trades.loc[x.index, 'Exit Price'], weights=closed_trades.loc[x.index, 'Quantity Closed'])
    }).reset_index()

    summary.rename(columns={'Quantity Closed': 'Closed Qty', 'Entry Price': 'Avg Entry Price', 'Exit Price': 'Avg Exit Price'}, inplace=True)

if not open_at_end.empty:
    open_summary = open_at_end.groupby(group_keys + ['Position Type']).agg({
        'Quantity Open': 'sum',
        'Avg Entry Price': lambda x: np.average(open_at_end.loc[x.index, 'Avg Entry Price'], weights=open_at_end.loc[x.index, 'Quantity Open'])
    }).reset_index()
    open_summary['Closed Qty'] = 0
    open_summary['PL'] = 0
    open_summary['Avg Exit Price'] = np.nan
    summary = pd.concat([summary, open_summary], ignore_index=True, sort=False)

buy_filter = period_transactions['Amount'] < 0
sell_filter = period_transactions['Amount'] > 0

if buy_filter.any():
    num_buy_txns = period_transactions[buy_filter].groupby(group_keys).size().rename('Num Debit Txns')
    summary = summary.merge(num_buy_txns, on=group_keys, how='left')

if sell_filter.any():
    num_sell_txns = period_transactions[sell_filter].groupby(group_keys).size().rename('Num Credit Txns')
    summary = summary.merge(num_sell_txns, on=group_keys, how='left')

summary = summary.fillna(0)

summary = summary.sort_values(['Instrument', 'Option Type', 'Expiration', 'Strike'])

# ── Summary Totals ───────────────────────────────────────────────────────────
total_realized_pl = summary['PL'].sum()

profitable_contracts = summary[summary['PL'] > 0]
losing_contracts = summary[summary['PL'] < 0]
total_profit_qty = profitable_contracts['Closed Qty'].sum()
total_loss_qty = losing_contracts['Closed Qty'].sum()

# ── Unrealized ───────────────────────────────────────────────────────────────
if not open_at_end.empty and st.sidebar.button("Fetch Current Prices → Unrealized P/L (period)"):
    open_at_end['Current Price'] = open_at_end.apply(fetch_current_option_price, axis=1)
    open_at_end['Unrealized P/L'] = open_at_end.apply(calculate_unrealized, axis=1)
    total_unrealized = open_at_end['Unrealized P/L'].sum()
else:
    total_unrealized = 0.0

# ── Tabs ─────────────────────────────────────────────────────────────────────
tab1, tab2, tab3, tab4, tab5, tab6 = st.tabs(["Overview (Period)", "MTD Overall", "Charts (Period)", "Data", "Options Summary", "Dashboard"])

with tab1:
    st.header(f"Overview — {start_date} to {end_date} — {', '.join(selected_instr) if selected_instr else 'All'}")
    cols = st.columns(5)
    cols[0].metric("Realized P/L", f"${total_pl:,.2f}")
    cols[1].metric("Unrealized P/L", f"${total_unrealized:,.2f}")
    cols[2].metric("Closed Trades", period_metrics.get('Closed Trades', 0))
    cols[3].metric("Profitable Trades", period_metrics.get('Profitable Trades', 0))
    cols[4].metric("Losing Trades", period_metrics.get('Losing Trades', 0))

    if not closed_trades.empty:
        daily = closed_trades.groupby(['Exit Date', 'Instrument'])['PL'].sum().reset_index()
        fig = px.bar(daily, x='Exit Date', y='PL', color='Instrument', title="Daily P/L (stacked by ticker)")
        st.plotly_chart(fig, use_container_width=True)

    if not open_at_end.empty and 'Current Price' in open_at_end.columns:
        st.subheader("Open Positions at Period End")
        st.dataframe(open_at_end.style.format({"Avg Entry Price": "${:,.2f}", "Current Price": "${:,.2f}",
                                               "Unrealized P/L": "${:,.2f}", "Quantity Open": "{:.0f}"}))

with tab2:
    st.header("Month-to-Date Overall (All Tickers)")
    today = datetime.today().date()
    month_start = today.replace(day=1)
    month_start_dt = pd.to_datetime(month_start)

    df_mtd = df[df['Process Date'] <= pd.to_datetime(today)].copy()
    trades_mtd, open_mtd = match_trades(df_mtd)
    closed_mtd = trades_mtd[trades_mtd['Exit Date'] >= month_start_dt].copy()
    if not include_unmatched:
        closed_mtd = closed_mtd[closed_mtd['Match Type'] != 'Unmatched Close']

    mtd_metrics = calculate_trade_metrics(closed_mtd)
    mtd_total_pl = closed_mtd['PL'].sum() if not closed_mtd.empty else 0.0

    if not open_mtd.empty and st.button("Fetch Current Prices → MTD Unrealized P/L"):
        open_mtd['Current Price'] = open_mtd.apply(fetch_current_option_price, axis=1)
        open_mtd['Unrealized P/L'] = open_mtd.apply(calculate_unrealized, axis=1)
        mtd_unreal = open_mtd['Unrealized P/L'].sum()
    else:
        mtd_unreal = 0.0

    cols = st.columns(5)
    cols[0].metric("MTD Realized", f"${mtd_total_pl:,.2f}")
    cols[1].metric("MTD Unrealized", f"${mtd_unreal:,.2f}")
    cols[2].metric("MTD Trades", mtd_metrics.get('Closed Trades', 0))
    cols[3].metric("MTD Profitable Trades", mtd_metrics.get('Profitable Trades', 0))
    cols[4].metric("MTD Losing Trades", mtd_metrics.get('Losing Trades', 0))

    if not closed_mtd.empty:
        daily_mtd = closed_mtd.groupby('Exit Date')['PL'].sum().reset_index()
        fig_mtd = px.bar(daily_mtd, x='Exit Date', y='PL', title=f"MTD Daily P/L — {month_start:%b %Y}")
        st.plotly_chart(fig_mtd, use_container_width=True)

    # ── Sell Order Statistics (MTD) ──────────────────────────────────────────
    st.subheader("Sell Order Statistics (MTD) - Long Positions")
    sell_stats = calculate_sell_order_stats_mtd(closed_mtd)
    if not sell_stats.empty:
        st.dataframe(
            sell_stats.style.format({
                'Avg Quantity Sold': '{:.2f}',
                'Avg Profit': '${:,.2f}',
                'Count': '{:.0f}'
            }),
            use_container_width=True
        )
        st.caption("Average quantity sold and average profit on 1st sell, 2nd sell, etc., from each buy in MTD.")
    else:
        st.info("No matched long sells found for sell-order analysis in MTD.")

with tab3:
    st.header("Charts — Selected Period & Tickers")
    if closed_trades.empty:
        st.info("No closed trades in selected period")
    else:
        by_ticker = closed_trades.groupby('Instrument')['PL'].sum().reset_index()
        fig_bar = px.bar(by_ticker, x='Instrument', y='PL', color=by_ticker['PL'].apply(lambda x: 'Profit' if x>0 else 'Loss'),
                         color_discrete_map={'Profit':'green','Loss':'red'}, title="Realized P/L by Ticker")
        st.plotly_chart(fig_bar, use_container_width=True)

        fig_box = px.box(closed_trades, y='PL', points="all", title="Trade P/L Distribution")
        st.plotly_chart(fig_box, use_container_width=True)

        tree = closed_trades.groupby('Instrument')['PL'].sum().reset_index()
        tree['Abs'] = tree['PL'].abs()
        tree['Sign'] = tree['PL'].apply(lambda x: 'Profit' if x>0 else 'Loss')
        fig_tree = px.treemap(tree, path=['Sign', 'Instrument'], values='Abs', color='PL',
                              color_continuous_scale='RdYlGn', title="P/L Treemap by Ticker")
        st.plotly_chart(fig_tree, use_container_width=True)

with tab4:
    st.subheader("Transactions in Period")
    st.dataframe(period_transactions.style.format({"Amount": "${:,.2f}", "Process Date": "{:%Y-%m-%d}"}))

    if not closed_trades.empty:
        st.subheader("Matched Closed Trades in Period")
        st.dataframe(closed_trades.style.format({"PL": "${:,.2f}", "Entry Price": "${:,.2f}",
                                                "Exit Price": "${:,.2f}", "Holding Hours": "{:.1f}"}))

with tab5:
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
            "Num Credit Txns": "{:.0f}"
        }))

    st.subheader("Summary Totals")
    cols = st.columns(5)
    cols[0].metric("Total Realized P/L", f"${total_realized_pl:,.2f}")
    cols[1].metric("Total Closed Qty", f"{summary['Closed Qty'].sum():.0f}")

    st.subheader("Profit/Loss Metrics")
    cols = st.columns(4)
    cols[0].metric("Qty Profitable Contracts", f"{total_profit_qty:.0f}")
    cols[1].metric("Qty Losing Contracts", f"{total_loss_qty:.0f}")
    cols[2].metric("Num Profitable Contracts", len(profitable_contracts))
    cols[3].metric("Num Losing Contracts", len(losing_contracts))

with tab6:
    st.header("Dashboard")
    if not closed_trades.empty:
        calendar_data = closed_trades.groupby('Exit Date').agg({'PL': 'sum', 'Instrument': 'count'}).rename(columns={'Instrument': 'Trades'}).reset_index()
        calendar_data['Date'] = pd.to_datetime(calendar_data['Exit Date'])
    else:
        calendar_data = pd.DataFrame(columns=['Date', 'PL', 'Trades'])

    if not calendar_data.empty:
        st.subheader(calendar_data['Date'].dt.month_name().iloc[0] + ", " + str(calendar_data['Date'].dt.year.iloc[0]))
    else:
        st.subheader("No Data")
    cols = st.columns(7)
    for i, day in enumerate(['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']):
        cols[i].write(day)
    
    cols = st.columns(7)
    for i, row in calendar_data.iterrows():
        col_idx = row['Date'].weekday()
        with cols[col_idx]:
            st.metric(str(row['Date'].day), f"${row['PL']:.2f}", delta_color="inverse")
            st.write(f"{row['Trades']} trades")

    if not closed_trades.empty:
        recent_trades = closed_trades.groupby('Instrument')['PL'].apply(list).reset_index()
        num_recent = len(recent_trades)
        if num_recent > 0:
            recent_dates = closed_trades['Exit Date'].sort_values().tail(num_recent).values
            recent_trades['Date'] = recent_dates
        else:
            recent_trades['Date'] = pd.NaT
        recent_trades.rename(columns={'PL': 'PL History'}, inplace=True)
    else:
        recent_trades = pd.DataFrame(columns=['Instrument', 'PL History', 'Date'])

    st.subheader("Your recent shared trades")
    cols = st.columns(3)
    for i in range(min(3, len(recent_trades))):
        trade = recent_trades.iloc[i]
        with cols[i]:
            date_str = trade['Date'].strftime('%Y-%m-%d') if pd.notna(trade['Date']) else 'N/A'
            st.write(date_str)
            st.write(trade['Instrument'])
            fig = px.line(y=trade['PL History'], markers=True)
            fig.update_layout(showlegend=False, height=150, margin=dict(l=0, r=0, t=0, b=0))
            st.plotly_chart(fig, use_container_width=True)

    cols = st.columns(4)
    cols[0].metric("Profit factor", f"{period_metrics.get('Profit Factor', 0):.2f}")
    cols[1].metric("Winning VS Losing Trades", f"{period_metrics.get('Profitable Trades', 0)} VS {period_metrics.get('Losing Trades', 0)}")
    cols[2].metric("Average Winning Trade VS Losing Trade", f"${period_metrics.get('Avg Win', 0):.2f} VS {period_metrics.get('Avg Loss', 0):.2f}")
    cols[3].metric("Hourly", "")

    if not closed_trades.empty:
        closed_trades['Hour'] = closed_trades['Exit Date'].dt.hour
        hourly_pl = closed_trades.groupby('Hour')['PL'].sum().reset_index()
    else:
        hourly_pl = pd.DataFrame(columns=['Hour', 'PL'])

    fig_hourly = px.bar(hourly_pl, x='Hour', y='PL', color='PL', color_continuous_scale='rdylgn')
    st.plotly_chart(fig_hourly, use_container_width=True)

    cols = st.columns(4)
    largest_gain = closed_trades['PL'].max() if not closed_trades.empty else 0
    gain_loss_ratio = [0, 0]
    with cols[0]:
        fig_gauge = go.Figure(go.Indicator(mode = "gauge+number", value = largest_gain, title = {'text': "Largest Gain"}))
        st.plotly_chart(fig_gauge, use_container_width=True)
    with cols[1]:
        fig_donut = px.pie(names=['Gain', 'Loss'], values=gain_loss_ratio, hole=0.3, title="Total Gain Loss")
        st.plotly_chart(fig_donut, use_container_width=True)
    with cols[2]:
        fig_bar_k = px.bar(x=['K Ratio'], y=[period_metrics.get('Risk-Reward Ratio', 0)], title="K Ratio")
        st.plotly_chart(fig_bar_k, use_container_width=True)
    with cols[3]:
        st.metric("Largest Gain", f"${largest_gain:,.2f}")

    st.subheader("Live Market Prices")
    if not closed_trades.empty:
        unique_symbols = closed_trades['Instrument'].unique()
        live_prices = {}
        for symbol in unique_symbols:
            if ' ' in symbol or '/' in symbol:
                live_prices[symbol] = np.nan
            else:
                current_price = fetch_current_stock_price(symbol)
                live_prices[symbol] = current_price
        live_df = pd.DataFrame(list(live_prices.items()), columns=['Symbol', 'Current Price'])
        live_df['Current Price'] = live_df['Current Price'].apply(lambda x: f"${x:,.2f}" if not np.isnan(x) else "N/A")
        st.dataframe(live_df.style.format({"Current Price": lambda x: x}), use_container_width=True)
    else:
        st.info("No symbols to fetch live prices for.")

st.markdown("---")
st.markdown("[Support by Grok](https://x.com/grok)", unsafe_allow_html=True)