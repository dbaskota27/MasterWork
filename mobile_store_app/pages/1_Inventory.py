import streamlit as st
import pandas as pd
import numpy as np
from PIL import Image
import database as db
from config import STORE_NAME, CURRENCY


def _decode_barcode(pil_image: Image.Image):
    """Return (value, type) from a PIL image using available decoders."""
    img_rgb = np.array(pil_image.convert("RGB"))
    try:
        import zxingcpp
        target = (
            zxingcpp.BarcodeFormat.EAN13 | zxingcpp.BarcodeFormat.EAN8
            | zxingcpp.BarcodeFormat.UPCA | zxingcpp.BarcodeFormat.UPCE
            | zxingcpp.BarcodeFormat.ITF | zxingcpp.BarcodeFormat.ITF14
            | zxingcpp.BarcodeFormat.Code39 | zxingcpp.BarcodeFormat.Codabar
            | zxingcpp.BarcodeFormat.Code93 | zxingcpp.BarcodeFormat.Code128
            | zxingcpp.BarcodeFormat.QRCode
        )
        for bc in zxingcpp.read_barcodes(img_rgb, formats=target):
            if bc.valid and bc.text:
                return bc.text, str(bc.format).split(".")[-1]
    except Exception:
        pass
    try:
        from pyzbar.pyzbar import decode as pyzbar_decode
        for obj in pyzbar_decode(pil_image):
            return obj.data.decode("utf-8"), str(obj.type)
    except Exception:
        pass
    return None, None

st.set_page_config(page_title="Inventory", page_icon="📦", layout="wide")
st.title("📦 Inventory Management")

tab_list, tab_add, tab_cats = st.tabs(["All Products", "Add Product", "Categories"])

# ─── All Products ─────────────────────────────────────────────────────────────
with tab_list:
    products   = db.get_products()
    categories = db.get_categories()

    col1, col2, col3 = st.columns([3, 1, 1])
    search       = col1.text_input("Search", placeholder="Name, brand, model, barcode...")
    cat_names    = ["All"] + [c["name"] for c in categories]
    cat_filter   = col2.selectbox("Category", cat_names)
    stock_filter = col3.selectbox("Stock", ["All", "In Stock", "Low Stock", "Out of Stock"])

    filtered = products
    if search:
        s = search.lower()
        filtered = [p for p in filtered if
                    s in (p.get("name") or "").lower() or
                    s in (p.get("brand") or "").lower() or
                    s in (p.get("model") or "").lower() or
                    s in (p.get("barcode") or "").lower()]
    if cat_filter != "All":
        filtered = [p for p in filtered if
                    p.get("categories") and p["categories"]["name"] == cat_filter]
    if stock_filter == "In Stock":
        filtered = [p for p in filtered if p["stock_qty"] > (p.get("min_stock") or 5)]
    elif stock_filter == "Low Stock":
        filtered = [p for p in filtered if 0 < p["stock_qty"] <= (p.get("min_stock") or 5)]
    elif stock_filter == "Out of Stock":
        filtered = [p for p in filtered if p["stock_qty"] == 0]

    st.caption(f"Showing {len(filtered)} of {len(products)} products")

    if filtered:
        df = pd.DataFrame(filtered)

        def stock_status(row):
            qty = row.get("stock_qty", 0)
            mn  = row.get("min_stock") or 5
            if qty == 0:
                return "🔴 Out"
            elif qty <= mn:
                return "🟡 Low"
            return "🟢 OK"

        df["status"] = df.apply(stock_status, axis=1)

        show = {
            "name": "Product", "brand": "Brand", "model": "Model",
            "barcode": "Barcode", "cost_price": f"Cost ({CURRENCY})",
            "sell_price": f"Price ({CURRENCY})", "stock_qty": "Stock",
            "min_stock": "Min", "status": "Status"
        }
        available = {k: v for k, v in show.items() if k in df.columns}
        st.dataframe(df[list(available.keys())].rename(columns=available), use_container_width=True)

        st.divider()
        st.subheader("Edit / Delete Product")
        sel_id = st.selectbox(
            "Select product",
            options=[p["id"] for p in filtered],
            format_func=lambda x: next(p["name"] for p in filtered if p["id"] == x)
        )
        if sel_id:
            p = next(p for p in filtered if p["id"] == sel_id)
            with st.form("edit_product"):
                c1, c2 = st.columns(2)
                name    = c1.text_input("Name *",  value=p["name"])
                brand   = c2.text_input("Brand",   value=p.get("brand") or "")
                c3, c4  = st.columns(2)
                model   = c3.text_input("Model",   value=p.get("model") or "")
                barcode = c4.text_input("Barcode", value=p.get("barcode") or "")

                cat_opts  = {c["id"]: c["name"] for c in categories}
                cat_ids   = list(cat_opts.keys())
                cur_cat   = p.get("category_id")
                cat_idx   = cat_ids.index(cur_cat) if cur_cat in cat_ids else 0
                category_id = st.selectbox("Category",
                                           options=cat_ids,
                                           format_func=lambda x: cat_opts[x],
                                           index=cat_idx) if cat_ids else None

                c5, c6, c7, c8 = st.columns(4)
                cost_price = c5.number_input("Cost Price",  value=float(p.get("cost_price") or 0), min_value=0.0, step=0.01)
                sell_price = c6.number_input("Sell Price",  value=float(p.get("sell_price") or 0), min_value=0.0, step=0.01)
                stock_qty  = c7.number_input("Stock Qty",   value=int(p.get("stock_qty") or 0),    min_value=0,   step=1)
                min_stock  = c8.number_input("Min Stock Alert", value=int(p.get("min_stock") or 5), min_value=0,  step=1)

                description = st.text_area("Description", value=p.get("description") or "")

                cs, cd = st.columns([4, 1])
                save   = cs.form_submit_button("💾 Save Changes", use_container_width=True, type="primary")
                delete = cd.form_submit_button("🗑️ Delete",       use_container_width=True)

                if save:
                    db.update_product(sel_id, {
                        "name": name, "brand": brand, "model": model, "barcode": barcode,
                        "category_id": category_id, "cost_price": cost_price,
                        "sell_price": sell_price, "stock_qty": stock_qty,
                        "min_stock": min_stock, "description": description
                    })
                    st.success("✅ Product updated!")
                    st.rerun()
                if delete:
                    db.delete_product(sel_id)
                    st.success("Product deleted.")
                    st.rerun()
    else:
        st.info("No products found.")

