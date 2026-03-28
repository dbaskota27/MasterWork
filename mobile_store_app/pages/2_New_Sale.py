import streamlit as st
import database as db
from config import STORE_NAME, CURRENCY, TAX_RATE

st.set_page_config(page_title="New Sale", page_icon="🛒", layout="wide")
st.title("🛒 New Sale — POS")

# ─── Cart init ────────────────────────────────────────────────────────────────
if "cart" not in st.session_state:
    st.session_state.cart = []


def add_to_cart(product, qty):
    for item in st.session_state.cart:
        if item["product_id"] == product["id"]:
            item["quantity"]   += qty
            item["total_price"] = item["quantity"] * item["unit_price"]
            return
    st.session_state.cart.append({
        "product_id":   product["id"],
        "product_name": product["name"],
        "unit_price":   float(product["sell_price"]),
        "quantity":     qty,
        "total_price":  float(product["sell_price"]) * qty,
    })


def remove_from_cart(product_id):
    st.session_state.cart = [i for i in st.session_state.cart if i["product_id"] != product_id]


# ─── Layout ───────────────────────────────────────────────────────────────────
col_products, col_cart = st.columns([3, 2])

# ──── Left: Product Browser ────────────────────────────────────────────────────
with col_products:
    st.subheader("Products")
    products   = db.get_products()
    categories = db.get_categories()

    c1, c2 = st.columns([3, 1])
    search      = c1.text_input("Search product", placeholder="Name, brand, model...")
    cat_names   = ["All"] + [c["name"] for c in categories]
    cat_filter  = c2.selectbox("Category", cat_names, key="pos_cat")

    filtered = products
    if search:
        s = search.lower()
        filtered = [p for p in filtered if
                    s in (p.get("name") or "").lower() or
                    s in (p.get("brand") or "").lower() or
                    s in (p.get("model") or "").lower()]
    if cat_filter != "All":
        filtered = [p for p in filtered if
                    p.get("categories") and p["categories"]["name"] == cat_filter]

    if not filtered:
        st.info("No products found.")
    else:
        # 2-column product grid
        for i in range(0, len(filtered), 2):
            cols = st.columns(2)
            for j, col in enumerate(cols):
                if i + j < len(filtered):
                    p = filtered[i + j]
                    with col:
                        with st.container(border=True):
                            label = p["name"]
                            if p.get("brand"):
                                label += f" — {p['brand']}"
                            if p.get("model"):
                                label += f" {p['model']}"
                            st.markdown(f"**{p['name']}**")
                            if p.get("brand") or p.get("model"):
                                st.caption(f"{p.get('brand','')} {p.get('model','')}".strip())
                            stock_color = "🔴" if p["stock_qty"] == 0 else ("🟡" if p["stock_qty"] <= (p.get("min_stock") or 5) else "🟢")
                            st.write(f"{CURRENCY}{float(p['sell_price']):.2f}  |  {stock_color} Stock: {p['stock_qty']}")

                            qty = st.number_input(
                                "Qty", min_value=1,
                                max_value=max(1, p["stock_qty"]),
                                value=1, key=f"qty_{p['id']}"
                            )
                            btn = st.button(
                                "Add to Cart", key=f"add_{p['id']}",
                                use_container_width=True,
                                disabled=(p["stock_qty"] == 0)
                            )
                            if btn:
                                add_to_cart(p, qty)
                                st.rerun()

