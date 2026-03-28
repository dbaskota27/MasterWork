import streamlit as st
import pandas as pd
import altair as alt
from datetime import date, timedelta
import database as db
from config import CURRENCY
from auth import require_login, require_manager

st.set_page_config(page_title="Reports", page_icon="📊", layout="wide")
require_login()
require_manager()
st.title("📊 Reports")

tab_sales, tab_inv, tab_cust, tab_products = st.tabs([
    "Sales Report", "Inventory Report", "Customer Report", "Top Products"
])

# ─── Sales Report ─────────────────────────────────────────────────────────────
with tab_sales:
    st.subheader("Sales Report")

    c1, c2, c3 = st.columns([2, 2, 2])
    start = c1.date_input("From", value=date.today() - timedelta(days=30))
    end   = c2.date_input("To",   value=date.today())
    group = c3.selectbox("Group by", ["Day", "Week", "Month"])

    invoices = db.get_invoices_by_date(start.isoformat(), end.isoformat())

    if invoices:
        df = pd.DataFrame(invoices)
        df["date"]    = pd.to_datetime(df["created_at"]).dt.date
        df["total"]   = df["total"].astype(float)
        df["discount"]= df.get("discount", pd.Series([0]*len(df))).fillna(0).astype(float)

        total_rev  = df["total"].sum()
        total_disc = df["discount"].sum()
        avg_sale   = df["total"].mean()
        num_sales  = len(df)

        m1, m2, m3, m4 = st.columns(4)
        m1.metric("Total Revenue",  f"{CURRENCY}{total_rev:,.2f}")
        m2.metric("Total Sales",    num_sales)
        m3.metric("Avg Sale",       f"{CURRENCY}{avg_sale:.2f}")
        m4.metric("Total Discounts",f"{CURRENCY}{total_disc:.2f}")

        # Daily / weekly / monthly chart
        df["period"] = pd.to_datetime(df["date"])
        if group == "Week":
            df["period"] = df["period"].dt.to_period("W").dt.start_time
        elif group == "Month":
            df["period"] = df["period"].dt.to_period("M").dt.start_time

        grouped = df.groupby("period")["total"].sum().reset_index()
        grouped.columns = ["Period", "Revenue"]

        chart = alt.Chart(grouped).mark_bar(color="#007bff").encode(
            x=alt.X("Period:T", title=group),
            y=alt.Y("Revenue:Q", title=f"Revenue ({CURRENCY})"),
            tooltip=["Period:T", alt.Tooltip("Revenue:Q", format=".2f")]
        ).properties(title=f"Revenue by {group}", height=300)
        st.altair_chart(chart, use_container_width=True)

        # Payment method breakdown
        if "payment_method" in df.columns:
            st.subheader("By Payment Method")
            pm = df.groupby("payment_method").agg(
                Revenue=("total", "sum"),
                Count=("total", "count")
            ).reset_index().rename(columns={"payment_method": "Method"})

            c1, c2 = st.columns(2)
            with c1:
                st.dataframe(pm, use_container_width=True)
            with c2:
                pie = alt.Chart(pm).mark_arc(innerRadius=50).encode(
                    theta=alt.Theta("Revenue:Q"),
                    color=alt.Color("Method:N"),
                    tooltip=["Method:N", alt.Tooltip("Revenue:Q", format=".2f"), "Count:Q"]
                ).properties(height=250)
                st.altair_chart(pie, use_container_width=True)

        st.subheader("Invoice Details")
        show = [c for c in ["invoice_number","customer_name","total","discount","payment_method","status","date"] if c in df.columns]
        st.dataframe(df[show].sort_values("date", ascending=False).rename(columns={
            "invoice_number":"Invoice #","customer_name":"Customer",
            "total":f"Total({CURRENCY})","discount":"Disc","payment_method":"Payment",
            "status":"Status","date":"Date"
        }), use_container_width=True)
    else:
        st.info("No sales in the selected date range.")

