from __future__ import annotations
import numpy as np

def yfinance_available() -> bool:
    try:
        import yfinance  # noqa
        return True
    except Exception:
        return False

def fetch_current_stock_price(symbol: str):
    try:
        import yfinance as yf
        ticker = yf.Ticker(symbol)
        hist = ticker.history(period="1d")
        if not hist.empty:
            return float(hist['Close'].iloc[-1])
        return np.nan
    except Exception:
        return np.nan

def fetch_current_option_price(row):
    import numpy as np
    from datetime import datetime
    try:
        import yfinance as yf
    except Exception:
        return np.nan

    if any([row.get('Instrument') is None, row.get('Option Type') is None, row.get('Expiration') is None, row.get('Strike') is None]):
        return np.nan

    try:
        exp_date = datetime.strptime(row['Expiration'], '%m/%d/%Y').strftime('%Y-%m-%d')
        ticker = yf.Ticker(row['Instrument'])
        chain = ticker.option_chain(exp_date)
        opts = chain.calls if row['Option Type'] == 'Call' else chain.puts
        opt = opts[opts['strike'] == row['Strike']]
        return float(opt['lastPrice'].values[0]) if not opt.empty else np.nan
    except Exception:
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
