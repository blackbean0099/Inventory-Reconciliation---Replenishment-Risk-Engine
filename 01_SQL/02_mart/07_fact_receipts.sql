/*
 =========================================
 THE PROBLEMS (Why we build this Fact)
 =========================================
 1. The Dock Illusion:
    When a box hits the receiving dock, we need to log it into financial inventory immediately. If we don't resolve the product to its exact state on that specific day, we miscalculate our inbound asset valuation.
 2. Engineering Clutter:
    Warehouse managers only care about what arrived, when it arrived, and where it was put away. They do not care about API batch IDs.
 */

--_________________________________________________________________________________________________________________________________________________________________
CREATE OR REPLACE TABLE `mart.fact_receipts` AS

select
    dp.product_sk,
    cr.receipt_id,
    cr.po_id,
    cr.warehouse_id,
    cr.actual_receipt_date,
    cr.putaway_date,
    cr.received_qty,
    cr.rejected_qty,
    cr.wms_bin_location
from
    clean.clean_receipts as cr
    LEFT JOIN mart.dim_product as dp ON cr.sku_id = dp.sku_id
    and cr.actual_receipt_date >= dp.effective_from
    and (
        cr.actual_receipt_date < dp.effective_to
        OR dp.effective_to IS NULL
    )
WHERE
    cr.is_valid_record = TRUE
--_________________________________________________________________________________________________________________________________________________________________
/*
 =========================================
 THE SOLUTIONS (How we built this Fact)
 =========================================
 1. Point-in-Time Resolution (The Dock Lock):
    Used a temporal `LEFT JOIN` against `dim_product`. By anchoring on `actual_receipt_date`, we grab the exact Surrogate Key (`product_sk`) representing the product's true category and status the moment it entered the building.
 2. The Clean Receiving Ledger:
    Exposed only the Verbs (receipt events, received vs. rejected quantities, putaway dates) to serve as a pure ledger for inbound supply chain metrics.
 */