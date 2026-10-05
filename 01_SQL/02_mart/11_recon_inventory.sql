/*
 =========================================
 THE PROBLEMS I SOLVED (Why I wrote it this way)
 =========================================
 1. The Row Explosion (Cartesian Fan-Out): 
 If a warehouse received 1 giant shipment of laptops, but customers placed 500 individual orders for those laptops, joining the raw tables directly would multiply that 1 shipment by 500. The database would think we received 500 giant shipments. 
 
 2. The Math Crash (The Null Problem):
 Databases are stupid at math. If we received 10 laptops, but transferred 0, the database leaves the transfer column "BLANK" (NULL). If you ask the database what "10 - BLANK" is, it panics and outputs "BLANK". 
 
 3. The Missing Item Trap:
 If a brand new product just arrived today, it exists in the 'Receipts' table, but it has zero sales, so it doesn't exist in the 'Sales' table yet. If we use a normal SQL JOIN, the database will delete the product from our final report because it couldn't find a matching sale.
 
 4. The Lying Computer:
 The warehouse computer system (WMS snapshot) tells us what it *thinks* is on the shelf. But we know systems lag, people steal, and boxes get lost. We cannot trust the screen.
 */

CREATE OR REPLACE TABLE `mart.recon_inventory` AS 

-- 1. What physically arrived from suppliers

WITH inbound_receipts AS (
    SELECT
        warehouse_id,
        product_sk,
        SUM(received_qty) AS total_received_qty
    FROM
        mart.fact_receipts
    GROUP BY
        warehouse_id,
        product_sk
),

-- 2. What physically left the building for customers (Fulfilled Sales)

outbound_sales AS (
    SELECT
        warehouse_id,
        product_sk,
        SUM(fulfilled_qty) AS total_sold_qty
    FROM
        mart.fact_sales
    GROUP BY
        warehouse_id,
        product_sk
),

-- 3. What moved INTO this warehouse from another warehouse

movements_in AS (
    SELECT
        to_warehouse_id AS warehouse_id,
        product_sk,
        SUM(quantity) AS total_transferred_in_qty
    FROM
        mart.fact_movements
    WHERE
        to_warehouse_id IS NOT NULL
    GROUP BY
        to_warehouse_id,
        product_sk
),

-- 4. What moved OUT OF this warehouse to another warehouse

movements_out AS (
    SELECT
        from_warehouse_id AS warehouse_id,
        product_sk,
        SUM(quantity) AS total_transferred_out_qty
    FROM
        mart.fact_movements
    WHERE
        from_warehouse_id IS NOT NULL
    GROUP BY
        from_warehouse_id,
        product_sk
),

-- 5. The  Warehouse Management System (WMS) Claim (The Latest Snapshot the warehouse manager is looking at)

latest_snapshots AS (
    SELECT
        warehouse_id,
        product_sk,
        on_hand_qty AS wms_reported_qty
    FROM
        mart.fact_snapshots
    WHERE
        snapshot_date = (
            SELECT
                MAX(snapshot_date)
            FROM
                mart.fact_snapshots
        )
) 

-- 6. The Master Join & Audit Math

