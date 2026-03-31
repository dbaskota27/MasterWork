import streamlit as st
import streamlit.components.v1 as components
from PIL import Image
import database as db
from config import CURRENCY, TAX_RATE
from utils import decode_barcode_image, build_receipt_html
from auth import require_login

st.set_page_config(page_title="Barcode Scanner", page_icon="📷", layout="wide")
require_login()
st.title("📷 Barcode Scanner")


# ─── Helpers ──────────────────────────────────────────────────────────────────
def _reset():
    st.session_state.scanner_step    = "scan"
    st.session_state.scanner_product = None
    st.session_state.scanner_barcode = None
    st.session_state.scanner_invoice = None
    st.session_state.show_camera     = False


def _product_card(product):
    cat_name = product.get("categories") or {}
    if isinstance(cat_name, dict):
        cat_name = cat_name.get("name", "—")
    stock      = int(product.get("stock_qty") or 0)
    min_stock  = int(product.get("min_stock") or 5)
    cost_price = float(product.get("cost_price") or 0)
    sell_price = float(product.get("sell_price") or 0)
    barcode    = product.get("barcode") or "—"
    icon       = "🔴" if stock == 0 else ("🟡" if stock <= min_stock else "🟢")
    with st.container(border=True):
        c1, c2, c3 = st.columns([3, 1, 1])
        with c1:
            st.markdown(f"**{product['name']}**")
            st.caption(
                f"Brand: {product.get('brand') or '—'}  |  "
                f"Model: {product.get('model') or '—'}  |  "
                f"Category: {cat_name}"
            )
            st.caption(f"Barcode: `{barcode}`")
            st.write(
                f"Cost: **{CURRENCY}{cost_price:.2f}**  |  "
                f"Sell: **{CURRENCY}{sell_price:.2f}**"
            )
        with c2:
            st.metric("Stock", f"{icon} {stock}")
        with c3:
            st.metric("Min Stock", min_stock)


# ─── Session state init ───────────────────────────────────────────────────────
for key, default in [
    ("scanner_step",    "scan"),
    ("scanner_product", None),
    ("scanner_barcode", None),
    ("scanner_invoice", None),
    ("scanner_qty",     1),
    ("show_camera",     False),
]:
    if key not in st.session_state:
        st.session_state[key] = default

# ─── Permission help ──────────────────────────────────────────────────────────
with st.expander("🔒 Camera not opening? Fix permissions"):
    st.markdown("""
**macOS:** System Settings → Privacy & Security → Camera → enable your browser

| Browser | Steps |
|---------|-------|
| Chrome | 🔒 in address bar → Camera → **Allow** |
| Firefox | Camera icon in address bar → **Allow** |
| Safari | Safari menu → Settings for This Website → Camera → **Allow** |

Reload the page after granting permission.
    """)


