/*
 =========================================
 THE REAL-WORLD PROBLEMS I SOLVED (Why I wrote it this way)
 =========================================
 1. The "Ghost Multiplier" Trap (Multi-Warehouse Confusion):
    If I have laptops stored in three different warehouses (New York, LA, and Chicago), my physical inventory table has 3 rows for that one laptop. If I blindly join that directly to my AI sales forecast, the database will duplicate my sales forecast 3 times. It will artificially panic and tell my boss we are selling 3x as many laptops as we actually are.

 2. The "Survivor Deletion" Trap:
    I need to find out when things run out of stock. But if a product is selling slowly and has enough stock to easily survive the next 30 days, its inventory never drops to zero. If I just write a basic filter saying "Show me where inventory is less than zero," the database completely deletes my healthy products from the final report. I need the dashboard to show me everything, including the healthy items.

 3. The "Fuel Gauge" Problem:
    My AI gave me daily sales guesses (e.g., "sell 5 on Monday, 3 on Tuesday"). But that doesn't tell me when I run out of stock. I needed a way to simulate a car's fuel tank draining day by day until the exact moment the engine stalls.
 */

--_________________________________________________________________________________________________________________________________________________________________
CREATE OR REPLACE TABLE `mart.replenishment_risk` AS

-- 1. Squash physical stock to the Product Grain across all warehouses
WITH current_inventory AS (
    SELECT
        product_sk,
        SUM(calculated_physical_qty) AS starting_stock
    FROM
        mart.recon_inventory
    GROUP BY
        product_sk
),

-- 2. Calculate the daily running depletion total
daily_burn AS (
    SELECT
        product_sk,
        forecast_date,
        predicted_sales_qty,
        SUM(predicted_sales_qty) OVER (
            PARTITION BY product_sk
            ORDER BY forecast_date ASC
        ) AS cumulative_sales
    FROM
        mart.ai_sales_forecast
),

-- 3. Model the fuel tank draining day-by-day
depletion_model AS (
    SELECT
        db.product_sk,
        db.forecast_date,
        COALESCE(ci.starting_stock, 0) AS starting_stock,
        db.cumulative_sales,
        (COALESCE(ci.starting_stock, 0) - db.cumulative_sales) AS projected_inventory_left
    FROM
        daily_burn AS db
        LEFT JOIN current_inventory AS ci 
            ON db.product_sk = ci.product_sk
),

-- 4. Isolate the exact milestone day where inventory hits 0
stockout_milestones AS (
    SELECT
        product_sk,
        MIN(forecast_date) AS projected_stockout_date
    FROM
        depletion_model
    WHERE
        projected_inventory_left <= 0
    GROUP BY
        product_sk
)

-- 5. Master Report: Retains healthy SKUs and flags immediate stockouts
SELECT
    ci.product_sk,
    ci.starting_stock,
    sm.projected_stockout_date,
    DATE_DIFF(sm.projected_stockout_date, CURRENT_DATE(), DAY) AS days_until_stockout,
    CASE
        WHEN ci.starting_stock <= 0 THEN 'OUT_OF_STOCK'
        WHEN DATE_DIFF(sm.projected_stockout_date, CURRENT_DATE(), DAY) <= 14 THEN 'CRITICAL_REORDER'
        WHEN DATE_DIFF(sm.projected_stockout_date, CURRENT_DATE(), DAY) <= 30 THEN 'WARNING_LOW_STOCK'
        ELSE 'HEALTHY'
    END AS risk_status
FROM
    current_inventory AS ci
    LEFT JOIN stockout_milestones AS sm 
        ON ci.product_sk = sm.product_sk
ORDER BY
    days_until_stockout ASC

--_________________________________________________________________________________________________________________________________________________________________
/*
 =========================================
 THE SOLUTIONS (How my code specifically fixes this)
 =========================================
 1. Pre-Squashing the Warehouses (CTE 1):
    In `current_inventory`, I added up (`SUM`) all the physical boxes across every single warehouse and grouped them strictly by Product ID. This forces the data down to 1 row per product. I built a single, company-wide "Starting Stock" number before I ever let it touch the AI sales data. Ghost multiplier destroyed.

 2. The Running Total Math (CTE 2 & 3):
    In `daily_burn`, I used a window function (`SUM OVER ... ORDER BY date`) to calculate a rolling snowball of sales. 
    - Day 1: 5 total sold. 
    - Day 2: 8 total sold. 
    - Day 3: 12 total sold. 
    Then, in `depletion_model`, I just took my Starting Stock and subtracted that rolling snowball. This perfectly simulates the fuel tank draining day after day.

 3. Finding the "Day of Death" (CTE 4):
    In `stockout_milestones`, I filtered for the days where the simulated fuel tank dropped to 0 or below. Because a product stays below zero forever once it runs out, I used `MIN(forecast_date)` to grab the absolute *first* day it hit empty. 
    
 4. The Safety Net Join (The Final SELECT):
    Instead of starting my final report with the dying products, I started with `current_inventory` (which contains ALL my products) and used a `LEFT JOIN` to attach their "Day of Death". 
    - If a product never runs out, the `LEFT JOIN` just leaves the date blank. 
    - My `CASE` statement grades them: If starting stock is already 0, it screams 'OUT_OF_STOCK'. If the runout date is blank, it slaps a 'HEALTHY' label on it. Nobody gets deleted.
 */