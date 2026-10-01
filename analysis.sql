-- =====================================================================
-- Supply Chain & Logistics Analytics
-- Full SQL pipeline: staging reference -> star schema -> business queries
-- Run sections in order.
-- =====================================================================


-- =====================================================================
-- SECTION 1: STAR SCHEMA CREATION
-- Source: staging_orders (raw cleaned data loaded from Python/pandas)
-- =====================================================================

-- 1.1 dim_customer
CREATE TABLE dim_customer AS
SELECT DISTINCT
    "Customer Id", "Customer City", "Customer Country", "Customer Segment",
    "Customer State", "Customer Zipcode", "Latitude", "Longitude"
FROM staging_orders;

-- Verify one row per customer before setting primary key
SELECT COUNT(*), COUNT(DISTINCT "Customer Id") FROM dim_customer;
-- Result: 20649, 20649 -- clean

ALTER TABLE dim_customer ADD PRIMARY KEY ("Customer Id");


-- 1.2 dim_product
CREATE TABLE dim_product AS
SELECT DISTINCT
    "Product Card Id", "Product Name", "Product Price",
    "Category Id", "Category Name", "Department Id", "Department Name"
FROM staging_orders;

SELECT COUNT(*), COUNT(DISTINCT "Product Card Id") FROM dim_product;
-- Result: 118, 118 -- clean

ALTER TABLE dim_product ADD PRIMARY KEY ("Product Card Id");


-- 1.3 dim_shipping (no natural key -- surrogate key generated)
CREATE TABLE dim_shipping AS
SELECT DISTINCT
    "Shipping Mode", "Delivery Status",
    "Days for shipping (real)", "Days for shipment (scheduled)", "Late_delivery_risk"
FROM staging_orders;

ALTER TABLE dim_shipping ADD COLUMN shipping_id SERIAL PRIMARY KEY;

SELECT COUNT(*) FROM dim_shipping;
-- Result: 26 distinct shipping combinations


-- 1.4 fact_orders (join to staging to attach the shipping surrogate key)
CREATE TABLE fact_orders AS
SELECT
    s."Order Item Id", s."Order Id", s."Customer Id", s."Product Card Id",
    ds.shipping_id,
    s."order date (DateOrders)" AS order_date,
    s."shipping date (DateOrders)" AS shipping_date,
    s."Sales", s."Order Item Quantity", s."Order Item Discount", s."Order Item Discount Rate",
    s."Order Item Product Price", s."Order Item Profit Ratio", s."Order Item Total",
    s."Order Profit Per Order", s."Benefit per order", s."Sales per customer",
    s."Market", s."Order Region", s."Order Country", s."Order State", s."Order City",
    s."Order Status", s."Type"
FROM staging_orders s
JOIN dim_shipping ds
    ON s."Shipping Mode" = ds."Shipping Mode"
    AND s."Delivery Status" = ds."Delivery Status"
    AND s."Days for shipping (real)" = ds."Days for shipping (real)"
    AND s."Days for shipment (scheduled)" = ds."Days for shipment (scheduled)"
    AND s."Late_delivery_risk" = ds."Late_delivery_risk";

-- Integrity check: row count must match staging_orders exactly
SELECT COUNT(*) FROM fact_orders;
-- Result: 180516 -- matches staging_orders, confirming no rows lost/duplicated in the join


-- 1.5 Keys and constraints
ALTER TABLE fact_orders ADD PRIMARY KEY ("Order Item Id");

ALTER TABLE fact_orders
    ADD CONSTRAINT fk_customer FOREIGN KEY ("Customer Id") REFERENCES dim_customer("Customer Id");

ALTER TABLE fact_orders
    ADD CONSTRAINT fk_product FOREIGN KEY ("Product Card Id") REFERENCES dim_product("Product Card Id");

ALTER TABLE fact_orders
    ADD CONSTRAINT fk_shipping FOREIGN KEY (shipping_id) REFERENCES dim_shipping(shipping_id);


-- =====================================================================
-- SECTION 2: BUSINESS QUESTION 1
-- Is late delivery concentrated in a specific shipping mode?
-- =====================================================================