# ══════════════════════════════════════════════════════════════════════════════
# STEP 1 — SCAN
# ══════════════════════════════════════════════════════════════════════════════
if st.session_state.scanner_step == "scan":

    col_mode, col_qty = st.columns([3, 1])
    mode = col_mode.radio(
        "Action",
        ["📥 Stock In (Receive inventory)", "📤 Stock Out (Sell)"],
        horizontal=True,
    )
    qty = col_qty.number_input("Quantity", min_value=1, value=1, step=1)

    st.divider()

    if st.button("📷 Show Barcode to Camera", type="primary", use_container_width=True):
        st.session_state.show_camera = not st.session_state.show_camera
        st.rerun()

    if st.session_state.show_camera:
        st.info("Hold the barcode steady and click **Take photo**.")
        photo = st.camera_input("Capture barcode", label_visibility="collapsed")

        if photo:
            value, btype = decode_barcode_image(Image.open(photo))

            if not value:
                st.warning(
                    "Could not read the barcode. Tips:\n"
                    "- Move **closer** so the barcode fills the frame\n"
                    "- Improve **lighting** — avoid glare on shiny labels\n"
                    "- Hold it **flat and still**, then retake"
                )
            else:
                st.success(f"Detected **{btype}**: `{value}`")
                product = db.get_product_by_barcode(value)

                if not product:
                    st.error(f"No stock found for barcode `{value}`.")
                    st.subheader("➕ Add New Product")
                    categories = db.get_categories()
                    with st.form("add_from_scan"):
                        c1, c2 = st.columns(2)
                        new_name  = c1.text_input("Product Name *")
                        new_brand = c2.text_input("Brand")
                        c3, c4 = st.columns(2)
                        new_model   = c3.text_input("Model")
                        new_barcode = c4.text_input("Barcode", value=value, disabled=True)
                        if categories:
                            cat_opts = {c["id"]: c["name"] for c in categories}
                            new_cat = st.selectbox("Category", options=list(cat_opts.keys()),
                                                   format_func=lambda x: cat_opts[x])
                        else:
                            new_cat = None
                        c5, c6, c7, c8 = st.columns(4)
                        new_cost  = c5.number_input("Cost Price *", min_value=0.0, step=0.01)
                        new_sell  = c6.number_input("Sell Price *", min_value=0.0, step=0.01)
                        new_stock = c7.number_input("Stock Qty", min_value=0, step=1, value=qty)
                        new_min   = c8.number_input("Min Stock Alert", min_value=0, step=1, value=5)
                        new_desc  = st.text_area("Description / Notes")
                        submitted = st.form_submit_button("➕ Add Product", use_container_width=True, type="primary")
                        if submitted:
                            if not new_name:
                                st.error("Product name is required!")
                            elif new_sell <= 0:
                                st.error("Sell price must be greater than 0.")
                            else:
                                db.add_product({
                                    "name": new_name, "brand": new_brand, "model": new_model,
                                    "barcode": value, "category_id": new_cat,
                                    "cost_price": new_cost, "sell_price": new_sell,
                                    "stock_qty": new_stock, "min_stock": new_min,
                                    "description": new_desc,
                                })
                                st.success(f"'{new_name}' added with {new_stock} units!")
                                st.session_state.show_camera = False
                                st.rerun()

                elif "📥" in mode:
                    # Stock In: show product card + editable fields
                    current    = int(product.get("stock_qty") or 0)
                    _product_card(product)
                    st.subheader("Update Stock & Prices")
                    with st.form("stock_in_form"):
                        c1, c2, c3 = st.columns(3)
                        new_qty    = c1.number_input("Add Qty", min_value=1, value=qty, step=1)
                        cost_price = c2.number_input("Cost Price", value=float(product.get("cost_price") or 0), min_value=0.0, step=0.01)
                        sell_price = c3.number_input("Sell Price", value=float(product.get("sell_price") or 0), min_value=0.0, step=0.01)
                        confirm = st.form_submit_button("✅ Confirm Stock In", use_container_width=True, type="primary")
                        if confirm:
                            update_data = {}
                            if cost_price != float(product.get("cost_price") or 0):
                                update_data["cost_price"] = cost_price
                            if sell_price != float(product.get("sell_price") or 0):
                                update_data["sell_price"] = sell_price
                            if update_data:
                                db.update_product(product["id"], update_data)
                            db.add_stock(product["id"], new_qty)
                            st.success(f"Done! Stock: {current} → {current + new_qty}")
                            st.session_state.show_camera = False
                            st.rerun()

                else:
                    # Stock Out: proceed to checkout
                    st.session_state.scanner_product = product
                    st.session_state.scanner_barcode = value
                    st.session_state.scanner_qty     = qty
                    st.session_state.scanner_step    = "checkout"
                    st.session_state.show_camera     = False
                    st.rerun()

        if st.button("❌ Cancel", use_container_width=True):
            st.session_state.show_camera = False
            st.rerun()

    # Manual entry fallback
    st.divider()
    with st.expander("⌨️ Enter barcode manually"):
        manual_code = st.text_input("Barcode / IMEI", placeholder="Type or paste here")
        manual_mode = st.radio(
            "Action", ["📥 Stock In", "📤 Stock Out (Sell)"],
            horizontal=True, key="m_mode"
        )
        manual_qty = st.number_input("Quantity", min_value=1, value=1, step=1, key="m_qty")

        if st.button("🔍 Lookup", type="primary"):
            if not manual_code:
                st.warning("Enter a barcode first.")
            else:
                barcode_val = manual_code.strip()
                product = db.get_product_by_barcode(barcode_val)
                if not product:
                    st.error(f"No stock found for barcode `{barcode_val}`.")
                    st.info("Add this product below:")
                    categories = db.get_categories()
                    with st.form("manual_add_product"):
                        mc1, mc2 = st.columns(2)
                        mn_name  = mc1.text_input("Product Name *", key="m_name")
                        mn_brand = mc2.text_input("Brand", key="m_brand")
                        mc3, mc4 = st.columns(2)
                        mn_model   = mc3.text_input("Model", key="m_model")
                        mc4.text_input("Barcode", value=barcode_val, disabled=True, key="m_bc_show")
                        if categories:
                            cat_opts = {c["id"]: c["name"] for c in categories}
                            mn_cat = st.selectbox("Category", options=list(cat_opts.keys()),
                                                  format_func=lambda x: cat_opts[x], key="m_cat")
                        else:
                            mn_cat = None
                        mc5, mc6, mc7, mc8 = st.columns(4)
                        mn_cost  = mc5.number_input("Cost Price *", min_value=0.0, step=0.01, key="m_cost")
                        mn_sell  = mc6.number_input("Sell Price *", min_value=0.0, step=0.01, key="m_sell")
                        mn_stock = mc7.number_input("Stock Qty", min_value=0, step=1, value=manual_qty, key="m_stk")
                        mn_min   = mc8.number_input("Min Stock", min_value=0, step=1, value=5, key="m_min")
                        mn_desc  = st.text_area("Description", key="m_desc")
                        if st.form_submit_button("➕ Add Product", use_container_width=True, type="primary"):
                            if not mn_name:
                                st.error("Product name is required!")
                            elif mn_sell <= 0:
                                st.error("Sell price must be greater than 0.")
                            else:
                                db.add_product({
                                    "name": mn_name, "brand": mn_brand, "model": mn_model,
                                    "barcode": barcode_val, "category_id": mn_cat,
                                    "cost_price": mn_cost, "sell_price": mn_sell,
                                    "stock_qty": mn_stock, "min_stock": mn_min,
                                    "description": mn_desc,
                                })
                                st.success(f"'{mn_name}' added with {mn_stock} units!")
                                st.rerun()
                elif "📥" in manual_mode:
                    current = int(product.get("stock_qty") or 0)
                    _product_card(product)
                    with st.form("manual_stock_in"):
                        mc1, mc2, mc3 = st.columns(3)
                        m_qty   = mc1.number_input("Add Qty", min_value=1, value=manual_qty, step=1, key="msi_qty")
                        m_cost  = mc2.number_input("Cost Price", value=float(product.get("cost_price") or 0), min_value=0.0, step=0.01, key="msi_cost")
                        m_sell  = mc3.number_input("Sell Price", value=float(product.get("sell_price") or 0), min_value=0.0, step=0.01, key="msi_sell")
                        if st.form_submit_button("✅ Confirm Stock In", use_container_width=True, type="primary"):
                            update_data = {}
                            if m_cost != float(product.get("cost_price") or 0):
                                update_data["cost_price"] = m_cost
                            if m_sell != float(product.get("sell_price") or 0):
                                update_data["sell_price"] = m_sell
                            if update_data:
                                db.update_product(product["id"], update_data)
                            db.add_stock(product["id"], m_qty)
                            st.success(f"**{product['name']}** stock: {current} → {current + m_qty}")
                else:
                    st.session_state.scanner_product = product
                    st.session_state.scanner_barcode = manual_code.strip()
                    st.session_state.scanner_qty     = manual_qty
                    st.session_state.scanner_step    = "checkout"
                    st.rerun()


