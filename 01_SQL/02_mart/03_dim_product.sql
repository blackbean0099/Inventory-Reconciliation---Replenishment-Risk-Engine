/*
 =========================================
 THE PROBLEMS (Why a standard table isn't enough)
 =========================================
 1. The Shape-Shifting SKU:
    A product changes over time (e.g., from "Active" to "Clearance"). Because of this, the same SKU exists on multiple rows. If we let the BI tool join on the natural `sku_id`, it will duplicate sales records and multiply our revenue falsely.
 
 2. The Distributed Database Trap:
    We need a single unique ID for each row, but generating a simple "1, 2, 3" counting ID in a massive cloud database like BigQuery is slow and fragile. If the pipeline rebuilds, the IDs might shuffle, breaking historical reports.
 */

--_________________________________________________________________________________________________________________________________________________________________
CREATE OR REPLACE TABLE `mart.dim_product` AS

select
TO_HEX(MD5(CONCAT(sku_id, '|', CAST(effective_from AS STRING)))) AS product_sk,
    sku_id,
    category,
    brand,
    pack_size,
    product_status,
    effective_from,
    effective_to,
    is_current
from
    clean.clean_product
WHERE
    is_valid_record = TRUE
--_________________________________________________________________________________________________________________________________________________________________

/*
 =========================================
 THE SOLUTIONS (How we built this dimension)
 =========================================
 1. The Surrogate Key (The Cryptographic Hash):
    Created `product_sk` by hashing the SKU and its Start Date together using `TO_HEX(MD5())`. This creates a mathematically permanent, unique fingerprint for every specific timeline version of a product. It never changes, and it gives Power BI a perfect, single-column join key.

 2. Presentation Ready:
    Filtered out the quarantined ghost records (`is_valid_record = TRUE`) and stripped away all backend pipeline metadata (batch IDs, ingestion times). We are handing the business a pristine, idiot-proof list of Nouns.
 */