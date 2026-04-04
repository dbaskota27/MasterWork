-- Migration: Add brand, model, IMEI, serial_number to products table
-- Run this on existing Supabase databases

ALTER TABLE products ADD COLUMN IF NOT EXISTS brand         text;
ALTER TABLE products ADD COLUMN IF NOT EXISTS model         text;
ALTER TABLE products ADD COLUMN IF NOT EXISTS imei          text;
ALTER TABLE products ADD COLUMN IF NOT EXISTS serial_number text;
