/*
 =========================================
 THE PROBLEMS (Why we build this Fact)
 =========================================
 1. The Grain Mismatch:
    Logistics data (shipments) operates at a different physical grain than sales or receipts. A carrier tracks a container (Shipment ID) and a manifest (PO ID), not individual SKUs. 
 
 2. Engineering Clutter & Zombies:
    We need pure transit timelines. We must drop API ingestion metadata and permanently filter out any webhook rows that failed physical time-travel validation in the quarantine layer.

 3. The "Just Use the Clean Table" Trap:
    Why not just point Power BI directly at `clean_shipments`? Because dashboards are fragile. If we connect the BI tool directly to our engineering plumbing, the dashboard breaks the second we change how we process raw data. Plus, it forces us to give analysts security access to our entire engineering dataset instead of just the finished, approved data.
 */
--_________________________________________________________________________________________________________________________________________________________________
CREATE OR REPLACE TABLE `mart.fact_shipments` AS

SELECT
    shipment_id,
    po_id,
    tracking_id,
    carrier_id,
    supplier_handover_date,
    ship_date,
    expected_arrival_date,
    destination_warehouse_id
FROM
    clean.clean_shipments
WHERE
    is_valid_record = TRUE
--_________________________________________________________________________________________________________________________________________________________________
/*
 =========================================
 THE SOLUTIONS (How we built this Fact)
 =========================================
 1. PO-Level Grain Lock:
    Extracted the pure logistics Verbs (shipment dates, arrival dates, tracking IDs). This table is designed to join downstream to `fact_purchase_orders` to calculate exact Supplier and Carrier lead times without multiplying row counts.
 
 2. Executive Filter:
    Hardcoded `is_valid_record = TRUE` to physically block impossible time-travel records from destroying SLA dashboard calculations.

 3. The Showroom Boundary (Decoupling):
    Even though we didn't write a complex join here, creating this view acts as a permanent, protective shield. We give the BI team access ONLY to the `mart` dataset (the showroom). If our ERP system changes next year and we have to completely rebuild the `clean` layer (the factory floor), we just update this view. The dashboard never breaks, and the analysts are structurally blocked from making mistakes.
 */