# ──── Right: Cart & Checkout ──────────────────────────────────────────────────
with col_cart:
    st.subheader(f"Cart  ({len(st.session_state.cart)} items)")

    if not st.session_state.cart:
        st.info("Cart is empty — add products from the left.")
    else:
        # Cart items
        for item in st.session_state.cart:
            with st.container(border=True):
                c1, c2, c3, c4 = st.columns([3, 2, 2, 1])
                c1.write(f"**{item['product_name']}**")
                new_qty = c2.number_input(
                    "Qty", min_value=1, value=item["quantity"],
                    key=f"cart_qty_{item['product_id']}", label_visibility="collapsed"
                )
                if new_qty != item["quantity"]:
                    item["quantity"]   = new_qty
                    item["total_price"] = new_qty * item["unit_price"]

                c3.write(f"{CURRENCY}{item['total_price']:.2f}")
                if c4.button("✕", key=f"rm_{item['product_id']}"):
                    remove_from_cart(item["product_id"])
                    st.rerun()

        st.divider()

        # Totals
        subtotal   = sum(i["total_price"] for i in st.session_state.cart)
        discount   = st.number_input(f"Discount ({CURRENCY})", min_value=0.0, max_value=float(subtotal), step=0.01, value=0.0)
        after_disc = subtotal - discount
        tax_amt    = after_disc * TAX_RATE
        total      = after_disc + tax_amt

        st.markdown(f"**Subtotal:** {CURRENCY}{subtotal:.2f}")
        if discount > 0:
            st.markdown(f"**Discount:** -{CURRENCY}{discount:.2f}")
        if TAX_RATE > 0:
            st.markdown(f"**Tax ({TAX_RATE*100:.1f}%):** {CURRENCY}{tax_amt:.2f}")
        st.markdown(f"### Total: {CURRENCY}{total:.2f}")

        st.divider()

        # Customer
        st.subheader("Customer")
        customers = db.get_customers()
        cust_map  = {"": "— Walk-in Customer —"} | {str(c["id"]): f"{c['name']}  ({c.get('phone') or 'no phone'})" for c in customers}
        sel_cust  = st.selectbox("Select customer", options=list(cust_map.keys()), format_func=lambda x: cust_map[x])

        with st.expander("+ Quick Add Customer"):
            with st.form("quick_cust", clear_on_submit=True):
                nc1, nc2 = st.columns(2)
                n_name  = nc1.text_input("Name *")
                n_phone = nc2.text_input("Phone")
                n_email = st.text_input("Email")
                if st.form_submit_button("Add"):
                    if n_name:
                        db.add_customer({"name": n_name, "phone": n_phone, "email": n_email})
                        st.success("Customer added!")
                        st.rerun()

        st.divider()

        # Payment
        payment_method = st.selectbox("Payment Method", ["Cash", "Card", "Bank Transfer", "Credit / Due"])
        amount_paid    = st.number_input(f"Amount Paid ({CURRENCY})", min_value=0.0, value=float(total), step=0.01)
        change_due     = amount_paid - total
        if change_due > 0:
            st.success(f"Change Due: {CURRENCY}{change_due:.2f}")
        elif change_due < 0:
            st.warning(f"Short by: {CURRENCY}{abs(change_due):.2f}")

        notes = st.text_area("Notes (optional)", height=60)

        c_complete, c_clear = st.columns(2)

        if c_complete.button("✅ Complete Sale", use_container_width=True, type="primary"):
            # Build customer info
            customer_id    = int(sel_cust) if sel_cust else None
            customer_name  = "Walk-in Customer"
            customer_phone = ""
            if customer_id:
                cust = db.get_customer(customer_id)
                customer_name  = cust["name"]
                customer_phone = cust.get("phone") or ""

            invoice_data = {
                "invoice_number":  db.generate_invoice_number(),
                "customer_id":     customer_id,
                "customer_name":   customer_name,
                "customer_phone":  customer_phone,
                "subtotal":        round(subtotal, 2),
                "discount":        round(discount, 2),
                "tax":             round(tax_amt, 2),
                "total":           round(total, 2),
                "payment_method":  payment_method,
                "amount_paid":     round(amount_paid, 2),
                "change_due":      round(max(0, change_due), 2),
                "status":          "paid" if payment_method != "Credit / Due" else "unpaid",
                "notes":           notes,
            }

            try:
                invoice = db.create_invoice(invoice_data, [dict(i) for i in st.session_state.cart])
                st.session_state.last_invoice_id = invoice["id"]
                st.session_state.cart = []
                st.success(f"✅ Sale complete!  Invoice: **{invoice['invoice_number']}**")
                st.balloons()
                st.page_link("pages/3_Invoices.py", label="🧾 View & Print Receipt")
            except Exception as e:
                st.error(f"Error saving sale: {e}")

        if c_clear.button("🗑️ Clear Cart", use_container_width=True):
            st.session_state.cart = []
            st.rerun()
