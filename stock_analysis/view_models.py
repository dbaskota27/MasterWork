import pandas as pd

def build_calendar_data(closed_trades):
    if closed_trades.empty:
        return pd.DataFrame(columns=['Date', 'PL', 'Trades'])

    df = closed_trades.groupby('Exit Date').agg(
        PL=('PL', 'sum'),
        Trades=('Instrument', 'count')
    ).reset_index()

    df.rename(columns={'Exit Date': 'Date'}, inplace=True)
    return df
