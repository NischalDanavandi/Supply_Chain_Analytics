"""
Supply Chain & Logistics Analytics
Data Cleaning & Exploratory Analysis

Input:  DataCoSupplyChainDataset.csv (raw, 180,519 rows x 53 columns)
Output: cleaned_supply_chain.csv (180,516 rows x 44 columns), pushed to PostgreSQL
"""

import pandas as pd
from sqlalchemy import create_engine


# =====================================================================
# 1. LOAD RAW DATA
# =====================================================================

df = pd.read_csv('DataCoSupplyChainDataset.csv', encoding='latin1')
print(df.shape)  # (180519, 53)


# =====================================================================
# 2. INITIAL STRUCTURAL INSPECTION
# =====================================================================

print(df.info())
print(df.isnull().sum())
print(df.duplicated().sum())  # 0 duplicate rows

# Findings:
# - Product Description: 100% null
# - Order Zipcode: ~86% null
# - order date / shipping date columns: stored as object, need datetime conversion
# - Customer Email, Password, Fname, Lname, Street: PII, not needed for analysis


# =====================================================================
# 3. DROP UNUSABLE AND PII COLUMNS, FIX TYPES
# =====================================================================

cols_to_drop = [
    'Product Description',   # 100% null
    'Order Zipcode',         # ~86% null
    'Customer Email', 'Customer Password',
    'Customer Fname', 'Customer Lname', 'Customer Street'
]
df = df.drop(columns=cols_to_drop)

df['order date (DateOrders)'] = pd.to_datetime(df['order date (DateOrders)'])
df['shipping date (DateOrders)'] = pd.to_datetime(df['shipping date (DateOrders)'])

df = df.dropna(subset=['Customer Zipcode'])  # drops 3 rows with missing zipcode

print(df.shape)                 # (180516, 46)
print(df.isnull().sum().sum())  # 0


# =====================================================================
# 4. DATA VALIDATION CHECKS
# =====================================================================

# 4.1 Does the recorded "real shipping days" match the actual date difference?
df['computed_shipping_days'] = (
    df['shipping date (DateOrders)'] - df['order date (DateOrders)']
).dt.days
mismatch = (df['computed_shipping_days'] != df['Days for shipping (real)']).sum()
print(f"Mismatches: {mismatch} out of {len(df)}")
# Result: 4,657 out of 180,516 (~2.6%) -- documented as a data-quality note,
# likely reflecting business-day vs. calendar-day tracking, not an error.

# 4.2 Granularity check -- how many line items per order?
items_per_order = df.groupby('Order Id')['Order Item Id'].nunique()
print(items_per_order.describe())
# Result: 1-5 items per order, average ~2.75 -- most orders are multi-item.

# 4.3 Does a profit column repeat the same value across an order's line items,
#     or is it genuinely recorded per line item? (Prevents a double-counting
#     error when aggregating profit in SQL.)
sample_order = items_per_order[items_per_order > 1].index[0]
print(df[df['Order Id'] == sample_order][
    ['Order Id', 'Order Item Id', 'Sales', 'Order Profit Per Order', 'Order Item Total']
])
# Result: distinct values per line item -- confirmed safe to SUM() directly
# in SQL without deduplicating by Order Id first.


# =====================================================================
# 5. EXPLORATORY ANALYSIS
# =====================================================================

category_sales = df.groupby('Category Name')['Sales'].sum().sort_values(ascending=False)
print(category_sales.head(10))

print(df['Shipping Mode'].value_counts())
print(df['Delivery Status'].value_counts())
# Result: Standard Class ~60% of shipments; Late delivery ~55% of all orders
# -- the single largest delivery status, and the starting point for the
# shipping-mode business question explored further in SQL.


# =====================================================================
# 6. FINAL CLEANUP BEFORE EXPORT
# =====================================================================

df = df.drop(columns=[
    'Product Status',          # constant value (0) across every row -- no information
    'computed_shipping_days',  # temporary column used only for the check in section 4.1
    'Product Image'            # image URL, no analytical value
])
print(df.shape)  # (180516, 44) -- final cleaned shape


# =====================================================================
# 7. EXPORT AND LOAD TO POSTGRESQL
# =====================================================================

df.to_csv('cleaned_supply_chain.csv', index=False)

# Note: a password containing '@' must be URL-encoded as '%40' in the
# connection string below, since '@' is a reserved separator character.
engine = create_engine('postgresql://postgres:YOUR_PASSWORD@localhost:5432/supply_chain_db')
df.to_sql('staging_orders', engine, if_exists='replace', index=False,
          method='multi', chunksize=5000)
print("Done — pushed to Postgres as 'staging_orders'")