# ─── Add Product ──────────────────────────────────────────────────────────────
with tab_add:
    st.subheader("Add New Product")
    categories = db.get_categories()

    # ── Barcode camera scanner (must live OUTSIDE the form) ───────────────────
    if "add_scanned_barcode" not in st.session_state:
        st.session_state.add_scanned_barcode  = ""
    if "add_show_camera" not in st.session_state:
        st.session_state.add_show_camera = False

    bc_col, btn_col = st.columns([4, 1])
    bc_col.markdown("**Barcode / IMEI**")
    if btn_col.button("📷 Scan", use_container_width=True, key="open_cam_btn"):
        st.session_state.add_show_camera = not st.session_state.add_show_camera

    if st.session_state.add_show_camera:
        photo = st.camera_input("Point camera at barcode and capture", label_visibility="collapsed")
        if photo:
            val, btype = _decode_barcode(Image.open(photo))
            if val:
                st.session_state.add_scanned_barcode = val
                st.session_state.add_show_camera     = False
                st.success(f"Barcode captured — **{btype}**: `{val}`")
                st.rerun()
            else:
                st.warning("Could not read barcode — try better lighting or move closer.")

    # ── Product form ──────────────────────────────────────────────────────────
    with st.form("add_product", clear_on_submit=True):
        c1, c2  = st.columns(2)
        name    = c1.text_input("Product Name *")
        brand   = c2.text_input("Brand")
        c3, c4  = st.columns(2)
        model   = c3.text_input("Model")
        barcode = c4.text_input(
            "Barcode / IMEI",
            value=st.session_state.add_scanned_barcode,
            placeholder="Scan with button above or type here",
        )

        if categories:
            cat_opts    = {c["id"]: c["name"] for c in categories}
            category_id = st.selectbox("Category",
                                       options=list(cat_opts.keys()),
                                       format_func=lambda x: cat_opts[x])
        else:
            st.info("Add a category first (Categories tab).")
            category_id = None

        c5, c6, c7, c8 = st.columns(4)
        cost_price = c5.number_input("Cost Price *",     min_value=0.0, step=0.01)
        sell_price = c6.number_input("Sell Price *",     min_value=0.0, step=0.01)
        stock_qty  = c7.number_input("Initial Stock",    min_value=0,   step=1, value=0)
        min_stock  = c8.number_input("Min Stock Alert",  min_value=0,   step=1, value=5)

        description = st.text_area("Description / Notes")
        submitted   = st.form_submit_button("➕ Add Product", use_container_width=True, type="primary")

        if submitted:
            if not name:
                st.error("Product name is required!")
            elif sell_price <= 0:
                st.error("Sell price must be greater than 0.")
            else:
                db.add_product({
                    "name": name, "brand": brand, "model": model, "barcode": barcode,
                    "category_id": category_id, "cost_price": cost_price,
                    "sell_price": sell_price, "stock_qty": stock_qty,
                    "min_stock": min_stock, "description": description
                })
                st.session_state.add_scanned_barcode = ""
                st.success(f"✅ '{name}' added to inventory!")

# ─── Categories ───────────────────────────────────────────────────────────────
with tab_cats:
    st.subheader("Product Categories")
    categories = db.get_categories()

    if categories:
        df_cat = pd.DataFrame(categories)[["id", "name"]]
        st.dataframe(df_cat.rename(columns={"id": "ID", "name": "Category"}), use_container_width=True)
    else:
        st.info("No categories yet.")

    with st.form("add_category", clear_on_submit=True):
        cat_name  = st.text_input("New Category Name")
        submitted = st.form_submit_button("Add Category")
        if submitted and cat_name:
            try:
                db.add_category(cat_name)
                st.success(f"'{cat_name}' added!")
                st.rerun()
            except Exception:
                st.error("Category already exists.")
