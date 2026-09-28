/*
 =========================================
 THE PROBLEMS I FOUND IN THE RAW DATA (raw.goods_receipts)
 =========================================
 1. The Disconnected Dock: 
    The warehouse dock receives boxes and generates receipts, but the raw data has no idea if we actually ordered those boxes. If we blindly trust the dock, we could pay for phantom inventory.
 
 2. Temporal Fraud (Time Travel): 
    Because systems lag or people make typos, a receipt might claim the boxes arrived on Tuesday, even though the Purchase Order wasn't created until Friday. 

 3. Standard Garbage: 
    The usual suspects: 10 different date formats, "N/A" strings masquerading as data, and duplicate receipt scans from the barcode guns.
 */

--_________________________________________________________________________________________________________________________________________________________________

CREATE OR REPLACE VIEW `clean.clean_receipts` AS

with fixed_receipts as (
    select
        CASE
            WHEN UPPER(TRIM(receipt_id_raw)) = 'N/A' THEN NULL
            ELSE UPPER(TRIM(receipt_id_raw))
        END AS receipt_id,
        --
        CASE
            WHEN UPPER(TRIM(po_id_raw)) = 'N/A' THEN NULL
            ELSE UPPER(TRIM(po_id_raw))
        END AS po_id,
        --
        CASE
            WHEN UPPER(TRIM(sku_id_raw)) = 'N/A' THEN NULL
            ELSE UPPER(TRIM(sku_id_raw))
        END AS sku_id,
        --
        CASE
            WHEN UPPER(TRIM(warehouse_id_raw)) = 'N/A' THEN NULL
            ELSE UPPER(TRIM(warehouse_id_raw))
        END AS warehouse_id,
        --
        COALESCE(
            -- 1. YYYY-MM-DD HH:MM:SS
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%d %H:%M:%S',
                TRIM(actual_receipt_date_raw)
            ),
            -- 2. YYYY-MM-DDTHH:MM:SSZ
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%dT%H:%M:%SZ',
                TRIM(actual_receipt_date_raw)
            ),
            -- 3. YYYY-MM-DDTHH:MM:SS+05:30
            -- BigQuery can directly cast ISO timestamps with timezone
            SAFE_CAST(
                TRIM(actual_receipt_date_raw) AS TIMESTAMP
            ),
            -- With Z
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%dT%H:%M:%SZ',
                TRIM(actual_receipt_date_raw)
            ),
            -- Without timezone
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%dT%H:%M:%S',
                TRIM(actual_receipt_date_raw)
            ),
            SAFE.PARSE_TIMESTAMP('%d-%m-%Y', TRIM(actual_receipt_date_raw)),
            --dd/mm/yy
            SAFE.PARSE_TIMESTAMP('%d/%m/%Y', TRIM(actual_receipt_date_raw)),
            -- 4. YYYY-MM-DD
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%d',
                TRIM(actual_receipt_date_raw)
            ),
            -- 5. MM-DD-YYYY
            -- Only use when second part > 12
            -- Example: 01-14-2025
            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(actual_receipt_date_raw),
                    r'^\d{2}-\d{2}-\d{4}$'
                )
                AND SAFE_CAST(
                    SPLIT(TRIM(actual_receipt_date_raw), '-') [SAFE_OFFSET(1)] AS INT64
                ) > 12 THEN SAFE.PARSE_TIMESTAMP(
                    '%m-%d-%Y',
                    TRIM(actual_receipt_date_raw)
                )
            END,
            -- 6. DD-MM-YYYY
            -- Only use when first part > 12
            -- Example: 24-09-2025
            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(actual_receipt_date_raw),
                    r'^\d{2}-\d{2}-\d{4}$'
                )
                AND SAFE_CAST(
                    SPLIT(TRIM(actual_receipt_date_raw), '-') [SAFE_OFFSET(0)] AS INT64
                ) > 12 THEN SAFE.PARSE_TIMESTAMP(
                    '%d-%m-%Y',
                    TRIM(actual_receipt_date_raw)
                )
            END,
            -- 7. MM/DD/YYYY
            -- Only use when second part > 12
            -- Example: 09/24/2025
            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(actual_receipt_date_raw),
                    r'^\d{2}/\d{2}/\d{4}$'
                )
                AND SAFE_CAST(
                    SPLIT(TRIM(actual_receipt_date_raw), '/') [SAFE_OFFSET(1)] AS INT64
                ) > 12 THEN SAFE.PARSE_TIMESTAMP(
                    '%m/%d/%Y',
                    TRIM(actual_receipt_date_raw)
                )
            END,
            -- 8. DD/MM/YYYY
            -- Only use when first part > 12
            -- Example: 21/01/2025
            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(actual_receipt_date_raw),
                    r'^\d{2}/\d{2}/\d{4}$'
                )
                AND SAFE_CAST(
                    SPLIT(TRIM(actual_receipt_date_raw), '/') [SAFE_OFFSET(0)] AS INT64
                ) > 12 THEN SAFE.PARSE_TIMESTAMP(
                    '%d/%m/%Y',
                    TRIM(actual_receipt_date_raw)
                )
            END,
            -- 9. Unix timestamp - seconds
            -- Example: 1752690600
            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(actual_receipt_date_raw),
                    r'^\d{10}$'
                ) THEN TIMESTAMP_SECONDS(
                    SAFE_CAST(
                        TRIM(actual_receipt_date_raw) AS INT64
                    )
                )
            END,
            -- 10. Excel serial date
            -- Example: 45716
            CASE
                WHEN SAFE_CAST(
                    TRIM(actual_receipt_date_raw) AS FLOAT64
                ) BETWEEN 30000
                AND 60000
                AND NOT REGEXP_CONTAINS(
                    TRIM(actual_receipt_date_raw),
                    r'^\d{10}$'
                ) THEN TIMESTAMP_SECONDS(
                    CAST(
                        (
                            SAFE_CAST(
                                TRIM(actual_receipt_date_raw) AS FLOAT64
                            ) - 25569
                        ) * 86400 AS INT64
                    )
                )
            END
        ) AS actual_receipt_date,
        --
        COALESCE(
            -- 1. YYYY-MM-DD HH:MM:SS
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%d %H:%M:%S',
                TRIM(putaway_date_raw)
            ),
            -- 2. YYYY-MM-DDTHH:MM:SSZ
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%dT%H:%M:%SZ',
                TRIM(putaway_date_raw)
            ),
            -- 3. YYYY-MM-DDTHH:MM:SS+05:30
            -- BigQuery can directly cast ISO timestamps with timezone
            SAFE_CAST(
                TRIM(putaway_date_raw) AS TIMESTAMP
            ),
            -- With Z
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%dT%H:%M:%SZ',
                TRIM(putaway_date_raw)
            ),
            -- Without timezone
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%dT%H:%M:%S',
                TRIM(putaway_date_raw)
            ),
            SAFE.PARSE_TIMESTAMP('%d-%m-%Y', TRIM(putaway_date_raw)),
            --dd/mm/yy
            SAFE.PARSE_TIMESTAMP('%d/%m/%Y', TRIM(putaway_date_raw)),
            -- 4. YYYY-MM-DD
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%d',
                TRIM(putaway_date_raw)
            ),
            -- 5. MM-DD-YYYY
            -- Only use when second part > 12
            -- Example: 01-14-2025
            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(putaway_date_raw),
                    r'^\d{2}-\d{2}-\d{4}$'
                )
                AND SAFE_CAST(
                    SPLIT(TRIM(putaway_date_raw), '-') [SAFE_OFFSET(1)] AS INT64
                ) > 12 THEN SAFE.PARSE_TIMESTAMP(
                    '%m-%d-%Y',
                    TRIM(putaway_date_raw)
                )
            END,
            -- 6. DD-MM-YYYY
            -- Only use when first part > 12
            -- Example: 24-09-2025
            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(putaway_date_raw),
                    r'^\d{2}-\d{2}-\d{4}$'
                )
                AND SAFE_CAST(
                    SPLIT(TRIM(putaway_date_raw), '-') [SAFE_OFFSET(0)] AS INT64
                ) > 12 THEN SAFE.PARSE_TIMESTAMP(
                    '%d-%m-%Y',
                    TRIM(putaway_date_raw)
                )
            END,
            -- 7. MM/DD/YYYY
            -- Only use when second part > 12
            -- Example: 09/24/2025
            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(putaway_date_raw),
                    r'^\d{2}/\d{2}/\d{4}$'
                )
                AND SAFE_CAST(
                    SPLIT(TRIM(putaway_date_raw), '/') [SAFE_OFFSET(1)] AS INT64
                ) > 12 THEN SAFE.PARSE_TIMESTAMP(
                    '%m/%d/%Y',
                    TRIM(putaway_date_raw)
                )
            END,
            -- 8. DD/MM/YYYY
            -- Only use when first part > 12
            -- Example: 21/01/2025
            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(putaway_date_raw),
                    r'^\d{2}/\d{2}/\d{4}$'
                )
                AND SAFE_CAST(
                    SPLIT(TRIM(putaway_date_raw), '/') [SAFE_OFFSET(0)] AS INT64
                ) > 12 THEN SAFE.PARSE_TIMESTAMP(
                    '%d/%m/%Y',
                    TRIM(putaway_date_raw)
                )
            END,
            -- 9. Unix timestamp - seconds
            -- Example: 1752690600
            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(putaway_date_raw),
                    r'^\d{10}$'
                ) THEN TIMESTAMP_SECONDS(
                    SAFE_CAST(
                        TRIM(putaway_date_raw) AS INT64
                    )
                )
            END,
            -- 10. Excel serial date
            -- Example: 45716
            CASE
                WHEN SAFE_CAST(
                    TRIM(putaway_date_raw) AS FLOAT64
                ) BETWEEN 30000
                AND 60000
                AND NOT REGEXP_CONTAINS(
                    TRIM(putaway_date_raw),
                    r'^\d{10}$'
                ) THEN TIMESTAMP_SECONDS(
                    CAST(
                        (
                            SAFE_CAST(
                                TRIM(putaway_date_raw) AS FLOAT64
                            ) - 25569
                        ) * 86400 AS INT64
                    )
                )
            END
        ) AS putaway_date,
        --
        SAFE_CAST(received_qty_raw AS INT64) AS received_qty,
        --
        SAFE_CAST(rejected_qty_raw AS INT64) AS rejected_qty,
        --
        upper(trim(wms_bin_location_raw)) as wms_bin_location,
        --
        upper(trim(source_system)) as source_system,
        --	
        COALESCE(
            -- 1. YYYY-MM-DD HH:MM:SS
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%d %H:%M:%S',
                TRIM(record_updated_at)
            ),
            -- 2. YYYY-MM-DDTHH:MM:SSZ
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%dT%H:%M:%SZ',
                TRIM(record_updated_at)
            ),
            -- 3. YYYY-MM-DDTHH:MM:SS+05:30
            -- BigQuery can directly cast ISO timestamps with timezone
            SAFE_CAST(
                TRIM(record_updated_at) AS TIMESTAMP
            ),
            -- With Z
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%dT%H:%M:%SZ',
                TRIM(record_updated_at)
            ),
            -- Without timezone
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%dT%H:%M:%S',
                TRIM(record_updated_at)
            ),
            SAFE.PARSE_TIMESTAMP(
                '%d-%m-%Y',
                TRIM(record_updated_at)
            ),
            --dd/mm/yy
            SAFE.PARSE_TIMESTAMP(
                '%d/%m/%Y',
                TRIM(record_updated_at)
            ),
            -- 4. YYYY-MM-DD
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%d',
                TRIM(record_updated_at)
            ),
            -- 5. MM-DD-YYYY
            -- Only use when second part > 12
            -- Example: 01-14-2025
            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(record_updated_at),
                    r'^\d{2}-\d{2}-\d{4}$'
                )
                AND SAFE_CAST(
                    SPLIT(TRIM(record_updated_at), '-') [SAFE_OFFSET(1)] AS INT64
                ) > 12 THEN SAFE.PARSE_TIMESTAMP(
                    '%m-%d-%Y',
                    TRIM(record_updated_at)
                )
            END,
            -- 6. DD-MM-YYYY
            -- Only use when first part > 12
            -- Example: 24-09-2025
            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(record_updated_at),
                    r'^\d{2}-\d{2}-\d{4}$'
                )
                AND SAFE_CAST(
                    SPLIT(TRIM(record_updated_at), '-') [SAFE_OFFSET(0)] AS INT64
                ) > 12 THEN SAFE.PARSE_TIMESTAMP(
                    '%d-%m-%Y',
                    TRIM(record_updated_at)
                )
            END,
            -- 7. MM/DD/YYYY
            -- Only use when second part > 12
            -- Example: 09/24/2025
            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(record_updated_at),
                    r'^\d{2}/\d{2}/\d{4}$'
                )
                AND SAFE_CAST(
                    SPLIT(TRIM(record_updated_at), '/') [SAFE_OFFSET(1)] AS INT64
                ) > 12 THEN SAFE.PARSE_TIMESTAMP(
                    '%m/%d/%Y',
                    TRIM(record_updated_at)
                )
            END,
            -- 8. DD/MM/YYYY
            -- Only use when first part > 12
            -- Example: 21/01/2025
            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(record_updated_at),
                    r'^\d{2}/\d{2}/\d{4}$'
                )
                AND SAFE_CAST(
                    SPLIT(TRIM(record_updated_at), '/') [SAFE_OFFSET(0)] AS INT64
                ) > 12 THEN SAFE.PARSE_TIMESTAMP(
                    '%d/%m/%Y',
                    TRIM(record_updated_at)
                )
            END,
            -- 9. Unix timestamp - seconds
            -- Example: 1752690600
            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(record_updated_at),
                    r'^\d{10}$'
                ) THEN TIMESTAMP_SECONDS(
                    SAFE_CAST(
                        TRIM(record_updated_at) AS INT64
                    )
                )
            END,
            -- 10. Excel serial date
            -- Example: 45716
            CASE
                WHEN SAFE_CAST(
                    TRIM(record_updated_at) AS FLOAT64
                ) BETWEEN 30000
                AND 60000
                AND NOT REGEXP_CONTAINS(
                    TRIM(record_updated_at),
                    r'^\d{10}$'
                ) THEN TIMESTAMP_SECONDS(
                    CAST(
                        (
                            SAFE_CAST(
                                TRIM(record_updated_at) AS FLOAT64
                            ) - 25569
                        ) * 86400 AS INT64
                    )
                )
            END
        ) AS record_updated_at_clean,
        --
        COALESCE(
            -- 1. YYYY-MM-DD HH:MM:SS
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%d %H:%M:%S',
                TRIM(ingestion_timestamp)
            ),
            -- 2. YYYY-MM-DDTHH:MM:SSZ
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%dT%H:%M:%SZ',
                TRIM(ingestion_timestamp)
            ),
            -- 3. YYYY-MM-DDTHH:MM:SS+05:30
            -- BigQuery can directly cast ISO timestamps with timezone
            SAFE_CAST(
                TRIM(ingestion_timestamp) AS TIMESTAMP
            ),
            -- With Z
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%dT%H:%M:%SZ',
                TRIM(ingestion_timestamp)
            ),
            -- Without timezone
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%dT%H:%M:%S',
                TRIM(ingestion_timestamp)
            ),
            SAFE.PARSE_TIMESTAMP('%d-%m-%Y', TRIM(ingestion_timestamp)),
            --dd/mm/yy
            SAFE.PARSE_TIMESTAMP('%d/%m/%Y', TRIM(ingestion_timestamp)),
            -- 4. YYYY-MM-DD
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%d',
                TRIM(ingestion_timestamp)
            ),
            -- 5. MM-DD-YYYY
            -- Only use when second part > 12
            -- Example: 01-14-2025
            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(ingestion_timestamp),
                    r'^\d{2}-\d{2}-\d{4}$'
                )
                AND SAFE_CAST(
                    SPLIT(TRIM(ingestion_timestamp), '-') [SAFE_OFFSET(1)] AS INT64
                ) > 12 THEN SAFE.PARSE_TIMESTAMP(
                    '%m-%d-%Y',
                    TRIM(ingestion_timestamp)
                )
            END,
            -- 6. DD-MM-YYYY
            -- Only use when first part > 12
            -- Example: 24-09-2025
            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(ingestion_timestamp),
                    r'^\d{2}-\d{2}-\d{4}$'
                )
                AND SAFE_CAST(
                    SPLIT(TRIM(ingestion_timestamp), '-') [SAFE_OFFSET(0)] AS INT64
                ) > 12 THEN SAFE.PARSE_TIMESTAMP(
                    '%d-%m-%Y',
                    TRIM(ingestion_timestamp)
                )
            END,
            -- 7. MM/DD/YYYY
            -- Only use when second part > 12
            -- Example: 09/24/2025
            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(ingestion_timestamp),
                    r'^\d{2}/\d{2}/\d{4}$'
                )
                AND SAFE_CAST(
                    SPLIT(TRIM(ingestion_timestamp), '/') [SAFE_OFFSET(1)] AS INT64
                ) > 12 THEN SAFE.PARSE_TIMESTAMP(
                    '%m/%d/%Y',
                    TRIM(ingestion_timestamp)
                )
            END,
            -- 8. DD/MM/YYYY
            -- Only use when first part > 12
            -- Example: 21/01/2025
            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(ingestion_timestamp),
                    r'^\d{2}/\d{2}/\d{4}$'
                )
                AND SAFE_CAST(
                    SPLIT(TRIM(ingestion_timestamp), '/') [SAFE_OFFSET(0)] AS INT64
                ) > 12 THEN SAFE.PARSE_TIMESTAMP(
                    '%d/%m/%Y',
                    TRIM(ingestion_timestamp)
                )
            END,
            -- 9. Unix timestamp - seconds
            -- Example: 1752690600
            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(ingestion_timestamp),
                    r'^\d{10}$'
                ) THEN TIMESTAMP_SECONDS(
                    SAFE_CAST(
                        TRIM(ingestion_timestamp) AS INT64
                    )
                )
            END,
            -- 10. Excel serial date
            -- Example: 45716
            CASE
                WHEN SAFE_CAST(
                    TRIM(ingestion_timestamp) AS FLOAT64
                ) BETWEEN 30000
                AND 60000
                AND NOT REGEXP_CONTAINS(
                    TRIM(ingestion_timestamp),
                    r'^\d{10}$'
                ) THEN TIMESTAMP_SECONDS(
                    CAST(
                        (
                            SAFE_CAST(
                                TRIM(ingestion_timestamp) AS FLOAT64
                            ) - 25569
                        ) * 86400 AS INT64
                    )
                )
            END
        ) AS ingestion_timestamp_clean,
        --
        CONCAT(
            SPLIT(batch_id, '_') [SAFE_OFFSET(0)],
            '_',
            SPLIT(batch_id, '_') [SAFE_OFFSET(1)]
        ) AS clean_batch_id
    from
        raw.receipts
),
clean_receipts as (
    select
        *,
        CASE
            WHEN receipt_id IS NULL
            OR receipt_id = '' THEN FALSE
            WHEN po_id IS NULL
            OR po_id = '' THEN FALSE
            WHEN sku_id IS NULL
            OR sku_id = '' THEN FALSE
            WHEN warehouse_id IS NULL
            OR warehouse_id = '' THEN FALSE
            WHEN actual_receipt_date IS NULL THEN FALSE
            WHEN putaway_date IS NULL THEN FALSE
            WHEN received_qty IS NULL THEN FALSE
            WHEN rejected_qty IS NULL THEN FALSE
            WHEN wms_bin_location IS NULL
            OR wms_bin_location = '' THEN FALSE
            WHEN source_system IS NULL
            OR source_system = '' THEN FALSE
            WHEN record_updated_at_clean IS NULL THEN FALSE
            WHEN ingestion_timestamp_clean IS NULL THEN FALSE
            WHEN clean_batch_id IS NULL
            OR clean_batch_id = '' THEN FALSE
            ELSE TRUE
        END AS is_valid_record,
        --
        CASE
            WHEN receipt_id IS NULL
            OR receipt_id = '' THEN 'MISSING_RECEIPT_ID'
            WHEN po_id IS NULL
            OR po_id = '' THEN 'MISSING_PO_ID'
            WHEN sku_id IS NULL
            OR sku_id = '' THEN 'MISSING_SKU_ID'
            WHEN warehouse_id IS NULL
            OR warehouse_id = '' THEN 'MISSING_WAREHOUSE_ID'
            WHEN actual_receipt_date IS NULL THEN 'MISSING_ACTUAL_RECEIPT_DATE'
            WHEN putaway_date IS NULL THEN 'MISSING_PUTAWAY_DATE'
            WHEN received_qty IS NULL THEN 'INVALID_RECEIVED_QUANTITY'
            WHEN rejected_qty IS NULL THEN 'INVALID_REJECTED_QUANTITY'
            WHEN wms_bin_location IS NULL
            OR wms_bin_location = '' THEN 'MISSING_WMS_BIN_LOCATION'
            WHEN source_system IS NULL
            OR source_system = '' THEN 'MISSING_SOURCE_SYSTEM'
            WHEN record_updated_at_clean IS NULL THEN 'MISSING_RECORD_UPDATED_AT'
            WHEN ingestion_timestamp_clean IS NULL THEN 'MISSING_INGESTION_TIMESTAMP'
            WHEN clean_batch_id IS NULL
            OR clean_batch_id = '' THEN 'MISSING_BATCH_ID'
            ELSE NULL
        END AS exception_reason
    from
        fixed_receipts
),
deduplicated_receipts AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY receipt_id,
            sku_id
            ORDER BY
                record_updated_at_clean DESC
        ) AS row_num
    from
        clean_receipts
),
cross_checked_receipts AS (
    SELECT
        t1.*,
        t2.po_date as joined_po_date,
        t2.po_id as joined_po_id
    FROM
        deduplicated_receipts as t1
        LEFT JOIN `clean.clean_purchase_orders` as t2 ON t1.po_id = t2.po_id
        AND t1.sku_id = t2.sku_id
    WHERE
        t1.row_num = 1
)
select
    receipt_id,
    po_id,
    sku_id,
    warehouse_id,
    actual_receipt_date,
    putaway_date,
    received_qty,
    rejected_qty,
    wms_bin_location,
    source_system,
    record_updated_at_clean,
    ingestion_timestamp_clean,
    clean_batch_id,
    -------
    case
        when is_valid_record = false then false -- Keep previous failures
        WHEN joined_po_id IS NULL THEN FALSE 
        WHEN actual_receipt_date < joined_po_date THEN FALSE -- The Time Travel Test
        WHEN received_qty < 0 THEN FALSE
            WHEN rejected_qty < 0 THEN FALSE
            WHEN putaway_date < actual_receipt_date THEN FALSE
        ELSE TRUE
    END AS is_valid_record,
    -------
    CASE
        WHEN exception_reason IS NOT NULL THEN exception_reason -- Keep previous failures
        WHEN joined_po_id IS NULL THEN 'ORPHAN_RECEIPT'
        WHEN actual_receipt_date < joined_po_date THEN 'TIMETRAVEL_RECEIPT'
        WHEN received_qty < 0 THEN 'INVALID_NEGATIVE_RECEIVED_QTY'
            WHEN rejected_qty < 0 THEN 'INVALID_NEGATIVE_REJECTED_QTY'
            WHEN putaway_date < actual_receipt_date THEN 'TIMETRAVEL_PUTAWAY_BEFORE_RECEIPT'
        ELSE NULL
    END AS exception_reason
FROM
    cross_checked_receipts

--_________________________________________________________________________________________________________________________________________________________________

/*
 =========================================
 HOW I FIXED IT (THE SOLUTIONS)
 =========================================
 1. The Cross-Table Interrogation: 
    I didn't just clean this table in isolation. I used a LEFT JOIN to cross-reference every receipt against the `clean_purchase_orders` table (locking the grain by both PO ID and SKU ID to prevent duplication).

 2. The Orphan Trap: 
    If a receipt claims to belong to a Purchase Order that doesn't exist in our cleaned PO table, it gets flagged as FALSE (`ORPHAN_RECEIPT`). We stop phantom inventory at the door.

 3. The Physics Engine: 
    If the actual receipt date is mathematically older than the PO creation date, it gets flagged as FALSE (`TIMETRAVEL_RECEIPT`). 

 4. Cascading Quarantine: 
    I built a multi-stage validation engine. It checks for basic missing data first, and only runs the advanced cross-table checks if the row is fundamentally sound, ensuring we never overwrite basic errors with advanced ones.
 */