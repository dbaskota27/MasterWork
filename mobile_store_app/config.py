import os
from dotenv import load_dotenv

load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL", "")
SUPABASE_KEY = os.getenv("SUPABASE_KEY", "")
SUPABASE_SERVICE_KEY = os.getenv("SUPABASE_SERVICE_KEY", "")

STORE_NAME = os.getenv("STORE_NAME", "My Mobile Store")
STORE_ADDRESS = os.getenv("STORE_ADDRESS", "")
STORE_PHONE = os.getenv("STORE_PHONE", "")
STORE_EMAIL = os.getenv("STORE_EMAIL", "")
TAX_RATE = float(os.getenv("TAX_RATE", "0"))
CURRENCY = os.getenv("CURRENCY", "$")
STORE_PAYMENT_QR = os.getenv("STORE_PAYMENT_QR", "")

MANAGER_USERNAME = os.getenv("MANAGER_USERNAME", "")
MANAGER_PASSWORD = os.getenv("MANAGER_PASSWORD", "")
WORKER_USERNAME  = os.getenv("WORKER_USERNAME",  "")
WORKER_PASSWORD  = os.getenv("WORKER_PASSWORD",  "")
