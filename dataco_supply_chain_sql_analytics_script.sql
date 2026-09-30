-- =============================================================================
-- DataCo Supply Chain Analytics: Database Schema & Business Diagnostic Queries
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. SCHEMA DESIGN & DATA MODELING (STAR SCHEMA)
-- -----------------------------------------------------------------------------

-- Create Dimension: Customer
CREATE TABLE IF NOT EXISTS dim_customer (
    customer_id INT PRIMARY KEY,
    customer_fname VARCHAR(100),
    customer_lname VARCHAR(100),
    customer_segment VARCHAR(50),
    customer_city VARCHAR(100),
    customer_state VARCHAR(100),
    customer_country VARCHAR(100)
);

-- Create Dimension: Product
CREATE TABLE IF NOT EXISTS dim_product (
    product_card_id INT PRIMARY KEY,
    category_id INT,
    category_name VARCHAR(100),
    product_name VARCHAR(255),
    product_price NUMERIC(10, 2)
);

-- Create Dimension: Shipping
CREATE TABLE IF NOT EXISTS dim_shipping (
    shipping_id SERIAL PRIMARY KEY,
    shipping_mode VARCHAR(50),
    delivery_status VARCHAR(50)
);

-- Create Fact Table: Orders
CREATE TABLE IF NOT EXISTS fact_orders (
    order_item_id INT PRIMARY KEY,
    order_id INT,
    customer_id INT REFERENCES dim_customer(customer_id),
    product_card_id INT REFERENCES dim_product(product_card_id),
    shipping_id INT REFERENCES dim_shipping(shipping_id),
    order_date TIMESTAMP,
    shipping_date TIMESTAMP,
    sales NUMERIC(10, 2),
    order_profit_per_order NUMERIC(10, 2),
    order_item_quantity INT,
    days_for_shipping_real INT,
    days_for_shipment_scheduled INT,
    order_region VARCHAR(100),
    market VARCHAR(50)
);

-- Indexes for Query Performance
CREATE INDEX IF NOT EXISTS idx_fact_orders_customer ON fact_orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_fact_orders_product ON fact_orders(product_card_id);
CREATE INDEX IF NOT EXISTS idx_fact_orders_shipping ON fact_orders(shipping_id);
CREATE INDEX IF NOT EXISTS idx_fact_orders_date ON fact_orders(order_date);


-- -----------------------------------------------------------------------------
-- 2. CORE BUSINESS DIAGNOSTIC QUERIES
-- -----------------------------------------------------------------------------

-- Question 1: What is the late delivery percentage across different shipping modes?
SELECT 
    ds.shipping_mode,
    COUNT(*) AS total_orders,
    COUNT(CASE WHEN ds.delivery_status = 'Late delivery' THEN 1 END) AS late_orders,
    ROUND(
        (COUNT(CASE WHEN ds.delivery_status = 'Late delivery' THEN 1 END)::NUMERIC / COUNT(*)) * 100, 2
    ) AS late_delivery_pct
FROM fact_orders fo
JOIN dim_shipping ds ON fo.shipping_id = ds.shipping_id
GROUP BY ds.shipping_mode
ORDER BY late_delivery_pct DESC;


-- Question 2: Root Cause Analysis — Real Shipping Days vs. Scheduled Target Days
SELECT 
    ds.shipping_mode,
    ROUND(AVG(fo.days_for_shipping_real), 2) AS avg_real_days,
    ROUND(AVG(fo.days_for_shipment_scheduled), 2) AS avg_scheduled_days,
    ROUND(AVG(fo.days_for_shipping_real - fo.days_for_shipment_scheduled), 2) AS avg_delay_days,
    ROUND(
        (COUNT(CASE WHEN ds.delivery_status = 'Late delivery' THEN 1 END)::NUMERIC / COUNT(*)) * 100, 2
    ) AS late_delivery_pct
FROM fact_orders fo
JOIN dim_shipping ds ON fo.shipping_id = ds.shipping_id
GROUP BY ds.shipping_mode
ORDER BY late_delivery_pct DESC;


-- Question 3: Category Profitability — Revenue, Profit, and Profit Margin %
SELECT 
    dp.category_name,
    COUNT(fo.order_item_id) AS total_items_sold,
    ROUND(SUM(fo.sales), 2) AS total_sales,
    ROUND(SUM(fo.order_profit_per_order), 2) AS total_profit,
    ROUND(
        (SUM(fo.order_profit_per_order) / NULLIF(SUM(fo.sales), 0)) * 100, 2
    ) AS profit_margin_pct
FROM fact_orders fo
JOIN dim_product dp ON fo.product_card_id = dp.product_card_id
GROUP BY dp.category_name
ORDER BY profit_margin_pct ASC;


-- Question 4: Regional Geographic Uniformity Check
SELECT 
    fo.order_region,
    COUNT(fo.order_item_id) AS total_orders,
    ROUND(
        (COUNT(CASE WHEN ds.delivery_status = 'Late delivery' THEN 1 END)::NUMERIC / COUNT(*)) * 100, 2
    ) AS late_delivery_pct,
    ROUND(
        (SUM(fo.order_profit_per_order) / NULLIF(SUM(fo.sales), 0)) * 100, 2
    ) AS profit_margin_pct
FROM fact_orders fo
JOIN dim_shipping ds ON fo.shipping_id = ds.shipping_id
GROUP BY fo.order_region
ORDER BY total_orders DESC;


-- -----------------------------------------------------------------------------
-- 3. DATA QUALITY & INTEGRITY VALIDATION QUERIES
-- -----------------------------------------------------------------------------

-- Data Quality Check: Year Completeness Check (Diagnosing 2018 Data Drop)
SELECT
    EXTRACT(YEAR FROM order_date::timestamp) AS order_year,
    MIN(order_date::timestamp) AS earliest_date,
    MAX(order_date::timestamp) AS latest_date,
    COUNT(*) AS total_orders
FROM fact_orders
GROUP BY EXTRACT(YEAR FROM order_date::timestamp)
ORDER BY order_year;