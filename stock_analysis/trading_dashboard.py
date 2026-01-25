import streamlit as st
import pandas as pd
import plotly.express as px
import numpy as np
import re
import os
import glob
import yfinance as yf
from datetime import datetime

st.set_page_config(page_title="Crypto Paddler Dashboard", layout="wide", page_icon="📈")
st.title("Crypto Paddler Trading Dashboard – @paddleurway")
st.markdown("Auto-loads **all .csv files** from the current folder, fixes parentheses in Amount, sorts by date, matches BTO (negative) with STC (positive) with tighter contract grouping. Buys before sells on same day.")

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
df.columns = df.columns.str.strip().str.lower().str.replace(' ', '_')  # Normalize
column_map = {
    'process_date': 'Process Date',
    'trade_date': 'Process Date',
    'instrument': 'Instrument',
    'description': 'Description',
    'trans_code': 'trans_code',  # From your screenshot
    'quantity': 'Quantity',
    'price': 'Price',
    'amount': 'Amount'
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

# Strip non-numeric from Quantity (e.g., '7S' → 7.0)
df['Quantity'] = pd.to_numeric(df['Quantity'].astype(str).str.replace(r'[^0-9.]', '', regex=True), errors='coerce').abs()

df['Price'] = pd.to_numeric(df['Price'], errors='coerce')

# Impute Amount=0 for OEXP/expiration rows if NaN (worthless)
mask_exp = df['trans_code'].str.upper().str.contains('OEXP|EXP', na=False) | df['Description'].str.lower().str.contains('expiration', na=False)
df.loc[mask_exp & df['Amount'].isna(), 'Amount'] = 0.0

# Back-calculate or set Price=0 for expirations
df.loc[mask_exp & df['Price'].isna(), 'Price'] = 0.0
df['Price'] = df['Price'].fillna(abs(df['Amount']) / (df['Quantity'] * 100 + 1e-6))

df = df.sort_values('Process Date').reset_index(drop=True)
df['Cum PL'] = df['Amount'].cumsum()

# ── Parse Option Details ─────────────────────────────────────────────────────
def parse_option_details(desc):
    if pd.isna(desc):
        return 'Unknown', None, None
    desc = str(desc).lower()
    opt_type = 'Put' if 'put' in desc else 'Call' if 'call' in desc else 'Other'
    exp = re.search(r'(\d{1,2}/\d{1,2}/\d{4})', desc).group(1) if re.search(r'(\d{1,2}/\d{1,2}/\d{4})', desc) else None
    strike = float(re.search(r'\$(\d+\.?\d*)', desc).group(1)) if re.search(r'\$(\d+\.?\d*)', desc) else None
    return opt_type, exp, strike

parsed = df['Description'].apply(parse_option_details)
df['Option Type'] = [p[0] for p in parsed]
df['Expiration'] = [p[1] for p in parsed]
df['Strike'] = [p[2] for p in parsed]

# ── Sidebar Filters ──────────────────────────────────────────────────────────
st.sidebar.header("Filters")
instruments = sorted(df['Instrument'].dropna().unique())
selected_instr = st.sidebar.multiselect("Instruments", instruments, default=instruments)
date_min = df['Process Date'].min().date() if pd.notna(df['Process Date'].min()) else None
date_max = df['Process Date'].max().date() if pd.notna(df['Process Date'].max()) else None
start_date = st.sidebar.date_input("Start Date", value=date_min)
end_date = st.sidebar.date_input("End Date", value=date_max)
include_unmatched = st.sidebar.checkbox("Include unmatched sells in P/L?", value=True)

filtered_df = df[
    (df['Instrument'].isin(selected_instr)) &
    (df['Process Date'].dt.date >= start_date) &
    (df['Process Date'].dt.date <= end_date)
].copy()

# ── Trade Matching ───────────────────────────────────────────────────────────
def match_trades(df):
    df = df.dropna(subset=['Quantity', 'Instrument', 'Process Date']).copy()  # Relaxed dropna: allow Price/Amount NaN for expirations
    trades = []
    open_positions = []

    group_keys = ['Instrument', 'Option Type', 'Expiration', 'Strike']

    for keys, group in df.groupby(group_keys, dropna=False):
        # Sort by date, then buys before sells (allow cross-day for expirations)
        group = group.sort_values(by=['Process Date', 'Amount'], ascending=[True, True])
        entry_queue = []  # open buys

        for _, row in group.iterrows():
            qty = row['Quantity']
            price = row.get('Price', 0.0)  # Default 0 if NaN
            date = row['Process Date']
            amount = row.get('Amount', 0.0)  # Default 0 if NaN
            trans_code = str(row.get('trans_code', '')).upper()
            desc = str(row.get('Description', '')).lower()

            if 'oexp' in trans_code or 'exp' in trans_code or 'expiration' in desc:  # Handle expiration as close @0 (worthless)
                # Force price=0 for expiration
                price = 0
                qty_to_match = qty
                i = 0
                while qty_to_match > 0 and i < len(entry_queue):
                    entry = entry_queue[i]
                    match_qty = min(entry['qty'], qty_to_match)
                    pl = (price - entry['price']) * match_qty * 100  # Loss to zero for longs
                    trades.append({
                        'Instrument': row['Instrument'],
                        'Option Type': row['Option Type'],
                        'Expiration': row['Expiration'],
                        'Strike': row['Strike'],
                        'Entry Date': entry['date'],
                        'Exit Date': date,
                        'Quantity Closed': match_qty,
                        'Entry Price': entry['price'],
                        'Exit Price': price,
                        'PL': pl,
                        'Holding Hours': (date - entry['date']).total_seconds() / 3600,
                        'Match Type': 'Expired'
                    })
                    entry['qty'] -= match_qty
                    qty_to_match -= match_qty
                    if entry['qty'] <= 0:
                        entry_queue.pop(i)
                    else:
                        i += 1
                if qty_to_match > 0:
                    st.sidebar.warning(f"Unmatched expiration qty for {keys}: {qty_to_match}")
                continue  # Skip the rest for expiration rows

            if amount < 0:  # BTO / Buy
                entry_queue.append({'qty': qty, 'price': price, 'date': date})
            elif amount > 0:  # STC / Sell
                qty_to_match = qty
                i = 0
                while qty_to_match > 0 and i < len(entry_queue):
                    entry = entry_queue[i]
                    match_qty = min(entry['qty'], qty_to_match)
                    pl = (price - entry['price']) * match_qty * 100
                    trades.append({
                        'Instrument': row['Instrument'],
                        'Option Type': row['Option Type'],
                        'Expiration': row['Expiration'],
                        'Strike': row['Strike'],
                        'Entry Date': entry['date'],
                        'Exit Date': date,
                        'Quantity Closed': match_qty,
                        'Entry Price': entry['price'],
                        'Exit Price': price,
                        'PL': pl,
                        'Holding Hours': (date - entry['date']).total_seconds() / 3600,
                        'Match Type': 'Matched'
                    })
                    entry['qty'] -= match_qty
                    qty_to_match -= match_qty
                    if entry['qty'] <= 0:
                        entry_queue.pop(i)
                    else:
                        i += 1
                if qty_to_match > 0:
                    trades.append({
                        'Instrument': row['Instrument'],
                        'Option Type': row['Option Type'],
                        'Expiration': row['Expiration'],
                        'Strike': row['Strike'],
                        'Entry Date': None,
                        'Exit Date': date,
                        'Quantity Closed': qty_to_match,
                        'Entry Price': None,
                        'Exit Price': price,
                        'PL': amount,
                        'Holding Hours': None,
                        'Match Type': 'Unmatched Sell'
                    })

        # Remaining opens
        for entry in entry_queue:
            open_positions.append({
                'Instrument': keys[0],
                'Option Type': keys[1],
                'Expiration': keys[2],
                'Strike': keys[3],
                'Entry Date': entry['date'],
                'Quantity Open': entry['qty'],
                'Avg Entry Price': entry['price']
            })

    trades_df = pd.DataFrame(trades)
    open_df = pd.DataFrame(open_positions)
    return trades_df, open_df

trades_df, open_df = match_trades(filtered_df)
st.sidebar.write(f"**Matched closed trades: {len(trades_df)}**")
st.sidebar.write(f"**Open positions (unmatched buys): {len(open_df)}**")

# Optional: Filter unmatched
if not include_unmatched:
    trades_df = trades_df[trades_df['Match Type'] != 'Unmatched Sell']

# ── Metrics ──────────────────────────────────────────────────────────────────
def calculate_trade_metrics(trades_df):
    if trades_df.empty:
        return {'Status': 'No closed trades matched – check dates, signs, or parsing'}
    total_pl = trades_df['PL'].sum()
    trades = len(trades_df)
    wins = trades_df[trades_df['PL'] > 0]
    losses = trades_df[trades_df['PL'] < 0]
    win_rate = len(wins) / trades * 100 if trades > 0 else 0
    avg_win = wins['PL'].mean() if len(wins) > 0 else 0
    avg_loss = losses['PL'].mean() if len(losses) > 0 else 0
    risk_reward_ratio = abs(avg_win / avg_loss) if avg_loss != 0 else np.inf
    profit_factor = abs(wins['PL'].sum() / losses['PL'].sum()) if len(losses) > 0 and losses['PL'].sum() != 0 else np.inf
    cum_pl = trades_df['PL'].cumsum()
    max_dd = (cum_pl - cum_pl.cummax()).min() if not cum_pl.empty else 0
    expectancy = (win_rate / 100 * avg_win) + ((1 - win_rate / 100) * avg_loss)
    return {
        'Total P/L': total_pl,
        'Closed Trades': trades,
        'Win Rate %': win_rate,
        'Avg Win': avg_win,
        'Avg Loss': avg_loss,
        'Risk-Reward Ratio': risk_reward_ratio,
        'Profit Factor': profit_factor,
        'Max Drawdown': max_dd,
        'Expectancy': expectancy
    }

metrics = calculate_trade_metrics(trades_df)

# ── Unrealized P/L Integration ───────────────────────────────────────────────
def fetch_current_option_price(instrument, option_type, expiration, strike):
    # Convert expiration to yfinance format YYYY-MM-DD
    try:
        exp_date = datetime.strptime(expiration, '%m/%d/%Y').strftime('%Y-%m-%d')
        ticker = yf.Ticker(instrument)
        chain = ticker.option_chain(exp_date)
        if option_type == 'Call':
            opts = chain.calls
        else:
            opts = chain.puts
        opt = opts[opts['strike'] == strike]
        if not opt.empty:
            return opt['lastPrice'].values[0]  # Use lastPrice as estimate
        else:
            return np.nan
    except Exception as e:
        st.warning(f"Failed to fetch price for {instrument} {option_type} {exp_date} ${strike}: {e}")
        return np.nan

if not open_df.empty:
    if st.sidebar.button("Fetch Current Prices for Unrealized P/L"):
        open_df['Current Price'] = open_df.apply(lambda row: fetch_current_option_price(row['Instrument'], row['Option Type'], row['Expiration'], row['Strike']), axis=1)
        open_df['Unrealized P/L'] = (open_df['Current Price'] - open_df['Avg Entry Price']) * open_df['Quantity Open'] * 100
        total_unrealized = open_df['Unrealized P/L'].sum()
    else:
        open_df['Current Price'] = np.nan
        open_df['Unrealized P/L'] = np.nan
        total_unrealized = 0.0
else:
    total_unrealized = 0.0

# ── Tabs ─────────────────────────────────────────────────────────────────────
tab1, tab2, tab3, tab4 = st.tabs(["Overview", "Metrics", "Charts", "Data"])

with tab1:
    st.header("Overview")
    cols = st.columns(5)
    cols[0].metric("Total Realized P/L", f"${metrics.get('Total P/L', 0):,.2f}")
    cols[1].metric("Total Unrealized P/L", f"${total_unrealized:,.2f}")
    cols[2].metric("Closed Trades", metrics.get('Closed Trades', 0))
    cols[3].metric("Win Rate", f"{metrics.get('Win Rate %', 0):.1f}%")
    cols[4].metric("Expectancy", f"${metrics.get('Expectancy', 0):,.2f}")

    if not trades_df.empty:
        # Stacked column chart for equity curve (P/L per ticker per date)
        pl_per_date_ticker = trades_df.groupby(['Exit Date', 'Instrument'])['PL'].sum().reset_index()
        fig_stack = px.bar(pl_per_date_ticker, x='Exit Date', y='PL', color='Instrument', title="Stacked P/L by Ticker and Date")
        st.plotly_chart(fig_stack, use_container_width=True)

    if not open_df.empty:
        st.subheader("Open Positions")
        st.dataframe(open_df.style.format({"Avg Entry Price": "${:,.2f}", "Quantity Open": "{:.0f}", "Current Price": "${:,.2f}", "Unrealized P/L": "${:,.2f}"}))

with tab2:
    st.header("Detailed Metrics")
    if 'Status' in metrics:
        st.warning(metrics['Status'])
    else:
        metrics_display = metrics.copy()
        metrics_display['Total P/L'] = f"${metrics['Total P/L']:,.2f}"
        metrics_display['Avg Win'] = f"${metrics['Avg Win']:,.2f}"
        metrics_display['Avg Loss'] = f"${metrics['Avg Loss']:,.2f}"
        metrics_display['Risk-Reward Ratio'] = f"{metrics['Risk-Reward Ratio']:.2f}" if np.isfinite(metrics['Risk-Reward Ratio']) else "∞"
        metrics_display['Max Drawdown'] = f"${metrics['Max Drawdown']:,.2f}"
        metrics_display['Expectancy'] = f"${metrics['Expectancy']:,.2f}"
        metrics_display['Win Rate %'] = f"{metrics['Win Rate %']:.1f}%"
        metrics_display['Profit Factor'] = f"{metrics['Profit Factor']:.2f}x" if np.isfinite(metrics['Profit Factor']) else "∞"
        metrics_display['Closed Trades'] = int(metrics['Closed Trades'])
        st.table(pd.DataFrame(list(metrics_display.items()), columns=["Metric", "Value"]))

with tab3:
    st.header("Charts")
    if filtered_df.empty:
        st.warning("No data")
    else:
        pl_by_ticker = filtered_df.groupby('Instrument')['Amount'].sum().reset_index()
        pl_by_ticker['Color'] = np.where(pl_by_ticker['Amount'] > 0, 'Profit', 'Loss')
        fig_bar = px.bar(pl_by_ticker, x='Instrument', y='Amount', title="Raw P/L by Instrument",
                         color='Color', color_discrete_map={'Profit': 'green', 'Loss': 'red'})
        st.plotly_chart(fig_bar, use_container_width=True)
        
        if not trades_df.empty:
            fig_box = px.box(trades_df, y='PL', title="Box Plot of Trade P/L", points="all")
            st.plotly_chart(fig_box, use_container_width=True)
            
            # Tree Map
            treemap_data = trades_df.groupby('Instrument')['PL'].sum().reset_index()
            treemap_data['Absolute PL'] = treemap_data['PL'].abs()
            treemap_data['Color'] = np.where(treemap_data['PL'] > 0, 'Profit', 'Loss')
            fig_tree = px.treemap(treemap_data, path=['Color', 'Instrument'], values='Absolute PL',
                                  color='PL', color_continuous_scale='RdYlGn', title="Tree Map of P/L by Instrument")
            st.plotly_chart(fig_tree, use_container_width=True)

with tab4:
    st.header("Raw & Matched Data")
    st.subheader("Raw Transactions")
    st.dataframe(filtered_df.style.format({
        "Amount": "${:,.2f}",
        "Cum PL": "${:,.2f}",
        "Process Date": "{:%Y-%m-%d}"
    }))

    if not trades_df.empty:
        st.subheader("Matched Closed Positions")
        st.dataframe(trades_df.style.format({
            "PL": "${:,.2f}",
            "Holding Hours": "{:.1f}",
            "Entry Price": "${:,.2f}",
            "Exit Price": "${:,.2f}"
        }))
    else:
        st.info("No matched closed trades. Check if Prices are filled correctly.")

# ── Sidebar Metrics ──────────────────────────────────────────────────────────
st.sidebar.header("Key Trading Metrics")
if not trades_df.empty:
    trades_df['Date'] = trades_df['Exit Date'].dt.date
    trades_df['Month'] = trades_df['Exit Date'].dt.to_period('M').dt.to_timestamp()
    trades_df['Cost Basis'] = trades_df['Entry Price'] * trades_df['Quantity Closed'] * 100
    trades_df['% Return'] = trades_df['PL'] / trades_df['Cost Basis'] * 100

    # Group by contract for aggregated % return (to handle splits)
    contract_group = trades_df.groupby(['Instrument', 'Option Type', 'Expiration', 'Strike'])
    agg_pl = contract_group['PL'].sum()
    agg_cost = contract_group['Cost Basis'].sum()
    agg_pct_return = (agg_pl / agg_cost) * 100

    # Highest % winner (contract level)
    max_pct = agg_pct_return.max()
    max_pct_contract = agg_pct_return.idxmax() if not np.isnan(max_pct) else None

    # Lowest % loser (contract level)
    min_pct = agg_pct_return.min()
    min_pct_contract = agg_pct_return.idxmin() if not np.isnan(min_pct) else None

    st.sidebar.metric("Highest % Winner (Contract)", f"{max_pct:.2f}% ({max_pct_contract[0] if max_pct_contract else 'N/A'})")
    st.sidebar.metric("Lowest % Loser (Contract)", f"{min_pct:.2f}% ({min_pct_contract[0] if min_pct_contract else 'N/A'})")

    # Brainstormed additional metrics
    st.sidebar.metric("Avg Holding Hours", f"{trades_df['Holding Hours'].mean():.1f}")
    st.sidebar.metric("Largest Win ($)", f"${trades_df['PL'].max():,.2f}")
    st.sidebar.metric("Largest Loss ($)", f"${trades_df['PL'].min():,.2f}")
    st.sidebar.metric("Trades per Day (Avg)", f"{len(trades_df) / (trades_df['Exit Date'].max() - trades_df['Exit Date'].min()).days:.1f}" if (trades_df['Exit Date'].max() - trades_df['Exit Date'].min()).days > 0 else "N/A")
else:
    st.sidebar.write("No trades to compute metrics.")

st.markdown("---")
st.caption("Updated: Adjusted % return for winners/losers at contract level (aggregated splits) + based on buy/sell prices")