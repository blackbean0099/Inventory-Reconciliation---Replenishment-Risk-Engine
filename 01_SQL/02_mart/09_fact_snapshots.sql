/*
 =========================================
 THE PROBLEMS (Why we build this Fact)
 =========================================
 1. The Moving Target:
    The WMS (Warehouse Management System) takes a daily snapshot of what it *thinks* is on the shelf. But because products change categories and statuses over time, checking the inventory of a SKU without locking in its exact historical state leads to broken asset valuation.
 
 2. The Zombie Data:
    The raw snapshots occasionally break the laws of physics (e.g., claiming negative inventory). If we don't physically block those rows, the dashboard will show negative assets.
 */

--_________________________________________________________________________________________________________________________________________________________________
CREATE OR REPLACE TABLE `mart.fact_snapshots` AS


select
    dp.product_sk,
    cs.warehouse_id,
    cs.snapshot_date,
    cs.on_hand_qty,
    cs.reserved_qty,
    cs.damaged_qty
from
    clean.clean_snapshots as cs
    LEFT JOIN mart.dim_product as dp on cs.sku_id = dp.sku_id
    AND cs.snapshot_date >= dp.effective_from
    AND (
        cs.snapshot_date < dp.effective_to
        OR dp.effective_to IS NULL
    )
where
    is_valid_record = TRUE
--_________________________________________________________________________________________________________________________________________________________________
/*
 =========================================
 THE SOLUTIONS (How we built this Fact)
 =========================================
 1. Point-in-Time Resolution (The Lie Detector Setup):
    Used a temporal `LEFT JOIN` against `dim_product`. By anchoring on `snapshot_date`, we grab the exact Surrogate Key (`product_sk`) representing the product's true category and status on the exact day the snapshot was taken.

 2. The Showroom Filter:
    Hardcoded `is_valid_record = TRUE` to ensure that impossible physics violations (negative inventory) are stripped out before the data ever reaches the reconciliation engine or the BI layer.
 */