SELECT
    COALESCE(
        ls.warehouse_id,
        ir.warehouse_id,
        os.warehouse_id
    ) AS warehouse_id,
    COALESCE(ls.product_sk, ir.product_sk, os.product_sk) AS product_sk,
    -- The Components (COALESCE to 0 so nulls don't break addition)
    COALESCE(ir.total_received_qty, 0) AS total_received_qty,
    COALESCE(mi.total_transferred_in_qty, 0) AS total_transferred_in_qty,
    COALESCE(mo.total_transferred_out_qty, 0) AS total_transferred_out_qty,
    COALESCE(os.total_sold_qty, 0) AS total_sold_qty,
    -- The Truth (Physical Ledger)
    (
        COALESCE(ir.total_received_qty, 0) + COALESCE(mi.total_transferred_in_qty, 0) - COALESCE(mo.total_transferred_out_qty, 0) - COALESCE(os.total_sold_qty, 0)
    ) AS calculated_physical_qty,
    -- The Claim (WMS System)
    COALESCE(ls.wms_reported_qty, 0) AS wms_reported_qty,
    -- The Discrepancy Math
    (
        COALESCE(ls.wms_reported_qty, 0) - (
            COALESCE(ir.total_received_qty, 0) + COALESCE(mi.total_transferred_in_qty, 0) - COALESCE(mo.total_transferred_out_qty, 0) - COALESCE(os.total_sold_qty, 0)
        )
    ) AS discrepancy_qty,
    -- Categorizing the Lie
    CASE
        WHEN COALESCE(ls.wms_reported_qty, 0) > (
            COALESCE(ir.total_received_qty, 0) + COALESCE(mi.total_transferred_in_qty, 0) - COALESCE(mo.total_transferred_out_qty, 0) - COALESCE(os.total_sold_qty, 0)
        ) THEN 'FALSE_STOCK'
        WHEN COALESCE(ls.wms_reported_qty, 0) < (
            COALESCE(ir.total_received_qty, 0) + COALESCE(mi.total_transferred_in_qty, 0) - COALESCE(mo.total_transferred_out_qty, 0) - COALESCE(os.total_sold_qty, 0)
        ) THEN 'MISSING_STOCK'
        ELSE 'ACCURATE'
    END AS discrepancy_status
FROM
    latest_snapshots AS ls FULL
    OUTER JOIN inbound_receipts AS ir ON ls.warehouse_id = ir.warehouse_id
    AND ls.product_sk = ir.product_sk FULL
    OUTER JOIN outbound_sales AS os ON COALESCE(ls.warehouse_id, ir.warehouse_id) = os.warehouse_id
    AND COALESCE(ls.product_sk, ir.product_sk) = os.product_sk
    LEFT JOIN movements_in AS mi ON COALESCE(
        ls.warehouse_id,
        ir.warehouse_id,
        os.warehouse_id
    ) = mi.warehouse_id
    AND COALESCE(ls.product_sk, ir.product_sk, os.product_sk) = mi.product_sk
    LEFT JOIN movements_out AS mo ON COALESCE(
        ls.warehouse_id,
        ir.warehouse_id,
        os.warehouse_id
    ) = mo.warehouse_id
    AND COALESCE(ls.product_sk, ir.product_sk, os.product_sk) = mo.product_sk;

/*
 =========================================
 THE SOLUTIONS (How this code fixes the problems)
 =========================================
 1. Pre-Aggregation (The CTE Isolation): 
 Before any tables are allowed to touch each other, I trapped them in CTEs (WITH blocks). I forced them to sum up their quantities grouped by Warehouse and Product. By compressing them to exactly one row per product *first*, they can never multiply each other when joined.
 
 2. COALESCE (The Blank Fixer):
 I wrapped every single number in `COALESCE(column_name, 0)`. This tells the database: "If you see a BLANK, pretend it is a zero." This guarantees our addition and subtraction never crashes.
 
 3. FULL OUTER JOIN (The Safety Net):
 Instead of a normal join, I used `FULL OUTER JOIN`. This forces the database to keep a product in the final report even if it only exists in one table (e.g., received but never sold, or snapshotted but never moved). 
 
 4. The Lie Detector (The Physics Math):
 I ignored the warehouse system's claim completely and calculated the absolute truth of physics: 
 (Boxes Received + Boxes Transferred In) - (Boxes Sold + Boxes Transferred Out) = True Physical Inventory. 
 
 Then, I compared my calculated Truth against the Computer's Claim using a CASE statement:
 - If the computer claims we have MORE than the truth = 'FALSE_STOCK' (Ghost inventory).
 - If the computer claims we have LESS than the truth = 'MISSING_STOCK' (Stolen or lost).
 - If they match = 'ACCURATE'.
 
 5. The Freshness Lock:
 Inside the `latest_snapshots` CTE, I used `SELECT MAX(snapshot_date)` to ensure we are only comparing our math against the freshest, most recent photo of the warehouse, ignoring months of old, useless snapshot history.
 */