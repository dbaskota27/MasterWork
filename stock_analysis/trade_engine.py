from __future__ import annotations
import pandas as pd
import numpy as np

def match_trades(df: pd.DataFrame, warn_func=None):
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

                if qty_to_match > 0 and warn_func:
                    warn_func(f"Unmatched expiration qty for {keys}: {qty_to_match}")
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

    return pd.DataFrame(trades), pd.DataFrame(open_positions)

def calculate_trade_metrics(trades_df: pd.DataFrame):
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
        'Total P/L': total_pl,
        'Closed Trades': trades,
        'Win Rate %': win_rate,
        'Avg Win': avg_win,
        'Avg Loss': avg_loss,
        'Risk-Reward Ratio': risk_reward,
        'Profit Factor': profit_factor,
        'Max Drawdown': max_dd,
        'Expectancy': expectancy,
        'Profitable Trades': len(wins),
        'Losing Trades': len(losses),
    }

def calculate_sell_order_stats(closed_trades: pd.DataFrame) -> pd.DataFrame:
    if closed_trades.empty:
        return pd.DataFrame()

    longs = closed_trades[closed_trades['Position Type'] == 'Long'].copy()
    if longs.empty:
        return pd.DataFrame()

    longs['Buy Key'] = (
        longs['Entry Date'].astype(str) + '_' +
        longs['Instrument'].astype(str) + '_' +
        longs['Expiration'].astype(str) + '_' +
        longs['Strike'].astype(str) + '_' +
        longs['Entry Price'].astype(str)
    )

    stats = []
    for _, group in longs.groupby('Buy Key'):
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
