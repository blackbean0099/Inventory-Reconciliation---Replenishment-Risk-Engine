/*
 =========================================
 THE PROBLEMS (Why we build this Fact)
 =========================================
 1. The Double-Entry Chaos:
    The movement table is the heartbeat of the warehouse. If a box moves, we need to know exactly what version of the product was in that box at that exact second. Joining on just SKU ID would duplicate every warehouse transfer in our history.
 2. Engineering Clutter:
    Inventory analysts need quantities, locations, and timestamps. They do not need to see quarantine exception flags or API ingestion times.
 */
--_________________________________________________________________________________________________________________________________________________________________
CREATE OR REPLACE TABLE `mart.fact_movements` AS

select
    dp.product_sk,
    cm.movement_id,
    cm.movement_timestamp,
    cm.from_warehouse_id,
    cm.to_warehouse_id,
    cm.movement_type,
    cm.quantity,
    cm.reference_id,
    cm.transfer_id
FROM
    clean.clean_movements as cm
    LEFT JOIN mart.dim_product as dp on cm.sku_id = dp.sku_id
    and cm.movement_timestamp >= dp.effective_from
    and (
        cm.movement_timestamp < dp.effective_to
        OR dp.effective_to IS NULL
    )
WHERE
    cm.is_valid_record = TRUE
--_________________________________________________________________________________________________________________________________________________________________
/*
 =========================================
 THE SOLUTIONS (How we built this Fact)
 =========================================
 1. Point-in-Time Resolution (The Physics Lock):
    Used a temporal `LEFT JOIN` against `dim_product`. By anchoring on the `movement_timestamp`, we grab the exact Surrogate Key (`product_sk`) representing the product's true state the exact second it was taken off the shelf.
 2. The Pure Ledger:
    Exposed only the Verbs (movement events, quantities, reference IDs) and the Foreign Keys connecting the origin and destination warehouses.
 */