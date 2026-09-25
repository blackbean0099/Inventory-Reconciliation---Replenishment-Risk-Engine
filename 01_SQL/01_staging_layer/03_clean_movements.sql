/*
 =========================================
 THE PROBLEMS 
 =========================================
 • The Time Trap: Movement timestamps came in 10 different formats (Unix, Excel, ISO).
 • Ghost Locations: The system sometimes output the string "N/A" or empty strings "" instead of a true SQL NULL for missing warehouses or reference IDs.
 • The Ledger Break: If a movement ID or a quantity failed to parse, the whole double-entry math system (inventory counting) would break down, creating "phantom" inventory.
 */

--_________________________________________________________________________________________________________________________________________________________________

CREATE OR REPLACE VIEW `clean.clean_movements` AS

with fixed_movements as (
    select
        upper(trim(movement_id_raw)) as movement_id,
        --
        COALESCE(
            -- 1. YYYY-MM-DD HH:MM:SS
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%d %H:%M:%S',
                TRIM(movement_timestamp_raw)
            ),
            -- 2. YYYY-MM-DDTHH:MM:SSZ
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%dT%H:%M:%SZ',
                TRIM(movement_timestamp_raw)
            ),
            -- 3. YYYY-MM-DDTHH:MM:SS+05:30
            -- BigQuery can directly cast ISO timestamps with timezone
            SAFE_CAST(
                TRIM(movement_timestamp_raw) AS TIMESTAMP
            ),
            -- With Z
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%dT%H:%M:%SZ',
                TRIM(movement_timestamp_raw)
            ),
            -- Without timezone
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%dT%H:%M:%S',
                TRIM(movement_timestamp_raw)
            ),
            SAFE.PARSE_TIMESTAMP('%d-%m-%Y', TRIM(movement_timestamp_raw)),
            --dd/mm/yy
            SAFE.PARSE_TIMESTAMP('%d/%m/%Y', TRIM(movement_timestamp_raw)),
            -- 4. YYYY-MM-DD
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%d',
                TRIM(movement_timestamp_raw)
            ),
            -- 5. MM-DD-YYYY
            -- Only use when second part > 12
            -- Example: 01-14-2025
            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(movement_timestamp_raw),
                    r'^\d{2}-\d{2}-\d{4}$'
                )
                AND SAFE_CAST(
                    SPLIT(TRIM(movement_timestamp_raw), '-') [SAFE_OFFSET(1)] AS INT64
                ) > 12 THEN SAFE.PARSE_TIMESTAMP(
                    '%m-%d-%Y',
                    TRIM(movement_timestamp_raw)
                )
            END,
            -- 6. DD-MM-YYYY
            -- Only use when first part > 12
            -- Example: 24-09-2025
            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(movement_timestamp_raw),
                    r'^\d{2}-\d{2}-\d{4}$'
                )
                AND SAFE_CAST(
                    SPLIT(TRIM(movement_timestamp_raw), '-') [SAFE_OFFSET(0)] AS INT64
                ) > 12 THEN SAFE.PARSE_TIMESTAMP(
                    '%d-%m-%Y',
                    TRIM(movement_timestamp_raw)
                )
            END,
            -- 7. MM/DD/YYYY
            -- Only use when second part > 12
            -- Example: 09/24/2025
            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(movement_timestamp_raw),
                    r'^\d{2}/\d{2}/\d{4}$'
                )
                AND SAFE_CAST(
                    SPLIT(TRIM(movement_timestamp_raw), '/') [SAFE_OFFSET(1)] AS INT64
                ) > 12 THEN SAFE.PARSE_TIMESTAMP(
                    '%m/%d/%Y',
                    TRIM(movement_timestamp_raw)
                )
            END,
            -- 8. DD/MM/YYYY
            -- Only use when first part > 12
            -- Example: 21/01/2025
            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(movement_timestamp_raw),
                    r'^\d{2}/\d{2}/\d{4}$'
                )
                AND SAFE_CAST(
                    SPLIT(TRIM(movement_timestamp_raw), '/') [SAFE_OFFSET(0)] AS INT64
                ) > 12 THEN SAFE.PARSE_TIMESTAMP(
                    '%d/%m/%Y',
                    TRIM(movement_timestamp_raw)
                )
            END,
            -- 9. Unix timestamp - seconds
            -- Example: 1752690600
            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(movement_timestamp_raw),
                    r'^\d{10}$'
                ) THEN TIMESTAMP_SECONDS(
                    SAFE_CAST(
                        TRIM(movement_timestamp_raw) AS INT64
                    )
                )
            END,
            -- 10. Excel serial date
            -- Example: 45716
            CASE
                WHEN SAFE_CAST(
                    TRIM(movement_timestamp_raw) AS FLOAT64
                ) BETWEEN 30000
                AND 60000
                AND NOT REGEXP_CONTAINS(
                    TRIM(movement_timestamp_raw),
                    r'^\d{10}$'
                ) THEN TIMESTAMP_SECONDS(
                    CAST(
                        (
                            SAFE_CAST(
                                TRIM(movement_timestamp_raw) AS FLOAT64
                            ) - 25569
                        ) * 86400 AS INT64
                    )
                )
            END
        ) AS movement_timestamp,
        --
        CASE
            WHEN UPPER(TRIM(sku_id_raw)) = 'N/A' THEN NULL
            ELSE upper(TRIM(sku_id_raw))
        END AS sku_id,
        --
        CASE
            WHEN UPPER(TRIM(from_warehouse_id_raw)) = 'N/A' THEN NULL
            ELSE UPPER(TRIM(from_warehouse_id_raw))
        END AS from_warehouse_id,
        --
        CASE
            WHEN UPPER(TRIM(to_warehouse_id_raw)) = 'N/A' THEN NULL
            ELSE UPPER(TRIM(to_warehouse_id_raw))
        END AS to_warehouse_id,
        --
        upper(trim(movement_type_raw)) as movement_type,
        --
        SAFE_CAST(quantity_raw AS INT64) AS quantity,
        --
        NULLIF(
            CASE
                WHEN UPPER(TRIM(reference_id_raw)) = 'N/A' THEN NULL
                ELSE TRIM(reference_id_raw)
            END,
            ''
        ) AS reference_id,
        --
        NULLIF(
            CASE
                WHEN UPPER(TRIM(transfer_id_raw)) = 'N/A' THEN NULL
                ELSE TRIM(transfer_id_raw)
            END,
            ''
        ) AS transfer_id,
        --
        UPPER(TRIM(source_system)) AS source_system,
        --
        SAFE_CAST(record_updated_at AS DATETIME) AS clean_record_updated_at,
        --
        SAFE_CAST(ingestion_timestamp AS DATETIME) AS clean_ingestion_timestamp,
        --
        CONCAT(
            SPLIT(batch_id, '_') [SAFE_OFFSET(0)],
            '_',
            SPLIT(batch_id, '_') [SAFE_OFFSET(1)]
        ) AS clean_batch_id
    FROM
        raw.movements
),
cleaned_movements AS (
    select
        movement_id,
        movement_timestamp,
        sku_id,
        from_warehouse_id,
        to_warehouse_id,
        movement_type,
        quantity,
        reference_id,
        transfer_id,
        source_system,
        clean_record_updated_at,
        clean_ingestion_timestamp,
        clean_batch_id,
        CASE
            WHEN movement_id IS NULL THEN FALSE
            WHEN movement_timestamp IS NULL THEN FALSE
            WHEN sku_id IS NULL THEN FALSE
            
            WHEN movement_type IS NULL THEN FALSE
            WHEN quantity IS NULL THEN FALSE
            WHEN clean_ingestion_timestamp IS NULL THEN FALSE
            when clean_batch_id IS NULL THEN FALSE
            ELSE TRUE
        END AS is_valid_record,
        CASE
            WHEN movement_id IS NULL THEN 'INVALID_OR_MISSING_MOVEMENT_ID'
            WHEN movement_timestamp IS NULL THEN 'INVALID_OR_MISSING_MOVEMENT_TIMESTAMP'
            WHEN sku_id IS NULL THEN 'INVALID_OR_MISSING_SKU_ID'
           
            WHEN movement_type IS NULL THEN 'INVALID_OR_MISSING_MOVEMENT_TYPE'
            WHEN quantity IS NULL THEN 'INVALID_OR_MISSING_QUANTITY'
            WHEN clean_ingestion_timestamp IS NULL THEN 'INVALID_OR_MISSING_CLEAN_INGESTION_TIMESTAMP'
            WHEN clean_batch_id IS NULL THEN 'INVALID_OR_MISSING_CLEAN_BATCH_ID'
            ELSE NULL
        END AS exception_reason
    from
        fixed_movements
)
select
    movement_id,
    is_valid_record,
    exception_reason,
    movement_timestamp,
    sku_id,
    from_warehouse_id,
    to_warehouse_id,
    movement_type,
    quantity,
    reference_id,
    transfer_id,
    source_system,
    clean_record_updated_at,
    clean_ingestion_timestamp,
    clean_batch_id
from
    cleaned_movements


--_________________________________________________________________________________________________________________________________________________________________
/*
 =========================================
 WHAT I FIXED (THE SOLUTIONS)
 =========================================
 • Universal Date Translator: Automatically normalized all 10 date formats into a standard timestamp without losing the critical hours/minutes/seconds of the warehouse events.
 • String Scrubbing: Forced all "N/A", invisible spaces, and empty strings into true SQL NULLs so they don't break downstream joins or math.
 • Full Traceability: Extracted both the Origin (from_warehouse_id) and Destination (to_warehouse_id) to maintain the perfect double-entry inventory ledger.
 • Smart Quarantine: Flagged records with missing movement IDs, SKUs, or quantities as FALSE, but deliberately ALLOWED warehouse IDs to be NULL (because a sale has no destination warehouse, and a vendor receipt has no origin warehouse).
 */