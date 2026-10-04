/*
 =========================================
 THE PROBLEMS (Why we build this Fact)
 =========================================
 1. The Grain Mismatch (Again):
    Carrier webhooks track the box (`tracking_id`), not the SKUs inside the box. Trying to force a join to `dim_product` here would physically break the data model.
 2. Engineering Clutter:
    Dashboards tracking carrier performance don't need backend API extraction metadata. 
 */
--_________________________________________________________________________________________________________________________________________________________________
CREATE OR REPLACE TABLE `mart.fact_telemetry` AS

SELECT
    tracking_id,
    shipment_id,
    delivery_status,
    event_name,
    location,
    exception_code,
    event_timestamp
FROM
    clean.clean_telemetry
WHERE
    is_valid_record = TRUE;
--_________________________________________________________________________________________________________________________________________________________________
/*
 =========================================
 THE SOLUTIONS (How we built this Fact)
 =========================================
 1. The Pure Event Log:
    Extracted the critical milestones (Customs Holds, Supplier Handovers) and exception codes so the logistics team can track exactly where boxes are getting stuck.
 2. The Showroom Boundary:
    Created this view to decouple the BI dashboards from the raw engineering pipeline, ensuring stability and strict access control.
 */