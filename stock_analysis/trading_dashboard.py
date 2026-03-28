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
from grok_api import run_grok_prompt
from dotenv import load_dotenv

load_dotenv(override=True)
_ENV_GROK_KEY = os.getenv("GROK_API_KEY", "")

st.set_page_config(page_title="Khata Dashboard", layout="wide", page_icon="📈")

st.markdown("""
<style>
    /* ── Base ── */
    .main { background-color: #0e1117; color: #e8eaf0; }
    section[data-testid="stSidebar"] {
        background-color: #13181f;
        border-right: 1px solid #1e2530;
    }
    /* ── Title banner ── */
    .khata-banner {
        background: linear-gradient(135deg, #0d1b2a 0%, #1a2a3a 100%);
        border-left: 4px solid #00ff9d;
        border-radius: 10px;
        padding: 18px 24px 14px 24px;
        margin-bottom: 16px;
    }
    .khata-banner h1 { margin: 0; font-size: 2rem; color: #ffffff; letter-spacing: 3px; }
    .khata-banner p  { margin: 4px 0 0 0; font-size: 0.82rem; color: #6a8099; }
    /* ── Metric cards ── */
    div[data-testid="metric-container"] {
        background: #1a2235;
        border: 1px solid #2a3348;
        border-radius: 10px;
        padding: 14px 16px;
    }
    div[data-testid="metric-container"] label {
        color: #7a8fa6 !important;
        font-size: 0.78rem;
        text-transform: uppercase;
        letter-spacing: 0.5px;
    }
    div[data-testid="metric-container"] [data-testid="stMetricValue"] {
        color: #ffffff;
        font-size: 1.3rem;
        font-weight: 700;
    }
    /* ── Buttons ── */
    .stButton>button {
        background: linear-gradient(135deg, #00ff9d, #00cc7a);
        color: #0e1117;
        border: none;
        border-radius: 8px;
        font-weight: 700;
        letter-spacing: 0.4px;
        padding: 8px 20px;
        transition: opacity 0.2s;
    }
    .stButton>button:hover { opacity: 0.85; }
    /* ── Tabs ── */
    button[data-baseweb="tab"] { font-weight: 600; color: #7a8fa6; }
    button[data-baseweb="tab"][aria-selected="true"] {
        color: #00ff9d !important;
        border-bottom-color: #00ff9d !important;
    }
    /* ── Section subheaders ── */
    h2, h3 { color: #c8d8e8 !important; }
    /* ── Dividers ── */
    hr { border-color: #2a3348; }
    /* ── P/L color helpers ── */
    .pl-positive { color: #00e676; font-weight: 700; }
    .pl-negative { color: #ff5252; font-weight: 700; }
</style>
""", unsafe_allow_html=True)

st.markdown("""
<div class="khata-banner">
    <h1>KHATA</h1>
    <p>Professional Trading Journal &amp; Live Option Scalp Intelligence &nbsp;·&nbsp; Chakra Mystic Capital</p>
</div>
""", unsafe_allow_html=True)

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
    base = os.path.dirname(os.path.abspath(__file__))
    # Look in Data/ subfolder first, fall back to the script directory
    data_dir = os.path.join(base, "Data")
    folder = data_dir if os.path.isdir(data_dir) else base
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
_today = datetime.today().date()

st.sidebar.markdown("**Quick Range**")
_qcol1, _qcol2, _qcol3 = st.sidebar.columns(3)
if _qcol1.button("Daily", use_container_width=True):
    st.session_state["_qrange"] = "daily"
if _qcol2.button("MTD", use_container_width=True):
    st.session_state["_qrange"] = "mtd"
if _qcol3.button("YTD", use_container_width=True):
    st.session_state["_qrange"] = "ytd"

_qrange = st.session_state.get("_qrange", None)
if _qrange == "daily":
    # Last trading day = most recent date in the data
    _last_trading_day = df['Process Date'].max().date() if pd.notna(df['Process Date'].max()) else _today
    _default_start, _default_end = _last_trading_day, _last_trading_day
elif _qrange == "mtd":
    _default_start, _default_end = _today.replace(day=1), _today
elif _qrange == "ytd":
    _default_start, _default_end = _today.replace(month=1, day=1), _today
else:
    _default_start, _default_end = date_min, date_max

start_date = st.sidebar.date_input("Start Date", value=_default_start)
end_date   = st.sidebar.date_input("End Date", value=_default_end)

include_unmatched = st.sidebar.checkbox("Include unmatched sells in P/L?", value=False)

st.sidebar.markdown("---")
st.sidebar.subheader("Grok AI")
grok_api_key = st.sidebar.text_input(
    "Grok API Key",
    value=_ENV_GROK_KEY,
    type="password",
    placeholder="xai-...",
) or _ENV_GROK_KEY

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
tab1, tab2, tab3, tab4, tab5, tab6 = st.tabs([
    "Overview (Period)", "Charts (Period)", "Options Summary", "Dashboard", "Strategy", "Data"
])

# ── helpers ──────────────────────────────────────────────────────────────────
def _pl_delta(val):
    """Return a metric delta string so Streamlit colors the arrow green/red."""
    return f"${val:+,.2f}" if val != 0 else None

