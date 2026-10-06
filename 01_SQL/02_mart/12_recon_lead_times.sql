/*
 =========================================
 THE REAL-WORLD PROBLEMS (Why I wrote it this way)
 =========================================
 1. The "Who Dropped the Ball?" Problem:
    When an order arrives late, the supplier blames the shipping company (the carrier), and the carrier blames the supplier. Nobody wants to pay the late penalty. We need a mathematical way to prove exactly whose fault it is.
    
 2. The "Ghost Truck" Problem (Row Duplication):
    A single Purchase Order (PO) might contain 10 different products (SKUs). But all 10 of those products are packed onto 1 single truck (Shipment). If I just mash the Product table and the Truck table together using a normal JOIN, the database gets confused. It accidentally multiplies the truck by 10, and suddenly the reports say we had 10 trucks arrive instead of 1.

 3. The Exploding Math Problem (Date Crashes):
    To find out how many days late a delivery is, we have to subtract dates (Arrival Date minus Expected Date). But raw data is messy. Sometimes a date is missing, or typed in wrong. If you tell a database to do math on a broken date, the entire daily pipeline crashes, the dashboard goes blank, and everyone panics.
 */
--_________________________________________________________________________________________________________________________________________________________________


CREATE OR REPLACE TABLE `mart.recon_lead_times` AS

WITH base_orders AS (

    SELECT
        po_id,
        product_sk,
        ordered_qty,
        supplier_promised_ship_date
    FROM
        mart.fact_purchase_orders
),

actual_receipts AS (
    SELECT
        po_id,
        product_sk,
        MAX(actual_receipt_date) AS actual_receipt_date,
        SUM(received_qty) AS received_qty
    FROM
        mart.fact_receipts
    GROUP BY
        po_id,
        product_sk
),

shipment_tracking AS (
    SELECT
        po_id,
        MAX(supplier_handover_date) AS supplier_handover_date,
        MAX(ship_date) AS ship_date,
        MAX(expected_arrival_date) AS expected_arrival_date
    FROM
        mart.fact_shipments
    GROUP BY
        po_id
)

SELECT
    bo.po_id,
    bo.product_sk,
    bo.ordered_qty,
    COALESCE(ar.received_qty, 0) AS received_qty,
    
    -- The Shortage Math
    (bo.ordered_qty - COALESCE(ar.received_qty, 0)) AS shortage_qty,
    
    -- The Delay Math (BULLETPROOFED WITH SAFE_CAST)
    DATE_DIFF(
        SAFE_CAST(st.supplier_handover_date AS DATE),
        SAFE_CAST(bo.supplier_promised_ship_date AS DATE),
        DAY
    ) AS supplier_delay_days,
    
    DATE_DIFF(
        SAFE_CAST(ar.actual_receipt_date AS DATE), 
        SAFE_CAST(st.expected_arrival_date AS DATE), 
        DAY
    ) AS carrier_delay_days,
    
    -- The Blame Assignment
    CASE
        WHEN st.ship_date IS NULL THEN 'PENDING_SHIPMENT'
        WHEN ar.actual_receipt_date IS NULL THEN 'IN_TRANSIT'
        WHEN COALESCE(ar.received_qty, 0) < bo.ordered_qty THEN 'SHORT_SHIPPED'
        
        -- Grade the Supplier
        WHEN DATE_DIFF(
            SAFE_CAST(st.supplier_handover_date AS DATE),
            SAFE_CAST(bo.supplier_promised_ship_date AS DATE),
            DAY
        ) > 0 THEN 'SUPPLIER_LATE'
        
        -- Grade the Carrier
        WHEN DATE_DIFF(
            SAFE_CAST(ar.actual_receipt_date AS DATE), 
            SAFE_CAST(st.expected_arrival_date AS DATE), 
            DAY
        ) > 0 THEN 'CARRIER_LATE'
        
        ELSE 'ON_TIME'
    END AS fulfillment_status

FROM
    base_orders AS bo
    -- JOIN ORDER MATTERS: Join the specific SKU grain first, then the broader container grain
    LEFT JOIN actual_receipts AS ar 
        ON bo.po_id = ar.po_id AND bo.product_sk = ar.product_sk
    LEFT JOIN shipment_tracking AS st 
        ON bo.po_id = st.po_id;

--_________________________________________________________________________________________________________________________________________________________________

/*
 =========================================
 THE SOLUTIONS (How my code specifically fixes this)
 =========================================
 1. The Blame Waterfall (The CASE Statement):
    Look at the `CASE` statement at the bottom of the query. I built a strict grading system that checks for failures in a specific order:
    - First, did they even send us all the items? (If Received is less than Ordered -> 'SHORT_SHIPPED').
    - Next, did the Supplier take too long to build it and hand it over? (If Handover Date is after the Promised Date -> 'SUPPLIER_LATE').
    - Finally, if the supplier was on time, did the Carrier drive too slow? (If Actual Arrival is after Expected Arrival -> 'CARRIER_LATE').
    
 2. The "Pre-Squash" (Using CTEs to stop Ghost Trucks):
    Look at the `actual_receipts` and `shipment_tracking` blocks at the top. Before I ever let the tables touch each other, I trapped them in CTEs. I used `GROUP BY` and `MAX()` to squash the shipment data down so there is strictly only ONE row per Purchase Order. Because I grouped them first, it is mathematically impossible to create ghost trucks when I join them at the bottom.

 3. The Safety Net (SAFE_CAST):
    Look at the `DATE_DIFF` math. I wrapped every single date column inside `SAFE_CAST(column AS DATE)`. This is a bulletproof vest for the database. It tells BigQuery: "If you find a broken or missing date, don't crash the system. Just leave the answer blank (NULL) and move on to the next row."
 */