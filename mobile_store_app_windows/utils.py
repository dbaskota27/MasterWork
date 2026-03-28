"""Shared utilities: receipt HTML builder, QR generator, barcode decoder."""
import io
import base64
import numpy as np
from datetime import datetime
from PIL import Image
from config import (
    STORE_NAME, STORE_ADDRESS, STORE_PHONE, STORE_EMAIL,
    CURRENCY, STORE_PAYMENT_QR,
)


# ─── QR code helper ───────────────────────────────────────────────────────────
def make_qr_base64(data: str) -> str:
    """Generate a QR code from *data* and return it as a base64 PNG string."""
    import qrcode
    img = qrcode.make(data)
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return base64.b64encode(buf.getvalue()).decode()


# ─── Receipt HTML builder ─────────────────────────────────────────────────────
def build_receipt_html(invoice: dict, items: list) -> str:
    def fmt(v):
        return f"{CURRENCY}{float(v or 0):.2f}"

    try:
        dt = datetime.fromisoformat(invoice["created_at"].replace("Z", "+00:00"))
        date_str = dt.strftime("%B %d, %Y  %I:%M %p")
    except Exception:
        date_str = str(invoice.get("created_at", ""))[:16]

    # ── Item rows ──────────────────────────────────────────────────────────────
    rows = ""
    for it in items:
        rows += f"""
        <tr>
          <td class="item-name">{it['product_name']}</td>
          <td class="center">{it['quantity']}</td>
          <td class="right">{fmt(it['unit_price'])}</td>
          <td class="right">{fmt(it['total_price'])}</td>
        </tr>"""

    discount     = float(invoice.get("discount") or 0)
    tax_val      = float(invoice.get("tax") or 0)
    change_val   = float(invoice.get("change_due") or 0)
    amount_paid  = float(invoice.get("amount_paid") or invoice.get("total") or 0)

    discount_row = ""
    if discount > 0:
        discount_row = (
            f'<tr class="sub-row discount-row">'
            f'<td colspan="3" class="right">Discount:</td>'
            f'<td class="right">-{fmt(discount)}</td></tr>'
        )
    tax_row = ""
    if tax_val > 0:
        tax_row = (
            f'<tr class="sub-row"><td colspan="3" class="right">Tax:</td>'
            f'<td class="right">{fmt(tax_val)}</td></tr>'
        )
    change_row = ""
    if change_val > 0:
        change_row = (
            f'<tr class="sub-row change-row">'
            f'<td colspan="3" class="right">Change Given:</td>'
            f'<td class="right">{fmt(change_val)}</td></tr>'
        )

    # ── Customer block ─────────────────────────────────────────────────────────
    customer_block = ""
    cname = invoice.get("customer_name", "")
    if cname and cname != "Walk-in Customer":
        phone_line = f"📞 {invoice['customer_phone']}<br>" if invoice.get("customer_phone") else ""
        customer_block = f"""
        <div class="customer-box">
          <strong>Bill To:</strong><br>
          {cname}<br>{phone_line}
        </div>"""

    notes_block = ""
    if invoice.get("notes"):
        notes_block = f"<p class='notes'>Notes: {invoice['notes']}</p>"

    # ── Payment QR block ───────────────────────────────────────────────────────
    qr_block = ""
    if STORE_PAYMENT_QR:
        qr_b64 = make_qr_base64(STORE_PAYMENT_QR)
        qr_block = f"""
        <div class="qr-section">
          <p class="qr-label">⚡ Scan to Pay</p>
          <img src="data:image/png;base64,{qr_b64}" class="qr-img" alt="Payment QR">
          <p class="qr-hint">{STORE_PAYMENT_QR}</p>
        </div>"""

    status = (invoice.get("status") or "paid").upper()
    badge_style = (
        "background:#d4edda;color:#155724" if status == "PAID"
        else "background:#f8d7da;color:#721c24"
    )

    return f"""<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<style>
  * {{ box-sizing: border-box; margin: 0; padding: 0; }}
  body {{
    font-family: 'Segoe UI', Arial, sans-serif;
    background: #f0f2f5;
    display: flex;
    justify-content: center;
    padding: 20px;
  }}
  .receipt {{
    background: #fff;
    width: 420px;
    padding: 30px 24px;
    border-radius: 8px;
    box-shadow: 0 2px 12px rgba(0,0,0,0.15);
  }}
  .store-header {{ text-align:center; border-bottom:2px solid #333; padding-bottom:14px; margin-bottom:14px; }}
  .store-name {{ font-size:22px; font-weight:700; letter-spacing:1px; }}
  .store-info {{ font-size:12px; color:#555; margin-top:4px; }}
  .invoice-meta {{ font-size:13px; margin-bottom:12px; line-height:1.7; }}
  .invoice-meta strong {{ display:inline-block; width:110px; }}
  .customer-box {{
    background:#f8f9fa; border-left:3px solid #007bff;
    padding:8px 12px; margin-bottom:12px; font-size:13px; line-height:1.6;
  }}
  table {{ width:100%; border-collapse:collapse; font-size:13px; }}
  thead th {{
    border-top:2px solid #333; border-bottom:1px solid #ccc;
    padding:6px 4px; text-align:left;
  }}
  th.right, td.right {{ text-align:right; }}
  th.center, td.center {{ text-align:center; }}
  td {{ padding:5px 4px; }}
  td.item-name {{ max-width:180px; }}
  tbody tr:nth-child(even) {{ background:#f9f9f9; }}
  .sub-row td {{ padding:3px 4px; color:#444; }}
  .discount-row td {{ color:#e65100; font-weight:600; }}
  .total-row td {{ border-top:2px solid #333; padding-top:8px; font-size:16px; font-weight:700; }}
  .paid-row td {{ color:#155724; font-size:14px; font-weight:700; padding:5px 4px; background:#d4edda; }}
  .change-row td {{ color:#555; font-size:12px; padding:3px 4px; }}
  .badge {{
    display:inline-block; padding:3px 10px; border-radius:12px;
    font-size:11px; font-weight:700; margin-top:4px;
    {badge_style};
  }}
  .notes {{ font-size:12px; color:#666; margin-top:8px; font-style:italic; }}
  /* QR payment section */
  .qr-section {{
    margin-top:20px; padding-top:16px;
    border-top:2px dashed #ccc;
    text-align:center;
  }}
  .qr-label {{ font-size:14px; font-weight:700; margin-bottom:8px; color:#333; }}
  .qr-img {{ width:160px; height:160px; border:1px solid #ddd; border-radius:6px; }}
  .qr-hint {{ font-size:10px; color:#888; margin-top:6px; word-break:break-all; }}
  .footer {{
    text-align:center; margin-top:16px; padding-top:14px;
    border-top:2px dashed #ccc; font-size:12px; color:#666;
  }}
  .print-btn {{
    display:block; width:100%; margin-top:20px; padding:10px;
    background:#007bff; color:#fff; border:none; border-radius:6px;
    font-size:15px; cursor:pointer;
  }}
  .print-btn:hover {{ background:#0056b3; }}
  @media print {{
    body {{ background:#fff; padding:0; }}
    .receipt {{ box-shadow:none; border-radius:0; }}
    .print-btn {{ display:none; }}
  }}
</style>
</head>
<body>
<div class="receipt">

  <div class="store-header">
    <div class="store-name">{STORE_NAME}</div>
    <div class="store-info">
      {f"{STORE_ADDRESS}<br>" if STORE_ADDRESS else ""}
      {f"📞 {STORE_PHONE}<br>" if STORE_PHONE else ""}
      {f"✉️ {STORE_EMAIL}" if STORE_EMAIL else ""}
    </div>
  </div>

  <div class="invoice-meta">
    <strong>Invoice #:</strong> {invoice['invoice_number']}<br>
    <strong>Date:</strong> {date_str}<br>
    <strong>Payment:</strong> {invoice.get('payment_method', 'Cash')}<br>
    <strong>Status:</strong> <span class="badge">{status}</span>
  </div>

  {customer_block}

  <table>
    <thead>
      <tr>
        <th>Item</th>
        <th class="center">Qty</th>
        <th class="right">Unit</th>
        <th class="right">Total</th>
      </tr>
    </thead>
    <tbody>{rows}</tbody>
    <tfoot>
      <tr class="sub-row">
        <td colspan="3" class="right">Marked Price:</td>
        <td class="right">{fmt(invoice['subtotal'])}</td>
      </tr>
      {discount_row}
      {tax_row}
      <tr class="total-row">
        <td colspan="3" class="right">Customer Pays:</td>
        <td class="right">{fmt(invoice['total'])}</td>
      </tr>
      <tr class="paid-row">
        <td colspan="3" class="right">✓ Amount Received:</td>
        <td class="right">{fmt(amount_paid)}</td>
      </tr>
      {change_row}
    </tfoot>
  </table>

  {notes_block}
  {qr_block}

  <div class="footer">
    Thank you for your purchase!<br>
    Please come again 😊
  </div>

  <button class="print-btn" onclick="window.print()">🖨️ Print Receipt</button>
</div>
</body>
</html>"""


