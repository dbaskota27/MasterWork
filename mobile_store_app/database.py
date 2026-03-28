from supabase import create_client, Client
import streamlit as st
from config import SUPABASE_URL, SUPABASE_SERVICE_KEY, SUPABASE_KEY
from datetime import datetime


@st.cache_resource
def get_client() -> Client:
    key = SUPABASE_SERVICE_KEY or SUPABASE_KEY
    return create_client(SUPABASE_URL, key)


# ─── Categories ───────────────────────────────────────────────────────────────

def get_categories():
    return get_client().table("categories").select("*").order("name").execute().data

def add_category(name: str):
    return get_client().table("categories").insert({"name": name}).execute()

def delete_category(cat_id: int):
    return get_client().table("categories").delete().eq("id", cat_id).execute()


# ─── Products ─────────────────────────────────────────────────────────────────

def get_products():
    return get_client().table("products").select("*, categories(name)").order("name").execute().data

def get_product(product_id: int):
    return get_client().table("products").select("*").eq("id", product_id).single().execute().data

def add_product(data: dict):
    return get_client().table("products").insert(data).execute()

def update_product(product_id: int, data: dict):
    data["updated_at"] = datetime.utcnow().isoformat()
    return get_client().table("products").update(data).eq("id", product_id).execute()

def delete_product(product_id: int):
    return get_client().table("products").delete().eq("id", product_id).execute()

def deduct_stock(product_id: int, qty: int):
    product = get_product(product_id)
    new_qty = max(0, product["stock_qty"] - qty)
    get_client().table("products").update({"stock_qty": new_qty}).eq("id", product_id).execute()

def add_stock(product_id: int, qty: int):
    product = get_product(product_id)
    new_qty = product["stock_qty"] + qty
    get_client().table("products").update({"stock_qty": new_qty, "updated_at": datetime.utcnow().isoformat()}).eq("id", product_id).execute()

def get_product_by_barcode(barcode: str):
    result = get_client().table("products").select("*, categories(name)").eq("barcode", barcode).limit(1).execute()
    return result.data[0] if result.data else None


# ─── Customers ────────────────────────────────────────────────────────────────

def get_customers():
    return get_client().table("customers").select("*").order("name").execute().data

def get_customer(customer_id: int):
    return get_client().table("customers").select("*").eq("id", customer_id).single().execute().data

def add_customer(data: dict):
    return get_client().table("customers").insert(data).execute()

def update_customer(customer_id: int, data: dict):
    return get_client().table("customers").update(data).eq("id", customer_id).execute()

def delete_customer(customer_id: int):
    return get_client().table("customers").delete().eq("id", customer_id).execute()


# ─── Invoices ─────────────────────────────────────────────────────────────────

def get_invoices():
    return get_client().table("invoices").select("*").order("created_at", desc=True).execute().data

def get_invoice(invoice_id: int):
    return get_client().table("invoices").select("*").eq("id", invoice_id).single().execute().data

def get_invoice_items(invoice_id: int):
    return get_client().table("invoice_items").select("*").eq("invoice_id", invoice_id).execute().data

def generate_invoice_number() -> str:
    resp = get_client().table("invoices").select("id").order("id", desc=True).limit(1).execute()
    last_id = resp.data[0]["id"] if resp.data else 0
    return f"INV-{last_id + 1:05d}"

def create_invoice(invoice_data: dict, items: list) -> dict:
    client = get_client()
    # Insert invoice
    inv = client.table("invoices").insert(invoice_data).execute().data[0]
    invoice_id = inv["id"]
    # Insert items & deduct stock
    for item in items:
        item["invoice_id"] = invoice_id
        client.table("invoice_items").insert(item).execute()
        if item.get("product_id"):
            deduct_stock(item["product_id"], item["quantity"])
    return inv

def delete_invoice(invoice_id: int):
    return get_client().table("invoices").delete().eq("id", invoice_id).execute()


# ─── Reports ──────────────────────────────────────────────────────────────────

def get_invoices_by_date(start: str, end: str):
    return (get_client().table("invoices")
            .select("*")
            .gte("created_at", start)
            .lte("created_at", end + "T23:59:59")
            .order("created_at", desc=True)
            .execute().data)

def get_all_invoice_items():
    return get_client().table("invoice_items").select("*").execute().data