-- 2.1 Late delivery % by shipping mode
SELECT
    ds."Shipping Mode",
    COUNT(*) AS total_orders,
    SUM(CASE WHEN ds."Delivery Status" = 'Late delivery' THEN 1 ELSE 0 END) AS late_orders,
    ROUND(
        100.0 * SUM(CASE WHEN ds."Delivery Status" = 'Late delivery' THEN 1 ELSE 0 END) / COUNT(*),
        2
    ) AS late_delivery_pct
FROM fact_orders f
JOIN dim_shipping ds ON f.shipping_id = ds.shipping_id
GROUP BY ds."Shipping Mode"
ORDER BY late_delivery_pct DESC;
-- Result: First Class 95.32%, Second Class 76.63%, Same Day 45.74%, Standard Class 38.07%

-- 2.2 Follow-up: scheduled vs. real shipping days, by mode
-- (Explains WHY expedited modes are "late" so often -- checks the promise, not just the outcome)
SELECT
    ds."Shipping Mode",
    ROUND(AVG(ds."Days for shipment (scheduled)"), 2) AS avg_scheduled_days,
    ROUND(AVG(ds."Days for shipping (real)"), 2) AS avg_real_days
FROM fact_orders f
JOIN dim_shipping ds ON f.shipping_id = ds.shipping_id
GROUP BY ds."Shipping Mode"
ORDER BY avg_scheduled_days;
-- Result: every mode takes ~2x its promised time except Standard Class (4.00 promised, 4.00 real)

-- 2.3 Follow-up: does the pattern hold across every market, or is it regional?
SELECT
    f."Market", ds."Shipping Mode",
    COUNT(*) AS total_orders,
    ROUND(
        100.0 * SUM(CASE WHEN ds."Delivery Status" = 'Late delivery' THEN 1 ELSE 0 END) / COUNT(*),
        2
    ) AS late_delivery_pct
FROM fact_orders f
JOIN dim_shipping ds ON f.shipping_id = ds.shipping_id
GROUP BY f."Market", ds."Shipping Mode"
ORDER BY f."Market", late_delivery_pct DESC;
-- Result: pattern holds within ~2 percentage points across every market
-- -> confirms a structural estimate-setting issue, not a regional operations problem


-- =====================================================================
-- SECTION 3: BUSINESS QUESTION 2
-- Which product categories have the strongest/weakest profit margins?
-- =====================================================================

SELECT
    dp."Category Name",
    ROUND(SUM(f."Order Item Total")::numeric, 2) AS total_sales,
    ROUND(SUM(f."Order Profit Per Order")::numeric, 2) AS total_profit,
    ROUND((100.0 * SUM(f."Order Profit Per Order") / SUM(f."Order Item Total"))::numeric, 2) AS profit_margin_pct
FROM fact_orders f
JOIN dim_product dp ON f."Product Card Id" = dp."Product Card Id"
GROUP BY dp."Category Name"
ORDER BY profit_margin_pct ASC;
-- Result: Strength Training 0.68% (lowest by far); most categories sit at 9-16%


-- =====================================================================
-- SECTION 4: BUSINESS QUESTION 3
-- Does profitability vary meaningfully by region?
-- =====================================================================

SELECT
    f."Order Region",
    ROUND(SUM(f."Order Item Total")::numeric, 2) AS total_sales,
    ROUND(SUM(f."Order Profit Per Order")::numeric, 2) AS total_profit,
    ROUND((100.0 * SUM(f."Order Profit Per Order") / SUM(f."Order Item Total"))::numeric, 2) AS profit_margin_pct
FROM fact_orders f
GROUP BY f."Order Region"
ORDER BY total_sales DESC;
-- Result: flat 11-15% margin band across all 23 regions -- no material outlier
-- -> profitability in this business is product-driven, not geographic


-- =====================================================================
-- SECTION 5: SUPPORTING CHECK
-- Year completeness (informed the exclusion of 2018 from the dashboard's year-trend chart)
-- =====================================================================

SELECT
    EXTRACT(YEAR FROM order_date::timestamp) AS order_year,
    MIN(order_date::timestamp) AS earliest_date,
    MAX(order_date::timestamp) AS latest_date,
    COUNT(*) AS total_orders
FROM fact_orders
GROUP BY EXTRACT(YEAR FROM order_date::timestamp)
ORDER BY order_year;
-- Result: 2015-2017 have full 12-month coverage; 2018 has January only (2,123 orders)
-- -> 2018 excluded from year-over-year trend analysis as a partial year