# ─── Barcode decoder ──────────────────────────────────────────────────────────
def decode_barcode_image(pil_image: Image.Image):
    """Return (value, type) from a PIL image. Tries zxingcpp → pyzbar → OpenCV."""
    img_rgb = np.array(pil_image.convert("RGB"))

    try:
        import zxingcpp
        target = (
            zxingcpp.BarcodeFormat.EAN13 | zxingcpp.BarcodeFormat.EAN8
            | zxingcpp.BarcodeFormat.UPCA | zxingcpp.BarcodeFormat.UPCE
            | zxingcpp.BarcodeFormat.ITF | zxingcpp.BarcodeFormat.ITF14
            | zxingcpp.BarcodeFormat.Code39 | zxingcpp.BarcodeFormat.Codabar
            | zxingcpp.BarcodeFormat.Code93 | zxingcpp.BarcodeFormat.Code128
            | zxingcpp.BarcodeFormat.QRCode | zxingcpp.BarcodeFormat.DataMatrix
            | zxingcpp.BarcodeFormat.PDF417 | zxingcpp.BarcodeFormat.Aztec
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

    try:
        import cv2
        img_bgr = cv2.cvtColor(img_rgb, cv2.COLOR_RGB2BGR)
        detector = cv2.barcode.BarcodeDetector()
        ok, decoded_info, decoded_type, _ = detector.detectAndDecodeWithType(img_bgr)
        if ok:
            for val, btype in zip(decoded_info, decoded_type):
                if val:
                    return val, btype
    except Exception:
        pass

    return None, None
