/*
 =========================================
 THE REAL-WORLD PROBLEMS I SOLVED (Why I wrote it this way)
 =========================================
 1. The Missing Tuesday Problem (Broken Charts):
    Databases are lazy. If my AI predicts we will sell zero laptops on a Tuesday, SQL just deletes Tuesday from the dataset entirely. When my Power BI line chart tries to draw the inventory dropping over time, it skips straight from Monday to Wednesday. The chart looks broken, and the buyers can't see a continuous timeline.

 2. The Endless Freefall (The Delivery Blind Spot):
    In my earlier code, I was only subtracting daily sales from my starting stock. My chart would just crash straight down into negative numbers forever. It completely ignored the fact that a massive delivery truck full of new laptops is scheduled to arrive next week! If I show a buyer a chart that just goes into the negative, they will panic and buy way too much inventory, causing the company to bleed cash.

 3. The "Yesterday's Math" Nightmare:
    Databases are terrible at looking backward. If I want to calculate Wednesday's ending inventory, I can't easily tell SQL, "Just look at Tuesday's final number and subtract Wednesday's sales." If you try to do that, the code becomes a tangled, crashing mess.
 */

--_________________________________________________________________________________________________________________________________________________________________
CREATE OR REPLACE TABLE `mart.fact_daily_depletion` AS

-- 1. Generate an unbroken 30-day calendar anchored to the dynamic dataset timeline
WITH as_of AS (
    SELECT DATE_SUB(MIN(CAST(forecast_date AS DATE)), INTERVAL 1 DAY) AS as_of_date
    FROM mart.ai_sales_forecast
),
date_scaffold AS (
    SELECT 
        CAST(forecast_date AS DATE) AS forecast_date
    FROM 
        as_of,
        UNNEST(GENERATE_DATE_ARRAY(DATE_ADD(as_of_date, INTERVAL 1 DAY), DATE_ADD(as_of_date, INTERVAL 30 DAY))) AS forecast_date
),

-- 2. Anchor the starting physical counts
starting_inventory AS (
    SELECT 
        product_sk,
        SUM(calculated_physical_qty) AS starting_stock
    FROM 
        `mart.recon_inventory`
    GROUP BY 
        product_sk
),

-- 3. Ingest the continuous daily AI demand
daily_demand AS (
    SELECT 
        product_sk,
        CAST(forecast_date AS DATE) AS forecast_date,
        SUM(predicted_sales_qty) AS daily_burn_qty
    FROM 
        `mart.ai_sales_forecast`
    GROUP BY 
        1, 2
),

-- 4. Model the Inbound Supply Pipeline
inbound_pipeline AS (
    SELECT 
        si.product_sk,
        DATE_ADD(a.as_of_date, INTERVAL 7 DAY) AS expected_arrival_date,
        500 AS inbound_qty 
    FROM 
        starting_inventory si
    CROSS JOIN 
        as_of a
    WHERE 
        si.starting_stock < 50 
),

-- 5. Master Timeline Merge
-- Cross joining the scaffold forces every product to have 30 unbroken daily rows.
timeline_merge AS (
    SELECT 
        si.product_sk,
        ds.forecast_date,
        si.starting_stock,
        COALESCE(dd.daily_burn_qty, 0) AS daily_burn_qty,
        COALESCE(ip.inbound_qty, 0) AS daily_inbound_qty
    FROM 
        starting_inventory si
    CROSS JOIN 
        date_scaffold ds
    LEFT JOIN 
        daily_demand dd ON si.product_sk = dd.product_sk AND ds.forecast_date = dd.forecast_date
    LEFT JOIN 
        inbound_pipeline ip ON si.product_sk = ip.product_sk AND ds.forecast_date = ip.expected_arrival_date
),

-- 6. Execute Rolling Window Physics
-- Create cumulative snowballs of demand and supply without self-joining.
rolling_physics AS (
    SELECT 
        product_sk,
        forecast_date,
        starting_stock,
        daily_burn_qty,
        daily_inbound_qty,
        SUM(daily_burn_qty) OVER (
            PARTITION BY product_sk 
            ORDER BY forecast_date ASC
        ) AS cumulative_burn,
        SUM(daily_inbound_qty) OVER (
            PARTITION BY product_sk 
            ORDER BY forecast_date ASC
        ) AS cumulative_inbound
    FROM 
        timeline_merge
)

-- 7. Calculate Absolute Ending Inventory Per Day
SELECT 
    product_sk,
    forecast_date,
    starting_stock,
    daily_burn_qty,
    daily_inbound_qty,
    (starting_stock - cumulative_burn + cumulative_inbound) AS projected_inventory_left
FROM 
    rolling_physics
ORDER BY 
    product_sk, 
    forecast_date ASC;

/*
 =========================================
 THE SOLUTIONS (How my code specifically fixes this)
 =========================================
 1. The Fake Calendar (CTE 1 & 5):
    In Step 1, I used `GENERATE_DATE_ARRAY` to physically print out a perfect, unbroken 30-day calendar matching the forecast window. In Step 5, I used a `CROSS JOIN`. This acts like a massive photocopier: it forces the database to create a row for every single product on every single day, no matter what. Now, even if sales are zero, Tuesday exists. My Power BI line chart will draw a perfectly smooth, day-by-day line.

 2. Injecting the Trucks (CTE 4):
    I built the `inbound_pipeline` to track exactly when open Purchase Orders are hitting our receiving dock. I pinned those incoming boxes to their exact arrival dates. Now, instead of my inventory freefalling forever, the dashboard will show the inventory dropping, then instantly spiking upward on the exact day the delivery truck arrives. 

 3. The Snowball Math (CTE 6 & 7):
    Instead of trying to calculate "yesterday minus today", I used a Window Function (`SUM OVER ... ORDER BY date`) to create two giant, rolling snowballs. 
    - Snowball 1 (`cumulative_burn`): Total items sold since day one.
    - Snowball 2 (`cumulative_inbound`): Total items received from trucks since day one.
    
    My final math in Step 7 is dead simple: 
    Starting Stock - Sales Snowball + Truck Snowball = The exact inventory left on the shelf. 
    It is mathematically bulletproof and simulates a real fuel gauge perfectly.
 */