# ─── Inventory Report ─────────────────────────────────────────────────────────
with tab_inv:
    st.subheader("Inventory Report")
    products = db.get_products()

    if products:
        df = pd.DataFrame(products)
        df["cost_price"]      = df["cost_price"].astype(float)
        df["sell_price"]      = df["sell_price"].astype(float)
        df["stock_qty"]       = df["stock_qty"].astype(int)
        df["cost_value"]      = df["cost_price"]  * df["stock_qty"]
        df["retail_value"]    = df["sell_price"]  * df["stock_qty"]
        df["potential_profit"]= df["retail_value"] - df["cost_value"]
        df["min_stock"]       = df["min_stock"].fillna(5).astype(int)

        total_cost   = df["cost_value"].sum()
        total_retail = df["retail_value"].sum()
        low_stock    = df[df["stock_qty"] <= df["min_stock"]]
        out_of_stock = df[df["stock_qty"] == 0]

        m1, m2, m3, m4 = st.columns(4)
        m1.metric("Inventory Cost Value",    f"{CURRENCY}{total_cost:,.2f}")
        m2.metric("Inventory Retail Value",  f"{CURRENCY}{total_retail:,.2f}")
        m3.metric("Low / Out of Stock",      f"{len(low_stock)} / {len(out_of_stock)}")
        m4.metric("Potential Profit",        f"{CURRENCY}{(total_retail-total_cost):,.2f}")

        if not out_of_stock.empty:
            st.error("🚫 Out of Stock Items")
            oos_cols = [c for c in ["name","brand","model","sell_price"] if c in out_of_stock.columns]
            st.dataframe(out_of_stock[oos_cols], use_container_width=True)

        if not low_stock[low_stock["stock_qty"] > 0].empty:
            st.warning("⚠️ Low Stock Items")
            ls = low_stock[low_stock["stock_qty"] > 0]
            ls_cols = [c for c in ["name","brand","stock_qty","min_stock","sell_price"] if c in ls.columns]
            st.dataframe(ls[ls_cols], use_container_width=True)

        st.subheader("Full Inventory")
        full_cols = [c for c in ["name","brand","model","cost_price","sell_price","stock_qty","cost_value","retail_value","potential_profit"] if c in df.columns]
        st.dataframe(df[full_cols].sort_values("stock_qty").rename(columns={
            "name":"Product","brand":"Brand","model":"Model",
            "cost_price":f"Cost({CURRENCY})","sell_price":f"Price({CURRENCY})",
            "stock_qty":"Stock","cost_value":f"Cost Val","retail_value":f"Retail Val",
            "potential_profit":f"Pot. Profit"
        }), use_container_width=True)
    else:
        st.info("No products in inventory.")

# ─── Customer Report ──────────────────────────────────────────────────────────
with tab_cust:
    st.subheader("Customer Report")
    customers = db.get_customers()
    invoices  = db.get_invoices()

    if customers:
        rows = []
        for c in customers:
            c_invs = [i for i in invoices if i.get("customer_id") == c["id"]]
            spent  = sum(float(i["total"]) for i in c_invs)
            rows.append({
                "Customer":      c["name"],
                "Phone":         c.get("phone") or "",
                "Purchases":     len(c_invs),
                f"Total Spent":  spent,
                "Avg Purchase":  spent / len(c_invs) if c_invs else 0,
                "Last Visit":    max((i["created_at"][:10] for i in c_invs), default="Never")
            })

        df_c = pd.DataFrame(rows).sort_values("Total Spent", ascending=False)

        m1, m2, m3 = st.columns(3)
        m1.metric("Total Customers", len(customers))
        m2.metric("Revenue from Customers", f"{CURRENCY}{df_c['Total Spent'].sum():,.2f}")
        m3.metric("Top Customer", df_c.iloc[0]["Customer"] if not df_c.empty else "—")

        st.dataframe(df_c, use_container_width=True)
    else:
        st.info("No customer data yet.")

# ─── Top Products ─────────────────────────────────────────────────────────────
with tab_products:
    st.subheader("Top Selling Products")
    all_items = db.get_all_invoice_items()

    if all_items:
        df_items = pd.DataFrame(all_items)
        df_items["total_price"] = df_items["total_price"].astype(float)
        df_items["quantity"]    = df_items["quantity"].astype(int)

        top = (df_items.groupby("product_name")
               .agg(Units_Sold=("quantity","sum"), Revenue=("total_price","sum"))
               .reset_index()
               .sort_values("Revenue", ascending=False)
               .head(20))
        top.columns = ["Product", "Units Sold", f"Revenue ({CURRENCY})"]

        bar = alt.Chart(top).mark_bar(color="#28a745").encode(
            x=alt.X(f"Revenue ({CURRENCY}):Q"),
            y=alt.Y("Product:N", sort="-x"),
            tooltip=["Product:N", "Units Sold:Q", alt.Tooltip(f"Revenue ({CURRENCY}):Q", format=".2f")]
        ).properties(title="Top 20 Products by Revenue", height=500)
        st.altair_chart(bar, use_container_width=True)

        st.dataframe(top, use_container_width=True)
    else:
        st.info("No sales data yet.")
