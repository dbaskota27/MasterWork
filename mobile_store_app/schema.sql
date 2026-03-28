-- ============================================
-- Mobile Store App - Supabase Schema
-- Run this in Supabase SQL Editor
-- ============================================

-- Categories
CREATE TABLE IF NOT EXISTS categories (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Products / Inventory
CREATE TABLE IF NOT EXISTS products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    category_id INTEGER REFERENCES categories(id) ON DELETE SET NULL,
    brand VARCHAR(100),
    model VARCHAR(100),
    barcode VARCHAR(100),
    cost_price DECIMAL(10,2) NOT NULL DEFAULT 0,
    sell_price DECIMAL(10,2) NOT NULL DEFAULT 0,
    stock_qty INTEGER NOT NULL DEFAULT 0,
    min_stock INTEGER DEFAULT 5,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Customers
CREATE TABLE IF NOT EXISTS customers (
    id SERIAL PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    phone VARCHAR(30),
    email VARCHAR(200),
    address TEXT,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Invoices
CREATE TABLE IF NOT EXISTS invoices (
    id SERIAL PRIMARY KEY,
    invoice_number VARCHAR(50) UNIQUE NOT NULL,
    customer_id INTEGER REFERENCES customers(id) ON DELETE SET NULL,
    customer_name VARCHAR(200) DEFAULT 'Walk-in Customer',
    customer_phone VARCHAR(30),
    subtotal DECIMAL(10,2) NOT NULL DEFAULT 0,
    discount DECIMAL(10,2) DEFAULT 0,
    tax DECIMAL(10,2) DEFAULT 0,
    total DECIMAL(10,2) NOT NULL DEFAULT 0,
    payment_method VARCHAR(50) DEFAULT 'Cash',
    amount_paid DECIMAL(10,2) DEFAULT 0,
    change_due DECIMAL(10,2) DEFAULT 0,
    status VARCHAR(20) DEFAULT 'paid',
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Invoice Line Items
CREATE TABLE IF NOT EXISTS invoice_items (
    id SERIAL PRIMARY KEY,
    invoice_id INTEGER REFERENCES invoices(id) ON DELETE CASCADE,
    product_id INTEGER REFERENCES products(id) ON DELETE SET NULL,
    product_name VARCHAR(200) NOT NULL,
    quantity INTEGER NOT NULL DEFAULT 1,
    unit_price DECIMAL(10,2) NOT NULL,
    total_price DECIMAL(10,2) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- Disable RLS (for private internal use)
-- ============================================
ALTER TABLE categories DISABLE ROW LEVEL SECURITY;
ALTER TABLE products DISABLE ROW LEVEL SECURITY;
ALTER TABLE customers DISABLE ROW LEVEL SECURITY;
ALTER TABLE invoices DISABLE ROW LEVEL SECURITY;
ALTER TABLE invoice_items DISABLE ROW LEVEL SECURITY;

-- ============================================
-- Seed some default categories
-- ============================================
INSERT INTO categories (name) VALUES
    ('Smartphones'),
    ('Tablets'),
    ('Accessories'),
    ('Chargers & Cables'),
    ('Cases & Covers'),
    ('Screen Protectors'),
    ('Earphones & Headphones'),
    ('Power Banks'),
    ('Smart Watches'),
    ('Other')
ON CONFLICT (name) DO NOTHING;