# ══════════════════════════════════════════════════════════════════════════════
# STEP 2 — CHECKOUT  (Stock Out: customer + payment)
# ══════════════════════════════════════════════════════════════════════════════
elif st.session_state.scanner_step == "checkout":
    product = st.session_state.scanner_product
    qty     = st.session_state.scanner_qty

    if st.button("← Back / Scan Again"):
        _reset()
        st.rerun()

    st.subheader("Sale Checkout")
    _product_card(product)

    current_stock = int(product.get("stock_qty") or 0)
    deduct        = min(qty, current_stock)
    unit_price    = float(product.get("sell_price") or 0)
    marked_price  = round(unit_price * deduct, 2)

    # ── Linked pricing state ──────────────────────────────────────────────────
    # Reset when a different product enters checkout
    product_key = f"{product['id']}_{deduct}"
    if st.session_state.get("_co_product_key") != product_key:
        st.session_state._co_product_key  = product_key
        st.session_state._co_discount     = 0.0
        st.session_state._co_cust_pays    = marked_price
        st.session_state._co_last_changed = None

    # Sync: whichever field changed last drives the other
    def _on_discount_change():
        st.session_state._co_last_changed = "discount"

    def _on_cust_pays_change():
        st.session_state._co_last_changed = "cust_pays"

    if st.session_state._co_last_changed == "discount":
        d = max(0.0, min(float(st.session_state._co_discount), marked_price))
        st.session_state._co_cust_pays = round(marked_price - d, 2)
    elif st.session_state._co_last_changed == "cust_pays":
        cp = max(0.0, min(float(st.session_state._co_cust_pays), marked_price))
        st.session_state._co_discount = round(marked_price - cp, 2)

    st.divider()

    # ── Pricing UI ────────────────────────────────────────────────────────────
    st.subheader("Pricing")
    st.metric("Marked Price", f"{CURRENCY}{marked_price:.2f}")

    disc_col, cp_col = st.columns(2)
    disc_col.number_input(
        f"Discount ({CURRENCY})",
        min_value=0.0,
        max_value=float(marked_price),
        step=0.01,
        key="_co_discount",
        on_change=_on_discount_change,
    )
    cp_col.number_input(
        f"Customer Pays ({CURRENCY})",
        min_value=0.0,
        max_value=float(marked_price),
        step=0.01,
        key="_co_cust_pays",
        on_change=_on_cust_pays_change,
    )

    discount      = float(st.session_state._co_discount)
    customer_pays = float(st.session_state._co_cust_pays)
    tax_amt       = round(customer_pays * TAX_RATE, 2)
    total         = round(customer_pays + tax_amt, 2)

    if discount > 0:
        st.info(
            f"Marked: **{CURRENCY}{marked_price:.2f}**  →  "
            f"Discount: **{CURRENCY}{discount:.2f}**  →  "
            f"Customer Pays: **{CURRENCY}{total:.2f}**"
        )

    st.divider()

    # ── Customer ──────────────────────────────────────────────────────────────
    st.subheader("Customer Info")
    customers = db.get_customers()
    cust_map  = {"": "— Walk-in Customer —"} | {
        str(c["id"]): f"{c['name']}  ({c.get('phone') or 'no phone'})"
        for c in customers
    }
    sel_cust = st.selectbox(
        "Select existing customer",
        options=list(cust_map.keys()),
        format_func=lambda x: cust_map[x],
    )

    with st.expander("+ Add new customer"):
        nc1, nc2 = st.columns(2)
        new_name  = nc1.text_input("Name")
        new_phone = nc2.text_input("Phone")
        new_email = st.text_input("Email")
        if st.button("Save & Select Customer"):
            if new_name:
                db.add_customer({"name": new_name, "phone": new_phone, "email": new_email})
                st.success(f"'{new_name}' added! Select them from the dropdown above.")
                st.rerun()
            else:
                st.warning("Name is required.")

    st.divider()

    # ── Payment ───────────────────────────────────────────────────────────────
    st.subheader("Payment")
    pay_col1, pay_col2 = st.columns(2)
    pay_method = pay_col1.radio(
        "Payment Method",
        ["💵 Cash", "⚡ QuickPay"],
        horizontal=True,
    )
    is_quickpay = pay_method == "⚡ QuickPay"
    amt_label   = f"Amount Transferred ({CURRENCY})" if is_quickpay else f"Amount Received ({CURRENCY})"
    amt_help    = "Amount sent via QR / digital payment" if is_quickpay else "Cash handed over by customer"

    amount_paid = pay_col2.number_input(
        amt_label, min_value=0.0, value=float(total), step=0.01, help=amt_help
    )
    change_due = round(amount_paid - total, 2)
    if change_due > 0:
        label = "Change Due" if not is_quickpay else "Overpaid"
        st.success(f"{label}: {CURRENCY}{change_due:.2f}")
    elif change_due < 0:
        st.warning(f"Short by: {CURRENCY}{abs(change_due):.2f}")

    pay_method = "QuickPay" if is_quickpay else "Cash"

    notes = st.text_area("Notes (optional)", height=60)

    st.divider()

    if st.button("✅ Complete Sale & Print Receipt", type="primary", use_container_width=True):
        if current_stock == 0:
            st.error("This product is out of stock — cannot complete sale.")
        else:
            customer_id    = int(sel_cust) if sel_cust else None
            customer_name  = "Walk-in Customer"
            customer_phone = ""
            if customer_id:
                cust           = db.get_customer(customer_id)
                customer_name  = cust["name"]
                customer_phone = cust.get("phone") or ""

            invoice_data = {
                "invoice_number": db.generate_invoice_number(),
                "customer_id":    customer_id,
                "customer_name":  customer_name,
                "customer_phone": customer_phone,
                "subtotal":       marked_price,          # marked / listed price
                "discount":       round(discount, 2),    # agreed discount
                "tax":            tax_amt,
                "total":          total,                 # what customer actually pays
                "payment_method": pay_method,
                "amount_paid":    round(amount_paid, 2), # cash received
                "change_due":     max(0.0, change_due),
                "status":         "paid" if pay_method != "Credit / Due" else "unpaid",
                "notes":          notes,
            }
            cart_item = [{
                "product_id":   product["id"],
                "product_name": product["name"],
                "unit_price":   unit_price,
                "quantity":     deduct,
                "total_price":  marked_price,            # marked price for the line
            }]

            try:
                invoice = db.create_invoice(invoice_data, cart_item)
                st.session_state.scanner_invoice = invoice
                st.session_state.scanner_step    = "receipt"
                st.rerun()
            except Exception as e:
                st.error(f"Error saving sale: {e}")


# ══════════════════════════════════════════════════════════════════════════════
# STEP 3 — RECEIPT
# ══════════════════════════════════════════════════════════════════════════════
elif st.session_state.scanner_step == "receipt":
    invoice = st.session_state.scanner_invoice
    product = st.session_state.scanner_product

    st.success(f"✅ Sale complete!  Invoice **{invoice['invoice_number']}**")

    receipt_items = [{
        "product_name": product["name"],
        "quantity":     st.session_state.scanner_qty,
        "unit_price":   float(product.get("sell_price") or 0),
        "total_price":  float(invoice.get("subtotal") or 0),
    }]

    html = build_receipt_html(invoice, receipt_items)
    components.html(html, height=800, scrolling=True)

    col_a, col_b = st.columns(2)
    if col_a.button("📷 Scan Another Item", type="primary", use_container_width=True):
        _reset()
        st.rerun()
    if col_b.button("🧾 View All Invoices", use_container_width=True):
        st.session_state.view_invoice_id = invoice["id"]
        st.switch_page("pages/3_Invoices.py")
