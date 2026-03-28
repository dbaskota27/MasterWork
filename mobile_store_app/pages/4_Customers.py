import streamlit as st
import pandas as pd
import database as db
from config import CURRENCY

st.set_page_config(page_title="Customers", page_icon="👥", layout="wide")
st.title("👥 Customers")

tab_list, tab_add = st.tabs(["All Customers", "Add Customer"])

# ─── All Customers ────────────────────────────────────────────────────────────
with tab_list:
    customers = db.get_customers()
    invoices  = db.get_invoices()

    search = st.text_input("Search", placeholder="Name, phone, or email...")
    if search:
        s = search.lower()
        customers = [c for c in customers if
                     s in (c.get("name") or "").lower() or
                     s in (c.get("phone") or "").lower() or
                     s in (c.get("email") or "").lower()]

    st.caption(f"{len(customers)} customers")

    if customers:
        # Build summary table
        rows = []
        for c in customers:
            c_invs  = [i for i in invoices if i.get("customer_id") == c["id"]]
            spent   = sum(float(i["total"]) for i in c_invs)
            rows.append({
                "ID":           c["id"],
                "Name":         c["name"],
                "Phone":        c.get("phone") or "",
                "Email":        c.get("email") or "",
                "Purchases":    len(c_invs),
                f"Total Spent ({CURRENCY})": spent,
                "Last Visit":   max((i["created_at"][:10] for i in c_invs), default="—")
            })

        df = pd.DataFrame(rows).sort_values(f"Total Spent ({CURRENCY})", ascending=False)
        st.dataframe(df.drop(columns=["ID"]), use_container_width=True)

        st.divider()
        st.subheader("Customer Detail & Edit")

        sel_id = st.selectbox(
            "Select customer",
            options=[c["id"] for c in customers],
            format_func=lambda x: next(c["name"] for c in customers if c["id"] == x)
        )

        if sel_id:
            customer = next(c for c in customers if c["id"] == sel_id)
            c_invs   = [i for i in invoices if i.get("customer_id") == sel_id]
            spent    = sum(float(i["total"]) for i in c_invs)

            m1, m2, m3 = st.columns(3)
            m1.metric("Total Purchases", len(c_invs))
            m2.metric(f"Total Spent", f"{CURRENCY}{spent:,.2f}")
            m3.metric("Last Visit", max((i["created_at"][:10] for i in c_invs), default="Never"))

            with st.form("edit_customer"):
                c1, c2 = st.columns(2)
                name    = c1.text_input("Name *",   value=customer["name"])
                phone   = c2.text_input("Phone",    value=customer.get("phone") or "")
                c3, c4  = st.columns(2)
                email   = c3.text_input("Email",    value=customer.get("email") or "")
                address = c4.text_input("Address",  value=customer.get("address") or "")
                notes   = st.text_area("Notes",     value=customer.get("notes") or "")

                cs, cd = st.columns([4, 1])
                save   = cs.form_submit_button("💾 Save Changes", use_container_width=True, type="primary")
                delete = cd.form_submit_button("🗑️ Delete",       use_container_width=True)

                if save:
                    db.update_customer(sel_id, {
                        "name": name, "phone": phone,
                        "email": email, "address": address, "notes": notes
                    })
                    st.success("✅ Customer updated!")
                    st.rerun()
                if delete:
                    db.delete_customer(sel_id)
                    st.success("Customer deleted.")
                    st.rerun()

            # Purchase history
            if c_invs:
                st.subheader("Purchase History")
                df_inv = pd.DataFrame(c_invs)
                df_inv["created_at"] = pd.to_datetime(df_inv["created_at"]).dt.strftime("%Y-%m-%d %H:%M")
                show = [c for c in ["invoice_number", "total", "discount", "payment_method", "status", "created_at"] if c in df_inv.columns]
                st.dataframe(df_inv[show].rename(columns={
                    "invoice_number": "Invoice #",
                    "total": f"Total ({CURRENCY})",
                    "discount": "Discount",
                    "payment_method": "Payment",
                    "status": "Status",
                    "created_at": "Date"
                }), use_container_width=True)
    else:
        st.info("No customers found.")

# ─── Add Customer ─────────────────────────────────────────────────────────────
with tab_add:
    st.subheader("Add New Customer")
    with st.form("add_customer", clear_on_submit=True):
        c1, c2  = st.columns(2)
        name    = c1.text_input("Name *")
        phone   = c2.text_input("Phone")
        c3, c4  = st.columns(2)
        email   = c3.text_input("Email")
        address = c4.text_input("Address")
        notes   = st.text_area("Notes")

        submitted = st.form_submit_button("➕ Add Customer", use_container_width=True, type="primary")
        if submitted:
            if not name:
                st.error("Name is required!")
            else:
                db.add_customer({"name": name, "phone": phone, "email": email, "address": address, "notes": notes})
                st.success(f"✅ '{name}' added!")