with tab1:
    st.header(f"Overview — {start_date} to {end_date}")

    # ── Row 1: P/L + trade counts ────────────────────────────────────────────
    cols = st.columns(5)
    cols[0].metric("Realized P/L", f"${total_pl:,.2f}", delta=_pl_delta(total_pl))
    cols[1].metric("Unrealized P/L", f"${total_unrealized:,.2f}", delta=_pl_delta(total_unrealized))
    cols[2].metric("Closed Trades", period_metrics.get('Closed Trades', 0))
    cols[3].metric("Profitable Trades", period_metrics.get('Profitable Trades', 0))
    cols[4].metric("Losing Trades", period_metrics.get('Losing Trades', 0))

    # ── Row 2: performance stats (previously hidden) ──────────────────────────
    win_rate = period_metrics.get('Win Rate %', 0)
    avg_win  = period_metrics.get('Avg Win', 0)
    avg_loss = period_metrics.get('Avg Loss', 0)
    pf       = period_metrics.get('Profit Factor', 0)
    expect   = period_metrics.get('Expectancy', 0)

    cols2 = st.columns(5)
    cols2[0].metric("Win Rate", f"{win_rate:.1f}%")
    cols2[1].metric("Avg Win", f"${avg_win:,.2f}")
    cols2[2].metric("Avg Loss", f"${avg_loss:,.2f}")
    cols2[3].metric("Profit Factor", f"{pf:.2f}" if pf != float('inf') else "∞")
    cols2[4].metric("Expectancy / Trade", f"${expect:,.2f}")

    if not closed_trades.empty:
        # Daily stacked bar
        daily = closed_trades.groupby(['Exit Date', 'Instrument'])['PL'].sum().reset_index()
        fig_daily = px.bar(
            daily, x='Exit Date', y='PL', color='Instrument',
            title="Daily P/L (stacked by ticker)",
            template="plotly_dark",
        )
        fig_daily.update_layout(paper_bgcolor='#0e1117', plot_bgcolor='#0e1117')
        st.plotly_chart(fig_daily, use_container_width=True, key="tab1_daily_bar")

        # Cumulative P/L line
        cum = closed_trades.sort_values('Exit Date')[['Exit Date', 'PL']].copy()
        cum['Cumulative P/L'] = cum['PL'].cumsum()
        fig_cum = px.area(
            cum, x='Exit Date', y='Cumulative P/L',
            title="Cumulative P/L Curve",
            template="plotly_dark",
            color_discrete_sequence=['#00ff9d'],
        )
        fig_cum.update_layout(paper_bgcolor='#0e1117', plot_bgcolor='#0e1117')
        st.plotly_chart(fig_cum, use_container_width=True, key="tab1_cum_area")

    if not open_at_end.empty and 'Current Price' in open_at_end.columns:
        st.subheader("Open Positions at Period End")
        st.dataframe(open_at_end.style.format({
            "Avg Entry Price": "${:,.2f}", "Current Price": "${:,.2f}",
            "Unrealized P/L": "${:,.2f}", "Quantity Open": "{:.0f}",
        }))

with tab2:
    st.header("Charts — Selected Period & Tickers")
    if closed_trades.empty:
        st.info("No closed trades in selected period")
    else:
        # P/L by ticker bar
        by_ticker = closed_trades.groupby('Instrument')['PL'].sum().reset_index()
        by_ticker['_sign'] = by_ticker['PL'].apply(lambda v: 'Profit' if v >= 0 else 'Loss')
        fig_bar = px.bar(
            by_ticker, x='Instrument', y='PL', color='_sign',
            color_discrete_map={'Profit': '#00e676', 'Loss': '#ff5252'},
            title="Realized P/L by Ticker",
            template="plotly_dark",
        )
        fig_bar.update_layout(paper_bgcolor='#0e1117', plot_bgcolor='#0e1117', showlegend=False)
        st.plotly_chart(fig_bar, use_container_width=True, key="tab3_ticker_bar")

        # Box distribution
        fig_box = px.box(
            closed_trades, y='PL', points="all",
            title="Trade P/L Distribution",
            template="plotly_dark",
            color_discrete_sequence=['#00ff9d'],
        )
        fig_box.update_layout(paper_bgcolor='#0e1117', plot_bgcolor='#0e1117')
        st.plotly_chart(fig_box, use_container_width=True, key="tab3_box")

        # Treemap
        tree = closed_trades.groupby('Instrument')['PL'].sum().reset_index()
        tree['Abs'] = tree['PL'].abs()
        tree['Sign'] = tree['PL'].apply(lambda v: 'Profit' if v >= 0 else 'Loss')
        fig_tree = px.treemap(
            tree, path=['Sign', 'Instrument'], values='Abs', color='PL',
            color_continuous_scale='RdYlGn', title="P/L Treemap by Ticker",
        )
        st.plotly_chart(fig_tree, use_container_width=True, key="tab3_treemap")

with tab6:
    st.subheader("Transactions in Period")
    st.dataframe(period_transactions.style.format({"Amount": "${:,.2f}", "Process Date": "{:%Y-%m-%d}"}))

    if not closed_trades.empty:
        st.subheader("Matched Closed Trades in Period")

        def _color_pl(val):
            color = '#00e676' if val > 0 else '#ff5252' if val < 0 else ''
            return f'color: {color}; font-weight: bold'

        st.dataframe(
            closed_trades.style
            .format({"PL": "${:,.2f}", "Entry Price": "${:,.2f}", "Exit Price": "${:,.2f}", "Holding Hours": "{:.1f}"})
            .applymap(_color_pl, subset=['PL']),
        )

with tab3:
    st.header("Options Summary — Selected Period & Tickers")

    def _color_pl(val):
        color = '#00e676' if val > 0 else '#ff5252' if val < 0 else ''
        return f'color: {color}; font-weight: bold'

    if summary.empty:
        st.info("No options transactions in the selected period.")
    else:
        styled = (
            summary.style
            .format({
                "Strike": "${:,.2f}",
                "Closed Qty": "{:.0f}",
                "PL": "${:,.2f}",
                "Avg Entry Price": "${:,.2f}",
                "Avg Exit Price": "${:,.2f}",
                "Num Debit Txns": "{:.0f}",
                "Num Credit Txns": "{:.0f}",
            })
            .applymap(_color_pl, subset=['PL'])
        )
        st.dataframe(styled, use_container_width=True)

    st.subheader("Summary Totals")
    cols = st.columns(5)
    cols[0].metric("Total Realized P/L", f"${total_realized_pl:,.2f}", delta=_pl_delta(total_realized_pl))
    cols[1].metric("Total Closed Qty", f"{summary['Closed Qty'].sum():.0f}" if not summary.empty else "0")

    st.subheader("Profit / Loss Metrics")
    cols = st.columns(4)
    cols[0].metric("Qty Profitable Contracts", f"{total_profit_qty:.0f}")
    cols[1].metric("Qty Losing Contracts", f"{total_loss_qty:.0f}")
    cols[2].metric("Num Profitable Contracts", len(profitable_contracts))
    cols[3].metric("Num Losing Contracts", len(losing_contracts))

