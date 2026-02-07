from __future__ import annotations
import pandas as pd
import numpy as np
import streamlit as st
import plotly.express as px

def _ensure_exit_date(df: pd.DataFrame) -> pd.DataFrame:
    if df is None or df.empty:
        return pd.DataFrame(columns=["Exit Date", "PL", "Instrument"])
    out = df.copy()
    out["Exit Date"] = pd.to_datetime(out["Exit Date"], errors="coerce")
    return out.dropna(subset=["Exit Date"])

def render_calendar_tab(closed_trades: pd.DataFrame):
    st.header("Calendar View")

    ct = _ensure_exit_date(closed_trades)
    if ct.empty:
        st.info("No closed trades in the selected period.")
        return

    mode = st.radio("View", ["Monthly", "Weekly", "Yearly"], horizontal=True)

    # aggregate daily
    daily = ct.groupby(ct["Exit Date"].dt.date).agg(
        PL=("PL", "sum"),
        Trades=("Instrument", "count")
    ).reset_index().rename(columns={"Exit Date": "Date"})
    daily["Date"] = pd.to_datetime(daily["Date"])

    if mode == "Monthly":
        # pick month
        daily["Month"] = daily["Date"].dt.to_period("M").astype(str)
        month = st.selectbox("Month", sorted(daily["Month"].unique()), index=len(daily["Month"].unique())-1)
        dm = daily[daily["Month"] == month].copy()
        dm["dow"] = dm["Date"].dt.weekday  # Mon=0
        dm["week"] = dm["Date"].dt.isocalendar().week.astype(int)

        # build a month grid (weeks x dow)
        pivot_val = dm.pivot_table(index="week", columns="dow", values="PL", aggfunc="sum")
        pivot_trd = dm.pivot_table(index="week", columns="dow", values="Trades", aggfunc="sum")

        # ensure 0..6 columns exist
        for c in range(7):
            if c not in pivot_val.columns:
                pivot_val[c] = np.nan
            if c not in pivot_trd.columns:
                pivot_trd[c] = np.nan
        pivot_val = pivot_val.sort_index()[list(range(7))]
        pivot_trd = pivot_trd.sort_index()[list(range(7))]

        # labels for hover
        # Map each cell to actual date if exists
        date_map = dm.set_index(["week", "dow"])["Date"].to_dict()
        hover = []
        for w in pivot_val.index:
            row = []
            for d in range(7):
                dt = date_map.get((w, d))
                pl = pivot_val.loc[w, d]
                tr = pivot_trd.loc[w, d]
                if pd.isna(dt):
                    row.append("")
                else:
                    row.append(f"{dt.date()}<br>PL: {pl:,.2f}<br>Trades: {int(tr) if not pd.isna(tr) else 0}")
            hover.append(row)

        fig = px.imshow(
            pivot_val,
            aspect="auto",
            labels=dict(x="Day", y="Week", color="P/L"),
        )
        fig.update_traces(hovertemplate="%{customdata}", customdata=hover)
        fig.update_xaxes(
            tickmode="array",
            tickvals=list(range(7)),
            ticktext=["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"],
        )
        fig.update_layout(title=f"Monthly P/L Heatmap — {month}")
        st.plotly_chart(fig, use_container_width=True)

        st.subheader("Daily details (month)")
        st.dataframe(dm[["Date", "PL", "Trades"]].sort_values("Date"), use_container_width=True)

    elif mode == "Weekly":
        # pick week
        daily["Year"] = daily["Date"].dt.year
        daily["ISOWeek"] = daily["Date"].dt.isocalendar().week.astype(int)
        daily["YearWeek"] = daily["Year"].astype(str) + "-W" + daily["ISOWeek"].astype(str).str.zfill(2)

        yw = st.selectbox("Week", sorted(daily["YearWeek"].unique()), index=len(daily["YearWeek"].unique())-1)
        dw = daily[daily["YearWeek"] == yw].copy()
        dw["dow"] = dw["Date"].dt.weekday

        fig = px.bar(dw.sort_values("Date"), x="Date", y="PL", title=f"Weekly P/L — {yw}")
        st.plotly_chart(fig, use_container_width=True)

        st.subheader("Daily details (week)")
        st.dataframe(dw[["Date", "PL", "Trades"]].sort_values("Date"), use_container_width=True)

    else:  # Yearly
        daily["Year"] = daily["Date"].dt.year
        year = st.selectbox("Year", sorted(daily["Year"].unique()), index=len(daily["Year"].unique())-1)
        dy = daily[daily["Year"] == year].copy()
        dy["Month"] = dy["Date"].dt.to_period("M").astype(str)

        monthly = dy.groupby("Month").agg(PL=("PL", "sum"), Trades=("Trades", "sum")).reset_index()
        fig = px.bar(monthly, x="Month", y="PL", title=f"Monthly P/L — {year}")
        st.plotly_chart(fig, use_container_width=True)

        st.subheader("Monthly details (year)")
        st.dataframe(monthly, use_container_width=True)
