# Supply Chain & Logistics Analytics

An end-to-end data analytics pipeline analyzing ~180,000 order-line records from the DataCo Smart Supply Chain Dataset. This project covers raw data cleaning and validation in Python, star-schema modeling in PostgreSQL, and interactive visualization in Power BI.

## Table of Contents
- [Overview](#overview)
- [Problem Statement](#problem-statement)
- [Dataset Summary](#dataset-summary)
- [Tech Stack](#tech-stack)
- [Data Cleaning & Quality Assurances](#data-cleaning--quality-assurances)
- [Data Modeling & Analytics (SQL / DAX)](#data-modeling--analytics-sql--dax)
- [Key Findings & Recommendations](#key-findings--recommendations)
- [Dashboard Preview](#dashboard-preview)
- [Repository Structure](#repository-structure)
- [How to Run](#how-to-run)
- [Author](#author)

---

## Overview

Raw transactional data often conceals critical operational bottlenecks beneath high-level revenue growth. This project traces a full data pipeline from unvalidated transactional records to a structured dimensional schema and interactive executive dashboard—uncovering hidden delivery delays and product margin leaks.

## Problem Statement

The raw supply chain dataset contained unvalidated date structures, missing values, and PII fields without a relational schema. The business required a structured pipeline to answer three core operational questions:
1. Are late deliveries concentrated in specific shipping modes or global regions?
2. Are specific product categories quietly unprofitable despite strong sales?
3. Does operational performance or profitability vary significantly by geography?

## Dataset Summary

- **Source:** DataCo Smart Supply Chain Dataset (Kaggle)
- **Granularity:** One record per order line item (180,516 rows, 44 columns post-cleaning)
- **Timeframe:** January 2015 – January 2018 *(Note: 2018 contains January only)*

## Tech Stack

- **Python (pandas):** Data cleaning, date normalization, exploratory data analysis
- **PostgreSQL:** Star-schema database design, ETL staging, operational SQL queries
- **Power BI (DAX):** Data modeling and interactive dashboarding

---

## Data Cleaning & Quality Assurances

Initial data preparation resolved missing values, privacy concerns, and structural defects:

- **Dropped Obsolete Columns:** Removed `Product Description` (100% null) and `Order Zipcode` (~86% null).
- **PII Scrubbing:** Excluded customer-identifying details (`Email`, `Password`, `First/Last Name`, `Street`).
- **Constant Removal:** Removed `Product Status` due to zero variation across records.
- **Type Casting & Deduplication:** Converted timestamps to datetime standard; verified zero duplicate rows.

### Data Validation Insights
- **Line-Item Granularity:** Verified that `Order Profit Per Order` is recorded at the line-item level despite its name, making direct aggregation safe without double-counting risks.
- **Shipping Discrepancies:** Identified that ~2.6% of records show slight variances between recorded real shipping days and actual date-diffs; flagged as a documented data-quality note rather than corrected, since the underlying cause (e.g., business-day vs. calendar-day tracking) could not be confirmed from the data alone.
- **Partial-Year Handling:** Excluded 2018 (January-only data) from YoY trend analyses to prevent skewed reporting.

---

## Data Modeling & Analytics (SQL / DAX)

The raw staging table was organized into a **dimensional (star) schema** consisting of three dimension tables and one central fact table.

```text
       [dim_customer] ──────┐
                            ▼
       [dim_product]  ───> [fact_orders]
                            ▲
       [dim_shipping] ──────┘
```

### 1. Schema Creation (`fact_orders`)
```sql
CREATE TABLE fact_orders AS
SELECT
    s."Order Item Id", 
    s."Order Id", 
    s."Customer Id", 
    s."Product Card Id",
    ds.shipping_id,
    s."order date (DateOrders)" AS order_date,
    s."Sales", 
    s."Order Item Total", 
    s."Order Profit Per Order"
    -- additional columns omitted for brevity (23 total in the full table)
FROM staging_orders s
JOIN dim_shipping ds
    ON s."Shipping Mode" = ds."Shipping Mode"
    AND s."Delivery Status" = ds."Delivery Status"
    AND s."Days for shipping (real)" = ds."Days for shipping (real)"
    AND s."Days for shipment (scheduled)" = ds."Days for shipment (scheduled)"
    AND s."Late_delivery_risk" = ds."Late_delivery_risk";
```

### 2. Analytical SQL Queries

**Late Delivery Rate by Shipping Mode:**
```sql
SELECT
    ds."Shipping Mode",
    COUNT(*) AS total_orders,
    ROUND(
        100.0 * SUM(CASE WHEN ds."Delivery Status" = 'Late delivery' THEN 1 ELSE 0 END) / COUNT(*),
        2
    ) AS late_delivery_pct
FROM fact_orders f
JOIN dim_shipping ds ON f.shipping_id = ds.shipping_id
GROUP BY ds."Shipping Mode"
ORDER BY late_delivery_pct DESC;
```

**Lowest Margin Product Categories:**
```sql
SELECT
    dp."Category Name",
    ROUND(SUM(f."Order Item Total")::numeric, 2) AS total_sales,
    ROUND(SUM(f."Order Profit Per Order")::numeric, 2) AS total_profit,
    ROUND((100.0 * SUM(f."Order Profit Per Order") / SUM(f."Order Item Total"))::numeric, 2) AS profit_margin_pct
FROM fact_orders f
JOIN dim_product dp ON f."Product Card Id" = dp."Product Card Id"
GROUP BY dp."Category Name"
ORDER BY profit_margin_pct ASC;
```

### 3. Core DAX Measures
```dax
Total Sales = SUM(fact_orders[Order Item Total])

Total Profit = SUM(fact_orders[Order Profit Per Order])

Profit Margin % = DIVIDE([Total Profit], [Total Sales], 0)

Late Delivery % = 
DIVIDE(
    CALCULATE(COUNTROWS(fact_orders), dim_shipping[Delivery Status] = "Late delivery"),
    COUNTROWS(fact_orders),
    0
)
```

---

## Key Findings & Recommendations

| Focus Area | Key Finding | Strategic Recommendation |
| :--- | :--- | :--- |
| **Shipping Performance** | **First Class (95.3% late)** and **Second Class (76.6% late)** fail delivery commitments far more often than Standard Class (38.1% late). First Class actually delivers in roughly half the time of Standard Class in absolute terms; Second Class delivers in a comparable timeframe to Standard despite promising a much shorter window. In both cases, the high late-delivery rate is consistent with an unrealistic promised window, not slow fulfillment. | **Recalibrate delivery-window expectations:** Adjust customer-facing delivery estimates for expedited tiers rather than altering local regional logistics operations. |
| **Product Margins** | The **Strength Training** category has a **0.68% profit margin** (vs. company baseline of 11–16%) despite non-trivial sales — one of the lowest-margin outliers in the dataset. | **Margin Audit:** Perform a targeted cost-structure review of Strength Training product lines to renegotiate supplier pricing or adjust discounting logic. |
| **Regional Distribution** | Profit margins across all 23 global sales regions remain consistent within a **11%–15% band**. | **Strategy Realignment:** Prioritize product-level and catalog margin optimizations over region-specific strategy overhauls. |

---

## Dashboard Preview

> *(Include screenshot here: `![Dashboard Preview](powerbi/dashboard_screenshot.png)`)*

**Key Dashboard Features:**
- Executive KPI Cards: Total Sales, Total Profit, Profit Margin %.
- Shipping Performance Breakdown: Late Delivery % by Shipping Mode; Scheduled vs. Real Shipping Days by Class.
- Bottom 10 Profit Margin Categories.
- Dynamic Region and Category Slicers.

---

## Repository Structure

```text
├── data/         # Raw and cleaned CSV datasets
├── notebooks/    # Python notebooks for data cleaning & EDA
├── sql/          # Schema creation, dimension population, and analytics queries
├── powerbi/      # Power BI dashboard files (.pbix) and previews
└── README.md
```

---

## How to Run

1. **Clone the repository:**
   ```bash
   git clone https://github.com/NischalDanavandi/Supply-Chain-Logistics-Analytics.git
   ```
2. **Clean Data:** Run the Jupyter Notebook in `/notebooks` to generate clean CSV files.
3. **Database Setup:** Load cleaned CSVs into PostgreSQL and run scripts in `/sql` in sequence (`staging` → `dimensions` → `fact_orders` → `queries`).
4. **Dashboarding:** Open `/powerbi/dashboard.pbix` in Power BI Desktop and update the PostgreSQL connection settings to refresh visuals.

---

## Author

**Nischal Danavandi**  
Data Analyst / Business Analyst — Bengaluru, India