with tab4:
    st.header("Dashboard")

    # ── Performance stats row ─────────────────────────────────────────────────
    cols_dash = st.columns(4)
    pf_val = period_metrics.get('Profit Factor', 0)
    cols_dash[0].metric("Profit Factor", f"{pf_val:.2f}" if pf_val != float('inf') else "∞")
    cols_dash[1].metric(
        "Win vs Loss",
        f"{period_metrics.get('Profitable Trades', 0)} W / {period_metrics.get('Losing Trades', 0)} L",
    )
    cols_dash[2].metric("Avg Win", f"${period_metrics.get('Avg Win', 0):,.2f}")
    cols_dash[3].metric("Avg Loss", f"${period_metrics.get('Avg Loss', 0):,.2f}")

    st.markdown("---")

    # ── Monthly P/L heatmap calendar (with correct weekday alignment) ─────────
    st.subheader("Monthly P/L Heatmap Calendar")
    if not closed_trades.empty:
        calendar_data = (
            closed_trades
            .groupby('Exit Date')
            .agg(PL=('PL', 'sum'), Trades=('Instrument', 'count'))
            .reset_index()
        )
        calendar_data['Date'] = pd.to_datetime(calendar_data['Exit Date'])
        calendar_data['Year']  = calendar_data['Date'].dt.year
        calendar_data['Month'] = calendar_data['Date'].dt.month
        calendar_data['Day']   = calendar_data['Date'].dt.day

        selected_year = st.selectbox("Year", sorted(calendar_data['Year'].unique(), reverse=True))
        year_data = calendar_data[calendar_data['Year'] == selected_year]

        month_cols = st.columns(3)
        for idx, month_num in enumerate(range(1, 13)):
            month_data = year_data[year_data['Month'] == month_num]
            month_name = datetime(selected_year, month_num, 1).strftime("%B")
            # determine what weekday the 1st falls on (0=Mon … 6=Sun)
            first_weekday = datetime(selected_year, month_num, 1).weekday()

            with month_cols[idx % 3]:
                st.markdown(f"**{month_name} {selected_year}**")
                day_labels = st.columns(7)
                for d, lbl in enumerate(['M', 'T', 'W', 'T', 'F', 'S', 'S']):
                    day_labels[d].markdown(f"<center style='color:#7a8fa6;font-size:0.7rem'>{lbl}</center>", unsafe_allow_html=True)

                # build flat grid: None for empty cells, then day numbers
                import calendar as _cal
                _, days_in_month = _cal.monthrange(selected_year, month_num)
                cells = [None] * first_weekday + list(range(1, days_in_month + 1))
                # pad to full weeks
                while len(cells) % 7:
                    cells.append(None)

                pl_lookup = {int(r['Day']): r['PL'] for _, r in month_data.iterrows()}

                for week_start in range(0, len(cells), 7):
                    week_cells = cells[week_start:week_start + 7]
                    week_cols = st.columns(7)
                    for c, day_num in enumerate(week_cells):
                        with week_cols[c]:
                            if day_num is None:
                                st.markdown(
                                    "<div style='background:#0e1117;padding:6px;border-radius:6px;height:44px'></div>",
                                    unsafe_allow_html=True,
                                )
                            elif day_num in pl_lookup:
                                pl = pl_lookup[day_num]
                                bg = '#1a4d2e' if pl > 0 else '#4d1a1a'
                                border = '#00e676' if pl > 0 else '#ff5252'
                                sign = '+' if pl > 0 else ''
                                st.markdown(
                                    f"<div style='background:{bg};border:1px solid {border};"
                                    f"padding:4px 2px;border-radius:6px;text-align:center;"
                                    f"font-size:0.68rem;line-height:1.3'>"
                                    f"<b>{day_num}</b><br>"
                                    f"<span style='color:{border}'>{sign}${pl:,.0f}</span>"
                                    f"</div>",
                                    unsafe_allow_html=True,
                                )
                            else:
                                st.markdown(
                                    f"<div style='background:#1a2235;padding:4px 2px;"
                                    f"border-radius:6px;text-align:center;font-size:0.68rem;"
                                    f"color:#4a5568;line-height:1.3'><b>{day_num}</b><br>&nbsp;</div>",
                                    unsafe_allow_html=True,
                                )

    else:
        st.info("No closed trades to display.")

    st.markdown("---")

    # ── Recent ticker P/L sparklines ─────────────────────────────────────────
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

    st.subheader("Recent Ticker P/L Sparklines")
    cols = st.columns(3)
    for i in range(min(3, len(recent_trades))):
        trade = recent_trades.iloc[i]
        with cols[i]:
            date_str = trade['Date'].strftime('%Y-%m-%d') if pd.notna(trade['Date']) else 'N/A'
            net = sum(trade['PL History'])
            color = '#00e676' if net >= 0 else '#ff5252'
            st.markdown(
                f"**{trade['Instrument']}** &nbsp; <span style='color:{color}'>${net:+,.0f}</span> &nbsp;"
                f"<span style='color:#7a8fa6;font-size:0.8rem'>{date_str}</span>",
                unsafe_allow_html=True,
            )
            fig = px.line(
                y=trade['PL History'], markers=True,
                template="plotly_dark",
                color_discrete_sequence=[color],
            )
            fig.update_layout(
                showlegend=False, height=130,
                margin=dict(l=0, r=0, t=4, b=0),
                paper_bgcolor='#0e1117', plot_bgcolor='#0e1117',
            )
            st.plotly_chart(fig, use_container_width=True, key=f"tab6_sparkline_{i}")

    st.subheader("P/L by Hour of Day")

    if not closed_trades.empty:
        closed_trades['Hour'] = closed_trades['Exit Date'].dt.hour
        hourly_pl = closed_trades.groupby('Hour')['PL'].sum().reset_index()
    else:
        hourly_pl = pd.DataFrame(columns=['Hour', 'PL'])

    fig_hourly = px.bar(
        hourly_pl, x='Hour', y='PL', color='PL',
        color_continuous_scale='RdYlGn',
        title="P/L by Exit Hour",
        template="plotly_dark",
    )
    fig_hourly.update_layout(paper_bgcolor='#0e1117', plot_bgcolor='#0e1117')
    st.plotly_chart(fig_hourly, use_container_width=True, key="tab6_hourly")

    cols = st.columns(4)
    largest_gain = closed_trades['PL'].max() if not closed_trades.empty else 0
    largest_loss = closed_trades['PL'].min() if not closed_trades.empty else 0
    wins_sum  = closed_trades[closed_trades['PL'] > 0]['PL'].sum() if not closed_trades.empty else 0
    losses_sum = abs(closed_trades[closed_trades['PL'] < 0]['PL'].sum()) if not closed_trades.empty else 0
    with cols[0]:
        fig_gauge = go.Figure(go.Indicator(
            mode="gauge+number", value=largest_gain,
            title={'text': "Largest Gain", 'font': {'color': '#00e676'}},
            gauge={'axis': {'range': [0, max(largest_gain, 1)]},
                   'bar': {'color': '#00e676'},
                   'bgcolor': '#1a2235',
                   'bordercolor': '#2a3348'},
            number={'prefix': '$', 'font': {'color': '#00e676'}},
        ))
        fig_gauge.update_layout(paper_bgcolor='#0e1117', font_color='#e8eaf0', height=220)
        st.plotly_chart(fig_gauge, use_container_width=True, key="tab6_gauge")
    with cols[1]:
        fig_donut = px.pie(
            names=['Gross Profit', 'Gross Loss'],
            values=[wins_sum, losses_sum],
            hole=0.45, title="Gross Profit vs Loss",
            color_discrete_sequence=['#00e676', '#ff5252'],
            template="plotly_dark",
        )
        fig_donut.update_layout(paper_bgcolor='#0e1117')
        st.plotly_chart(fig_donut, use_container_width=True, key="tab6_donut")
    with cols[2]:
        rr = period_metrics.get('Risk-Reward Ratio', 0)
        fig_bar_k = px.bar(
            x=['Risk-Reward'], y=[rr if rr != float('inf') else 0],
            title="Risk-Reward Ratio",
            template="plotly_dark",
            color_discrete_sequence=['#00ff9d'],
        )
        fig_bar_k.update_layout(paper_bgcolor='#0e1117', plot_bgcolor='#0e1117')
        st.plotly_chart(fig_bar_k, use_container_width=True, key="tab6_rr_bar")
    with cols[3]:
        st.metric("Largest Single Gain", f"${largest_gain:,.2f}")
        st.metric("Largest Single Loss", f"${largest_loss:,.2f}")


