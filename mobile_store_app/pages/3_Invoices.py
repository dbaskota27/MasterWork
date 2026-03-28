import streamlit as st
import streamlit.components.v1 as components
import pandas as pd
import database as db
from config import STORE_NAME, STORE_ADDRESS, STORE_PHONE, STORE_EMAIL, CURRENCY
from utils import build_receipt_html

st.set_page_config(page_title="Invoices", page_icon="🧾", layout="wide")
st.title("🧾 Invoices & Receipts")




# ─── Tabs ─────────────────────────────────────────────────────────────────────
tab_list, tab_receipt = st.tabs(["All Invoices", "View Receipt"])

# ──── All Invoices ─────────────────────────────────────────────────────────────
with tab_list:
    invoices = db.get_invoices()

    c1, c2, c3, c4 = st.columns([3, 1, 1, 1])
    search        = c1.text_input("Search", placeholder="Invoice # or customer name")
    pay_filter    = c2.selectbox("Payment", ["All", "Cash", "Card", "Bank Transfer", "Credit / Due"])
    status_filter = c3.selectbox("Status",  ["All", "paid", "unpaid"])
    date_filter   = c4.selectbox("Period",  ["All time", "Today", "This week", "This month"])

    from datetime import date, timedelta
    today = date.today()

    filtered = invoices
    if search:
        s = search.lower()
        filtered = [i for i in filtered if
                    s in i["invoice_number"].lower() or
                    s in (i.get("customer_name") or "").lower()]
    if pay_filter != "All":
        filtered = [i for i in filtered if i.get("payment_method") == pay_filter]
    if status_filter != "All":
        filtered = [i for i in filtered if i.get("status") == status_filter]
    if date_filter == "Today":
        filtered = [i for i in filtered if i["created_at"][:10] == today.isoformat()]
    elif date_filter == "This week":
        start = (today - timedelta(days=today.weekday())).isoformat()
        filtered = [i for i in filtered if i["created_at"][:10] >= start]
    elif date_filter == "This month":
        filtered = [i for i in filtered if i["created_at"][:7] == today.strftime("%Y-%m")]

    total_shown = sum(float(i["total"]) for i in filtered)
    st.caption(f"{len(filtered)} invoices  •  Total: {CURRENCY}{total_shown:,.2f}")

    if filtered:
        # Auto-select last invoice from New Sale if available
        default_id = st.session_state.get("last_invoice_id")
        inv_ids    = [i["id"] for i in filtered]
        default_idx = inv_ids.index(default_id) if default_id in inv_ids else 0

        sel_inv = st.selectbox(
            "Select invoice to view receipt",
            options=inv_ids,
            index=default_idx,
            format_func=lambda x: next(
                f"{i['invoice_number']}  —  {i.get('customer_name','Walk-in')}  —  {CURRENCY}{float(i['total']):.2f}"
                for i in filtered if i["id"] == x
            )
        )

        df = pd.DataFrame(filtered)
        df["created_at"] = pd.to_datetime(df["created_at"]).dt.strftime("%Y-%m-%d %H:%M")
        show = [c for c in ["invoice_number", "customer_name", "total", "discount", "payment_method", "status", "created_at"] if c in df.columns]
        st.dataframe(df[show].rename(columns={
            "invoice_number": "Invoice #", "customer_name": "Customer",
            "total": f"Total ({CURRENCY})", "discount": "Discount",
            "payment_method": "Payment", "status": "Status", "created_at": "Date"
        }), use_container_width=True)

        col_receipt, col_delete = st.columns([4, 1])
        if col_receipt.button("🧾 View Receipt", use_container_width=True, type="primary"):
            st.session_state.view_invoice_id = sel_inv
            st.rerun()

        if col_delete.button("🗑️ Delete", use_container_width=True):
            db.delete_invoice(sel_inv)
            st.success("Invoice deleted.")
            st.rerun()
    else:
        st.info("No invoices found.")

# ──── Receipt Viewer ──────────────────────────────────────────────────────────
with tab_receipt:
    inv_id = st.session_state.get("view_invoice_id")

    if not inv_id:
        st.info("Select an invoice from **All Invoices** tab, then click **View Receipt**.")
    else:
        try:
            invoice = db.get_invoice(inv_id)
            items   = db.get_invoice_items(inv_id)
            if invoice:
                html = build_receipt_html(invoice, items)
                components.html(html, height=700, scrolling=True)
            else:
                st.warning("Invoice not found.")
        except Exception as e:
            st.error(f"Error loading receipt: {e}")
