import streamlit as st
import pandas as pd
from datetime import date
import database as db
from config import STORE_NAME, CURRENCY
from auth import require_login

st.set_page_config(
    page_title=STORE_NAME,
    page_icon="📱",
    layout="wide",
    initial_sidebar_state="expanded"
)

require_login()
st.title(f"📱 {STORE_NAME}")
st.caption("Dashboard")

# ─── Load data ────────────────────────────────────────────────────────────────
try:
    products  = db.get_products()
    invoices  = db.get_invoices()
    customers = db.get_customers()
except Exception as e:
    st.error("**Cannot reach the database.**")
    st.warning(
        "This usually means your **Supabase project is paused** (free tier pauses after 1 week of inactivity).\n\n"
        "**To fix:** go to [supabase.com](https://supabase.com) → open your project → click **Restore project**, "
        "wait ~1 minute, then reload this page."
    )
    with st.expander("Technical details"):
        st.code(str(e))
    st.stop()

# ─── Today / This month stats ─────────────────────────────────────────────────
today       = date.today().isoformat()
this_month  = date.today().strftime("%Y-%m")

today_sales  = [i for i in invoices if i["created_at"][:10] == today]
month_sales  = [i for i in invoices if i["created_at"][:7] == this_month]
low_stock    = [p for p in products if p["stock_qty"] <= (p.get("min_stock") or 5)]
out_of_stock = [p for p in products if p["stock_qty"] == 0]

today_rev  = sum(float(i["total"]) for i in today_sales)
month_rev  = sum(float(i["total"]) for i in month_sales)

# ─── Metrics row ──────────────────────────────────────────────────────────────
c1, c2, c3, c4, c5 = st.columns(5)
c1.metric("Today's Revenue",  f"{CURRENCY}{today_rev:,.2f}",  f"{len(today_sales)} sales")
c2.metric("Month Revenue",    f"{CURRENCY}{month_rev:,.2f}",  f"{len(month_sales)} sales")
c3.metric("Total Products",   len(products))
c4.metric("Total Customers",  len(customers))
c5.metric("All-Time Revenue", f"{CURRENCY}{sum(float(i['total']) for i in invoices):,.2f}")

# ─── Alerts ───────────────────────────────────────────────────────────────────
if out_of_stock:
    st.error(f"🚫 {len(out_of_stock)} product(s) are OUT OF STOCK!")
elif low_stock:
    st.warning(f"⚠️ {len(low_stock)} product(s) are running low on stock.")

if low_stock:
    with st.expander("View Low / Out of Stock Items"):
        df_low = pd.DataFrame(low_stock)
        cols = [c for c in ["name", "brand", "stock_qty", "min_stock", "sell_price"] if c in df_low.columns]
        st.dataframe(df_low[cols].rename(columns={
            "name": "Product", "brand": "Brand",
            "stock_qty": "Stock", "min_stock": "Min", "sell_price": "Price"
        }), use_container_width=True)

# ─── Recent Sales ─────────────────────────────────────────────────────────────
st.subheader("Recent Sales")
if invoices:
    df = pd.DataFrame(invoices[:15])
    df["created_at"] = pd.to_datetime(df["created_at"]).dt.strftime("%Y-%m-%d %H:%M")
    show_cols = [c for c in ["invoice_number", "customer_name", "total", "payment_method", "status", "created_at"] if c in df.columns]
    st.dataframe(
        df[show_cols].rename(columns={
            "invoice_number": "Invoice #", "customer_name": "Customer",
            "total": f"Total ({CURRENCY})", "payment_method": "Payment",
            "status": "Status", "created_at": "Date"
        }),
        use_container_width=True
    )
else:
    st.info("No sales yet. Go to **New Sale** to create your first transaction!")

# ─── Quick nav hint ───────────────────────────────────────────────────────────
st.divider()
col1, col2, col3, col4, col5, col6 = st.columns(6)
col1.page_link("pages/1_Inventory.py",        label="📦 Inventory",        use_container_width=True)
col2.page_link("pages/2_New_Sale.py",         label="🛒 New Sale",         use_container_width=True)
col3.page_link("pages/3_Invoices.py",         label="🧾 Invoices",         use_container_width=True)
col4.page_link("pages/4_Customers.py",        label="👥 Customers",        use_container_width=True)
col5.page_link("pages/5_Reports.py",          label="📊 Reports",          use_container_width=True)
col6.page_link("pages/6_Barcode_Scanner.py",  label="📷 Barcode Scanner",  use_container_width=True)
