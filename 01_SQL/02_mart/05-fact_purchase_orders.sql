/*
 =========================================
 THE PROBLEMS (Why we build this Fact)
 =========================================
 1. The Supplier's Ledger:
    Purchase orders lock in the price and quantity of what we expect to receive. If we don't connect these directly to the exact shape-shifting version of the product we ordered, our financial liability reports will be wildly inaccurate.
 2. Engineering Clutter:
    Finance needs dollars and dates, not batch IDs and ingestion timestamps.
 */

--_________________________________________________________________________________________________________________________________________________________________
CREATE OR REPLACE TABLE `mart.fact_purchase_orders` AS

select
    dp.product_sk,
    po.po_id,
    po.po_line,
    po.po_date,
    po.supplier_id,
    po.warehouse_id,
    po.ordered_qty,
    po.unit_cost_foreign,
    po.currency_code,
    po.expected_delivery_date,
    po.supplier_promised_ship_date,
    po.status
from
    clean.clean_purchase_orders as po
    LEFT JOIN mart.dim_product as dp on po.sku_id = dp.sku_id
    and po.po_date >= dp.effective_from
    AND (
        po.po_date < dp.effective_to
        OR dp.effective_to IS NULL
    )
where
    po.is_valid_record = TRUE
--_________________________________________________________________________________________________________________________________________________________________

/*
 =========================================
 THE SOLUTIONS (How we built this Fact)
 =========================================
 1. Point-in-Time Resolution:
    Used a temporal `LEFT JOIN` against `dim_product`. By anchoring on `po_date`, we grab the exact Surrogate Key (`product_sk`) for the product category/status at the exact moment the order was placed.
 2. The Math Layer:
    Exposed only the Verbs (events, quantities, prices, expected dates) and Foreign Keys to join to the Supplier and Warehouse dimensions.
 */