with tab5:
    st.header("Option Strategy Planner")
    st.caption("Live bias, key levels, and actionable option plays for any ticker.")

    # ── Ticker input ──────────────────────────────────────────────────────────
    col_t1, col_t2, col_t3 = st.columns([2, 1, 1])
    with col_t1:
        default_tickers = ["SPY", "QQQ", "AAPL", "NVDA", "TSLA", "AMZN", "META", "MSFT"]
        strat_options = sorted(set(default_tickers + list(instruments)))
        strategy_ticker = st.selectbox("Ticker to Analyze", strat_options, index=0)
    with col_t2:
        dte_pref = st.selectbox("Preferred DTE", ["0DTE (same day)", "1 week (5-7 DTE)", "2 weeks (14 DTE)", "Monthly (30 DTE)"])
    with col_t3:
        st.markdown("<br>", unsafe_allow_html=True)
        analyze_btn = st.button("Run Analysis", use_container_width=True)

    if analyze_btn or True:  # auto-run on load
        with st.spinner(f"Fetching data for {strategy_ticker}..."):
            try:
                tkr = yf.Ticker(strategy_ticker)
                hist_daily = tkr.history(period="60d")
                hist_weekly = tkr.history(period="1y", interval="1wk")
                info = tkr.info if hasattr(tkr, 'info') else {}
            except Exception as e:
                hist_daily = pd.DataFrame()
                hist_weekly = pd.DataFrame()
                info = {}

        if hist_daily.empty or len(hist_daily) < 5:
            st.error(f"Could not fetch data for {strategy_ticker}. Check the ticker symbol.")
        else:
            # ── Compute key values ────────────────────────────────────────────
            closes = hist_daily['Close']
            highs  = hist_daily['High']
            lows   = hist_daily['Low']

            current_price = closes.iloc[-1]
            prev_close    = closes.iloc[-2] if len(closes) >= 2 else closes.iloc[-1]

            # Previous day OHLC
            pdh = highs.iloc[-2]  if len(highs)  >= 2 else highs.iloc[-1]
            pdl = lows.iloc[-2]   if len(lows)   >= 2 else lows.iloc[-1]
            pdc = prev_close

            # Week levels (last 5 sessions)
            week_high = highs.tail(5).max()
            week_low  = lows.tail(5).min()

            # 20 / 50 EMA
            ema20 = closes.ewm(span=20, adjust=False).mean().iloc[-1]
            ema50 = closes.ewm(span=50, adjust=False).mean().iloc[-1]

            # RSI-14
            delta_c = closes.diff()
            gain_c  = delta_c.clip(lower=0).rolling(14).mean()
            loss_c  = (-delta_c.clip(upper=0)).rolling(14).mean()
            rs      = gain_c / loss_c.replace(0, np.nan)
            rsi     = float((100 - 100 / (1 + rs)).iloc[-1])

            # ATR-14
            hl   = highs - lows
            hpc  = (highs - closes.shift()).abs()
            lpc  = (lows  - closes.shift()).abs()
            atr  = float(pd.concat([hl, hpc, lpc], axis=1).max(axis=1).rolling(14).mean().iloc[-1])

            # 52-week H/L
            yr_high = highs.max()
            yr_low  = lows.min()

            # Day change %
            day_chg_pct = (current_price - prev_close) / prev_close * 100

            # ── Bias scoring ──────────────────────────────────────────────────
            bull_signals, bear_signals = [], []

            if current_price > ema20:
                bull_signals.append("Price > 20 EMA")
            else:
                bear_signals.append("Price < 20 EMA")

            if current_price > ema50:
                bull_signals.append("Price > 50 EMA")
            else:
                bear_signals.append("Price < 50 EMA")

            if current_price > pdc:
                bull_signals.append("Trading above prev close")
            else:
                bear_signals.append("Trading below prev close")

            if rsi > 55:
                bull_signals.append(f"RSI bullish ({rsi:.1f})")
            elif rsi < 45:
                bear_signals.append(f"RSI bearish ({rsi:.1f})")

            if current_price > pdh:
                bull_signals.append("Price broke above PDH")
            elif current_price < pdl:
                bear_signals.append("Price broke below PDL")

            if day_chg_pct > 0.3:
                bull_signals.append(f"Up {day_chg_pct:.2f}% today")
            elif day_chg_pct < -0.3:
                bear_signals.append(f"Down {abs(day_chg_pct):.2f}% today")

            b = len(bull_signals)
            br = len(bear_signals)

            if b >= 4:
                bias, bias_strength = "BULLISH", "Strong" if b >= 5 else "Moderate"
                bias_color = "#00e676"
            elif br >= 4:
                bias, bias_strength = "BEARISH", "Strong" if br >= 5 else "Moderate"
                bias_color = "#ff5252"
            elif b > br:
                bias, bias_strength = "BULLISH", "Weak"
                bias_color = "#69f0ae"
            elif br > b:
                bias, bias_strength = "BEARISH", "Weak"
                bias_color = "#ff7575"
            else:
                bias, bias_strength = "NEUTRAL", "Neutral"
                bias_color = "#ffd700"

            # ── Strike helpers ────────────────────────────────────────────────
            def nearest_strike(price, step=1.0):
                return round(round(price / step) * step, 2)

            is_index = strategy_ticker in ('SPX', 'NDX', 'RUT')
            strike_step = 5.0 if strategy_ticker in ('SPY', 'QQQ', 'IWM') else (25.0 if is_index else 2.5 if current_price > 100 else 1.0)
            atm = nearest_strike(current_price, strike_step)
            otm_call_1 = nearest_strike(current_price + atr * 0.5, strike_step)
            otm_put_1  = nearest_strike(current_price - atr * 0.5, strike_step)
            otm_call_2 = nearest_strike(current_price + atr, strike_step)
            otm_put_2  = nearest_strike(current_price - atr, strike_step)

            # DTE mapping
            dte_map = {
                "0DTE (same day)": "0DTE (expires today)",
                "1 week (5-7 DTE)": "~7 DTE (next weekly expiry)",
                "2 weeks (14 DTE)": "~14 DTE",
                "Monthly (30 DTE)": "~30 DTE (front month)",
            }
            dte_label = dte_map.get(dte_pref, "~7 DTE")

            # ── Compute iron condor levels (used for rec play scoring) ──────────
            iron_condor_call_sell = nearest_strike(current_price + atr * 0.75, strike_step)
            iron_condor_put_sell  = nearest_strike(current_price - atr * 0.75, strike_step)

            # ── Recommended Play computation (used for agreement scoring) ─────
            if bias == "BULLISH":
                rec_type   = "BUY CALL"
                rec_strike = otm_call_1 if bias_strength in ("Strong", "Moderate") else atm
                rec_color  = "#00e676"
                rec_entry  = f"Enter on a dip to ${max(pdc, ema20):,.2f}–${pdh:,.2f} zone with a bullish engulfing or hammer candle"
                rec_target1 = f"${nearest_strike(current_price + atr * 0.75, strike_step):,.2f} (+0.75 ATR) — take 50% off"
                rec_target2 = f"${nearest_strike(current_price + atr * 1.5, strike_step):,.2f} (+1.5 ATR) — runner target"
                rec_stop   = f"${nearest_strike(current_price - atr * 0.4, strike_step):,.2f} (close below, cut the trade)"
                rec_note   = f"With RSI at {rsi:.1f}, momentum is {'strong — trail stop after T1' if rsi > 60 else 'moderate — book at T1'}."
            elif bias == "BEARISH":
                rec_type   = "BUY PUT"
                rec_strike = otm_put_1 if bias_strength in ("Strong", "Moderate") else atm
                rec_color  = "#ff5252"
                rec_entry  = f"Enter on a bounce to ${min(pdc, ema20):,.2f}–${pdl:,.2f} zone that fails with a bearish candle"
                rec_target1 = f"${nearest_strike(current_price - atr * 0.75, strike_step):,.2f} (−0.75 ATR) — take 50% off"
                rec_target2 = f"${nearest_strike(current_price - atr * 1.5, strike_step):,.2f} (−1.5 ATR) — runner target"
                rec_stop   = f"${nearest_strike(current_price + atr * 0.4, strike_step):,.2f} (close above, cut the trade)"
                rec_note   = f"RSI at {rsi:.1f}. {'Oversold bounce risk — size smaller.' if rsi < 35 else 'Momentum confirms — press the trade.'}"
            else:
                rec_type   = "IRON CONDOR"
                rec_strike = atm
                rec_color  = "#ffd700"
                rec_entry  = f"Sell strangle: call at ${iron_condor_call_sell:,.2f} / put at ${iron_condor_put_sell:,.2f}"
                rec_target1 = "50% of credit collected"
                rec_target2 = "75% of credit collected — close rest"
                rec_stop   = f"Any breach of short strikes — close the threatened side"
                rec_note   = f"RSI neutral at {rsi:.1f}. Day range expected: ${(current_price-atr*0.6):,.2f}–${(current_price+atr*0.6):,.2f}"

            # ── Grok AI Analysis + Agreement Score ───────────────────────────
            st.subheader("Grok AI Analysis vs Technical Analysis")

            grok_cache_key = f"grok_{strategy_ticker}_{dte_pref}"

            if analyze_btn:
                if not grok_api_key:
                    st.warning("Add your Grok API key in the sidebar to enable AI analysis.")
                else:
                    # Grok receives live yfinance data, provides analytical conclusions
                    auto_prompt = (
                        f"You are an expert options trader. Analyze {strategy_ticker} using the live market data below.\n\n"
                        f"LIVE DATA (from yfinance, accurate as of now):\n"
                        f"Price: ${current_price:.2f} | Day change: {day_chg_pct:+.2f}%\n"
                        f"PDH: ${pdh:.2f} | PDL: ${pdl:.2f} | PDC: ${pdc:.2f}\n"
                        f"Week High: ${week_high:.2f} | Week Low: ${week_low:.2f}\n"
                        f"EMA-20: ${ema20:.2f} | EMA-50: ${ema50:.2f}\n"
                        f"RSI-14: {rsi:.1f} | ATR-14: ${atr:.2f}\n\n"
                        f"Based on this data, provide your expert analysis. "
                        f"Respond ONLY in this exact format with no extra text:\n"
                        f"BIAS: <BULLISH or BEARISH or NEUTRAL> — <1-sentence reason>\n"
                        f"BEST_PLAY: <CALL or PUT or IRON CONDOR> | Strike:<price> | Expiry:{dte_label} | Entry:<price> | T1:<price> | T2:<price> | Stop:<price>\n"
                        f"KEY_LEVELS: <price — why>;<price — why>;<price — why>\n"
                        f"RISKS: <risk1>;<risk2>;<risk3>\n"
                        f"CONVICTION: <number>/10\n"
                        f"REASONING: <2-3 sentences>"
                    )
                    with st.spinner("Grok is independently analyzing..."):
                        conviction, grok_text, _ = run_grok_prompt(
                            ticker=strategy_ticker,
                            custom_prompt=auto_prompt,
                            api_key=grok_api_key,
                        )
                    st.session_state[grok_cache_key] = (conviction, grok_text)

            if grok_cache_key in st.session_state:
                conviction, grok_text = st.session_state[grok_cache_key]

                def _extract(text, key):
                    m = re.search(rf'{key}:\s*(.+?)(?=\n[A-Z_]+:|$)', text, re.DOTALL | re.IGNORECASE)
                    return m.group(1).strip() if m else ""

                s_bias      = _extract(grok_text, "BIAS")
                s_play      = _extract(grok_text, "BEST_PLAY")
                s_levels    = _extract(grok_text, "KEY_LEVELS")
                s_risks     = _extract(grok_text, "RISKS")
                s_conv_raw  = _extract(grok_text, "CONVICTION")
                s_reasoning = _extract(grok_text, "REASONING")

                try:
                    conv_num = int(re.search(r'(\d+)', s_conv_raw).group(1))
                except Exception:
                    conv_num = conviction
                conv_color = "#00e676" if conv_num >= 7 else "#ffd700" if conv_num >= 5 else "#ff5252"

                parsed_ok = any([s_bias, s_play, s_levels])

                if not parsed_ok:
                    st.markdown(
                        f"<div style='background:#0d1b2a;border:2px solid {conv_color};border-radius:14px;padding:20px 24px'>"
                        f"<div style='color:#a78bfa;font-weight:700;margin-bottom:8px'>Grok · {strategy_ticker} — Conviction {conv_num}/10</div>"
                        f"<div style='color:#e8eaf0;font-size:0.92rem;white-space:pre-wrap;line-height:1.6'>{grok_text}</div>"
                        f"</div>",
                        unsafe_allow_html=True,
                    )
                else:
                    # ── Grok Analysis (full width) ─────────────────────────────
                    st.markdown(
                        f"<div style='background:#0d1b2a;border:2px solid {conv_color};border-radius:12px;padding:16px 20px;margin-bottom:12px'>"
                        f"<div style='display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:8px;margin-bottom:10px'>"
                        f"<div style='color:#a78bfa;font-size:0.75rem;text-transform:uppercase;letter-spacing:1px'>Grok AI · {strategy_ticker} · Independent Analysis</div>"
                        f"<span style='background:{conv_color};color:#0e1117;font-weight:900;font-size:0.9rem;padding:4px 14px;border-radius:20px'>Conviction {conv_num}/10</span>"
                        f"</div>"
                        f"<div style='color:#e8eaf0;font-size:1rem;line-height:1.5'>{s_bias}</div>"
                        f"</div>",
                        unsafe_allow_html=True,
                    )
                    # ── Live Technical Data (yfinance — source of truth) ────────
                    tech_badges = [
                        ("PDH",       pdh,       "#ffd700"),
                        ("PDL",       pdl,       "#ffd700"),
                        ("PDC",       pdc,       "#c8d8e8"),
                        ("Week High", week_high, "#00bcd4"),
                        ("Week Low",  week_low,  "#00bcd4"),
                        ("EMA-20",    ema20,     "#a78bfa"),
                        ("EMA-50",    ema50,     "#a78bfa"),
                        ("RSI-14",    rsi,       "#fb923c"),
                        ("ATR-14",    atr,       "#fb923c"),
                    ]
                    badge_html = "".join(
                        f"<div style='background:#1a2235;border:1px solid #2a3348;border-radius:10px;padding:10px 14px;text-align:center'>"
                        f"<div style='color:#7a8fa6;font-size:0.68rem;text-transform:uppercase;letter-spacing:0.5px'>{lbl}</div>"
                        f"<div style='color:{col};font-size:1.1rem;font-weight:700'>${v:,.2f}</div>"
                        f"</div>"
                        for lbl, v, col in tech_badges
                    )
                    st.markdown(
                        f"<div style='margin-bottom:12px'>"
                        f"<div style='color:#38bdf8;font-size:0.72rem;font-weight:700;text-transform:uppercase;letter-spacing:0.5px;margin-bottom:8px'>Live Technical Data (yfinance)</div>"
                        f"<div style='display:grid;grid-template-columns:repeat(9,1fr);gap:8px'>{badge_html}</div>"
                        f"</div>",
                        unsafe_allow_html=True,
                    )

                    if s_play:
                        play_items = [p.strip() for p in s_play.split('|')]
                        opt_type  = play_items[0] if play_items else "—"
                        opt_color = "#00e676" if "CALL" in opt_type.upper() else "#ff5252" if "PUT" in opt_type.upper() else "#ffd700"
                        cells_html = "".join(
                            f"<div style='background:#1a2235;border-radius:6px;padding:10px 12px;text-align:center'>"
                            f"<div style='color:#7a8fa6;font-size:0.65rem;text-transform:uppercase'>{(item.split(':',1)[0] if ':' in item else '').strip()}</div>"
                            f"<div style='color:#e8eaf0;font-weight:700;font-size:0.9rem;margin-top:2px'>{(item.split(':',1)[1] if ':' in item else item).strip()}</div>"
                            f"</div>"
                            for item in play_items[1:]
                        )
                        st.markdown(
                            f"<div style='background:#111827;border:1px solid {opt_color};border-radius:12px;padding:14px 18px;margin-bottom:12px'>"
                            f"<div style='color:{opt_color};font-size:1.1rem;font-weight:800;margin-bottom:10px'>Best Play — {opt_type}</div>"
                            f"<div style='display:grid;grid-template-columns:repeat(auto-fill,minmax(120px,1fr));gap:8px'>{cells_html}</div>"
                            f"</div>",
                            unsafe_allow_html=True,
                        )
                    levels_list = [l.strip() for l in s_levels.split(';') if l.strip()]
                    risks_list  = [r.strip() for r in s_risks.split(';') if r.strip()]
                    glcol1, glcol2 = st.columns(2)
                    with glcol1:
                        lvl_rows = "".join(f"<div style='padding:6px 0;border-bottom:1px solid #1e2d42;color:#e8eaf0;font-size:0.87rem'>📍 {l}</div>" for l in levels_list) or "<div style='color:#7a8fa6'>—</div>"
                        st.markdown(f"<div style='background:#111827;border-radius:10px;padding:14px 18px'><div style='color:#ffd700;font-size:0.72rem;font-weight:700;text-transform:uppercase;margin-bottom:10px'>Key Levels</div>{lvl_rows}</div>", unsafe_allow_html=True)
                    with glcol2:
                        risk_rows = "".join(f"<div style='padding:6px 0;border-bottom:1px solid #1e2d42;color:#e8eaf0;font-size:0.87rem'>⚠️ {r}</div>" for r in risks_list) or "<div style='color:#7a8fa6'>—</div>"
                        st.markdown(f"<div style='background:#111827;border-radius:10px;padding:14px 18px'><div style='color:#fb923c;font-size:0.72rem;font-weight:700;text-transform:uppercase;margin-bottom:10px'>Risks &amp; Catalysts</div>{risk_rows}</div>", unsafe_allow_html=True)
                    if s_reasoning:
                        st.markdown(f"<div style='background:#1a2235;border-radius:10px;padding:12px 16px;margin-top:10px;color:#a0b0c0;font-size:0.87rem;line-height:1.6'>💭 {s_reasoning}</div>", unsafe_allow_html=True)

                    # ── Agreement Score ────────────────────────────────────────
                    st.markdown("---")
                    grok_bias_dir = "BULLISH" if "BULLISH" in s_bias.upper() else "BEARISH" if "BEARISH" in s_bias.upper() else "NEUTRAL"
                    grok_play_dir = "CALL" if ("CALL" in s_play.upper() and "PUT" not in s_play.upper()) else "PUT" if "PUT" in s_play.upper() else "NEUTRAL"
                    yfin_play_dir = "CALL" if "CALL" in rec_type else "PUT" if "PUT" in rec_type else "NEUTRAL"

                    grok_strike_val = None
                    sm = re.search(r'Strike:\s*\$?([\d,]+\.?\d*)', s_play)
                    if sm:
                        try:
                            grok_strike_val = float(sm.group(1).replace(',', ''))
                        except Exception:
                            pass

                    # Bias match
                    bias_match = grok_bias_dir == bias
                    bias_pts   = 30 if bias_match else 0

                    # Play direction match
                    play_match = grok_play_dir == yfin_play_dir
                    play_pts   = 30 if play_match else 0

                    # Strike proximity
                    strike_diff = abs(grok_strike_val - rec_strike) / rec_strike * 100 if grok_strike_val else 999
                    strike_pts  = 20 if strike_diff < 1 else 12 if strike_diff < 3 else 6 if strike_diff < 6 else 0

                    # Agreement: Grok's analytical conclusions vs yfinance-derived signals
                    total = bias_pts + play_pts + strike_pts
                    score_color = "#00e676" if total >= 60 else "#ffd700" if total >= 35 else "#ff5252"
                    score_label = "Strong Agreement" if total >= 60 else "Moderate Agreement" if total >= 35 else "Low Agreement"

                    def _check(ok):
                        return "<span style='color:#00e676'>✔</span>" if ok else "<span style='color:#ff5252'>✘</span>"

                    breakdown_html = (
                        f"<div style='display:grid;grid-template-columns:repeat(3,1fr);gap:10px;margin-top:12px'>"
                        f"<div style='background:#1a2235;border-radius:8px;padding:12px;text-align:center'>"
                        f"<div style='color:#7a8fa6;font-size:0.68rem;text-transform:uppercase'>Bias Direction</div>"
                        f"<div style='font-size:1.2rem;margin-top:4px'>{_check(bias_match)}</div>"
                        f"<div style='color:#a78bfa;font-size:0.78rem;margin-top:4px'>Grok: <b>{grok_bias_dir}</b></div>"
                        f"<div style='color:#38bdf8;font-size:0.78rem'>TA: <b>{bias}</b></div>"
                        f"<div style='color:{score_color};font-size:0.72rem;margin-top:4px'>{bias_pts}/30 pts</div></div>"
                        f"<div style='background:#1a2235;border-radius:8px;padding:12px;text-align:center'>"
                        f"<div style='color:#7a8fa6;font-size:0.68rem;text-transform:uppercase'>Trade Direction</div>"
                        f"<div style='font-size:1.2rem;margin-top:4px'>{_check(play_match)}</div>"
                        f"<div style='color:#a78bfa;font-size:0.78rem;margin-top:4px'>Grok: <b>{grok_play_dir}</b></div>"
                        f"<div style='color:#38bdf8;font-size:0.78rem'>TA: <b>{yfin_play_dir}</b></div>"
                        f"<div style='color:{score_color};font-size:0.72rem;margin-top:4px'>{play_pts}/30 pts</div></div>"
                        f"<div style='background:#1a2235;border-radius:8px;padding:12px;text-align:center'>"
                        f"<div style='color:#7a8fa6;font-size:0.68rem;text-transform:uppercase'>Strike Proximity</div>"
                        f"<div style='font-size:1.2rem;margin-top:4px'>{_check(strike_pts >= 12)}</div>"
                        f"<div style='color:#a78bfa;font-size:0.78rem;margin-top:4px'>Grok: <b>${grok_strike_val:,.2f}</b></div>" if grok_strike_val else
                        f"<div style='color:#7a8fa6;font-size:0.78rem;margin-top:4px'>N/A</div>"
                        f"<div style='color:#38bdf8;font-size:0.78rem'>TA: <b>${rec_strike:,.2f}</b></div>"
                        f"<div style='color:{score_color};font-size:0.72rem;margin-top:4px'>{'±'+f'{strike_diff:.1f}%' if grok_strike_val else 'N/A'} · {strike_pts}/40 pts</div></div>"
                        f"</div>"
                    )

                    st.markdown(
                        f"<div style='background:#0d1b2a;border:2px solid {score_color};border-radius:14px;padding:18px 22px'>"
                        f"<div style='display:flex;align-items:center;justify-content:space-between'>"
                        f"<div>"
                        f"<div style='color:#e8eaf0;font-size:1rem;font-weight:700'>Agreement Score</div>"
                        f"<div style='color:#7a8fa6;font-size:0.75rem;margin-top:2px'>Grok analysis vs yfinance technical signals · same live data</div>"
                        f"</div>"
                        f"<div style='display:flex;align-items:center;gap:12px'>"
                        f"<span style='color:{score_color};font-size:2rem;font-weight:900'>{total}/80</span>"
                        f"<span style='background:{score_color};color:#0e1117;font-weight:800;font-size:0.85rem;padding:4px 14px;border-radius:20px'>{score_label}</span>"
                        f"</div></div>"
                        f"{breakdown_html}"
                        f"</div>",
                        unsafe_allow_html=True,
                    )

                    if s_reasoning:
                        st.markdown(
                            f"<div style='background:#1a2235;border-radius:10px;padding:12px 16px;margin-top:10px;color:#a0b0c0;font-size:0.87rem;line-height:1.6'>💭 {s_reasoning}</div>",
                            unsafe_allow_html=True,
                        )
            else:
                st.info("Click **Run Analysis** to get Grok AI analysis and agreement score.")

            st.markdown("---")

            # ── Price action mini-chart ───────────────────────────────────────
            st.subheader(f"{strategy_ticker} — Recent Price Action with Key Levels")
            fig_price = go.Figure()

            fig_price.add_trace(go.Candlestick(
                x=hist_daily.index,
                open=hist_daily['Open'],
                high=hist_daily['High'],
                low=hist_daily['Low'],
                close=hist_daily['Close'],
                name=strategy_ticker,
                increasing_line_color='#00e676',
                decreasing_line_color='#ff5252',
            ))

            fig_price.add_trace(go.Scatter(
                x=hist_daily.index, y=closes.ewm(span=20, adjust=False).mean(),
                mode='lines', name='20 EMA', line=dict(color='#a78bfa', width=1.5, dash='dot')
            ))
            fig_price.add_trace(go.Scatter(
                x=hist_daily.index, y=closes.ewm(span=50, adjust=False).mean(),
                mode='lines', name='50 EMA', line=dict(color='#fb923c', width=1.5, dash='dash')
            ))

            # Key level lines
            for level, label, color in [
                (pdh, f"PDH ${pdh:,.2f}", "#ffd700"),
                (pdl, f"PDL ${pdl:,.2f}", "#ffd700"),
                (ema20, f"20 EMA ${ema20:,.2f}", "#a78bfa"),
            ]:
                fig_price.add_hline(
                    y=level, line_color=color, line_dash="dash", line_width=1,
                    annotation_text=label, annotation_position="right",
                    annotation_font_color=color,
                )

            fig_price.update_layout(
                template="plotly_dark",
                paper_bgcolor='#0e1117',
                plot_bgcolor='#0e1117',
                height=420,
                xaxis_rangeslider_visible=False,
                margin=dict(l=0, r=80, t=20, b=0),
                legend=dict(orientation="h", yanchor="bottom", y=1.02, xanchor="left", x=0),
            )
            st.plotly_chart(fig_price, use_container_width=True, key="tab7_price_chart")

st.markdown("---")
st.markdown("[Support by Grok](https://x.com/grok)", unsafe_allow_html=True)