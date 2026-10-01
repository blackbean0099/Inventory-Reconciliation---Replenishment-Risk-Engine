/*
 =========================================
 THE PROBLEMS I FOUND IN THE RAW DATA (raw.snapshots)
 =========================================
 1. The Flattened Timeline: 
    A snapshot is a daily record, but systems often send duplicate updates for the same day. If we deduplicate incorrectly, we wipe out historical inventory data.

 2. Broken Physics (Negative Inventory): 
    The ERP system occasionally claims we have negative quantities on hand (e.g., -5 laptops). This is physically impossible and usually the result of a race condition in the source system's ledger.

 3. Standard Ghost Data & Time Traps: 
    "N/A" strings masquerading as missing IDs, and dates suffering from the 10-format time trap.
 */
--_________________________________________________________________________________________________________________________________________________________________

CREATE OR REPLACE VIEW `clean.clean_snapshots` AS

with fixed_snapshots as (
    SELECT
        COALESCE(
            -- 1. YYYY-MM-DD HH:MM:SS
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%d %H:%M:%S',
                TRIM(snapshot_date_raw)
            ),
            -- 2. YYYY-MM-DDTHH:MM:SSZ
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%dT%H:%M:%SZ',
                TRIM(snapshot_date_raw)
            ),
            -- 3. YYYY-MM-DDTHH:MM:SS+05:30
            -- BigQuery can directly cast ISO timestamps with timezone
            SAFE_CAST(
                TRIM(snapshot_date_raw) AS TIMESTAMP
            ),
            -- With Z
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%dT%H:%M:%SZ',
                TRIM(snapshot_date_raw)
            ),
            -- Without timezone
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%dT%H:%M:%S',
                TRIM(snapshot_date_raw)
            ),
            SAFE.PARSE_TIMESTAMP('%d-%m-%Y', TRIM(snapshot_date_raw)),
            --dd/mm/yy
            SAFE.PARSE_TIMESTAMP('%d/%m/%Y', TRIM(snapshot_date_raw)),
            -- 4. YYYY-MM-DD
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%d',
                TRIM(snapshot_date_raw)
            ),
            -- 5. MM-DD-YYYY
            -- Only use when second part > 12
            -- Example: 01-14-2025
            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(snapshot_date_raw),
                    r'^\d{2}-\d{2}-\d{4}$'
                )
                AND SAFE_CAST(
                    SPLIT(TRIM(snapshot_date_raw), '-') [SAFE_OFFSET(1)] AS INT64
                ) > 12 THEN SAFE.PARSE_TIMESTAMP(
                    '%m-%d-%Y',
                    TRIM(snapshot_date_raw)
                )
            END,
            -- 6. DD-MM-YYYY
            -- Only use when first part > 12
            -- Example: 24-09-2025
            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(snapshot_date_raw),
                    r'^\d{2}-\d{2}-\d{4}$'
                )
                AND SAFE_CAST(
                    SPLIT(TRIM(snapshot_date_raw), '-') [SAFE_OFFSET(0)] AS INT64
                ) > 12 THEN SAFE.PARSE_TIMESTAMP(
                    '%d-%m-%Y',
                    TRIM(snapshot_date_raw)
                )
            END,
            -- 7. MM/DD/YYYY
            -- Only use when second part > 12
            -- Example: 09/24/2025
            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(snapshot_date_raw),
                    r'^\d{2}/\d{2}/\d{4}$'
                )
                AND SAFE_CAST(
                    SPLIT(TRIM(snapshot_date_raw), '/') [SAFE_OFFSET(1)] AS INT64
                ) > 12 THEN SAFE.PARSE_TIMESTAMP(
                    '%m/%d/%Y',
                    TRIM(snapshot_date_raw)
                )
            END,
            -- 8. DD/MM/YYYY
            -- Only use when first part > 12
            -- Example: 21/01/2025
            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(snapshot_date_raw),
                    r'^\d{2}/\d{2}/\d{4}$'
                )
                AND SAFE_CAST(
                    SPLIT(TRIM(snapshot_date_raw), '/') [SAFE_OFFSET(0)] AS INT64
                ) > 12 THEN SAFE.PARSE_TIMESTAMP(
                    '%d/%m/%Y',
                    TRIM(snapshot_date_raw)
                )
            END,
            -- 9. Unix timestamp - seconds
            -- Example: 1752690600
            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(snapshot_date_raw),
                    r'^\d{10}$'
                ) THEN TIMESTAMP_SECONDS(
                    SAFE_CAST(
                        TRIM(snapshot_date_raw) AS INT64
                    )
                )
            END,
            -- 10. Excel serial date
            -- Example: 45716
            CASE
                WHEN SAFE_CAST(
                    TRIM(snapshot_date_raw) AS FLOAT64
                ) BETWEEN 30000
                AND 60000
                AND NOT REGEXP_CONTAINS(
                    TRIM(snapshot_date_raw),
                    r'^\d{10}$'
                ) THEN TIMESTAMP_SECONDS(
                    CAST(
                        (
                            SAFE_CAST(
                                TRIM(snapshot_date_raw) AS FLOAT64
                            ) - 25569
                        ) * 86400 AS INT64
                    )
                )
            END
        ) AS snapshot_date,
        --
        CASE
            WHEN UPPER(TRIM(warehouse_id_raw)) = 'N/A' THEN NULL
            ELSE UPPER(TRIM(warehouse_id_raw))
        END AS warehouse_id,
        --
        CASE
            WHEN UPPER(TRIM(sku_id_raw)) = 'N/A' THEN NULL
            ELSE UPPER(TRIM(sku_id_raw))
        END AS sku_id,
        --
        SAFE_CAST(on_hand_qty_raw AS INT64) AS on_hand_qty,
        --
        SAFE_CAST(reserved_qty_raw AS INT64) AS reserved_qty,
        --
        SAFE_CAST(damaged_qty_raw AS INT64) AS damaged_qty,
        --
        CASE
            WHEN UPPER(TRIM(source_timestamp_raw)) = 'N/A' THEN NULL
            ELSE UPPER(TRIM(source_timestamp_raw))
        END AS source_timestamp,
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
    FROM
        raw.snapshots
),
clean_snapshots as (
    select
        *,
        CASE
            WHEN snapshot_date IS NULL THEN FALSE
            WHEN warehouse_id IS NULL
            OR warehouse_id = '' THEN FALSE
            WHEN sku_id IS NULL
            OR sku_id = '' THEN FALSE
            WHEN on_hand_qty IS NULL THEN FALSE
            WHEN reserved_qty IS NULL THEN FALSE
            WHEN damaged_qty IS NULL THEN FALSE
            WHEN source_timestamp IS NULL THEN FALSE
            WHEN record_updated_at_clean IS NULL THEN FALSE
            WHEN ingestion_timestamp_clean IS NULL THEN FALSE
            WHEN clean_batch_id IS NULL
            OR clean_batch_id = '' THEN FALSE
            WHEN on_hand_qty < 0
            OR reserved_qty < 0
            OR damaged_qty < 0 then FALSE
            ELSE TRUE
        END AS is_valid_record,
        --
        CASE
            WHEN snapshot_date IS NULL THEN 'MISSING_SNAPSHOT_DATE'
            WHEN warehouse_id IS NULL
            OR warehouse_id = '' THEN 'MISSING_WAREHOUSE_ID'
            WHEN sku_id IS NULL
            OR sku_id = '' THEN 'MISSING_SKU_ID'
            WHEN on_hand_qty IS NULL THEN 'INVALID_ON_HAND_QUANTITY'
            WHEN reserved_qty IS NULL THEN 'INVALID_RESERVED_QUANTITY'
            WHEN damaged_qty IS NULL THEN 'INVALID_DAMAGED_QUANTITY'
            WHEN source_timestamp IS NULL THEN 'MISSING_SOURCE_TIMESTAMP'
            WHEN record_updated_at_clean IS NULL THEN 'MISSING_RECORD_UPDATED_AT'
            WHEN ingestion_timestamp_clean IS NULL THEN 'MISSING_INGESTION_TIMESTAMP'
            WHEN clean_batch_id IS NULL
            OR clean_batch_id = '' THEN 'MISSING_BATCH_ID'
            WHEN on_hand_qty < 0 THEN 'NEGATIVE_ON_HAND_QTY'
            WHEN reserved_qty < 0 THEN 'NEGATIVE_RESERVED_QTY'
            WHEN damaged_qty < 0 THEN 'NEGATIVE_DAMAGED_QTY'
            ELSE NULL
        END AS exception_reason
    from
        fixed_snapshots
),
deduplicated_snapshots as (
    select
        *,
        ROW_NUMBER() OVER (
            PARTITION BY warehouse_id,
            sku_id,
            CAST(snapshot_date AS DATE)
            ORDER BY
                record_updated_at_clean DESC
        ) AS row_num
    from
        clean_snapshots
)
select
    snapshot_date,
    is_valid_record,
    exception_reason,
    warehouse_id,
    sku_id,
    on_hand_qty,
    reserved_qty,
    damaged_qty,
    source_timestamp,
    record_updated_at_clean,
    ingestion_timestamp_clean,
    clean_batch_id
from
    deduplicated_snapshots
where
    row_num = 1
--_________________________________________________________________________________________________________________________________________________________________
/*
 =========================================
 HOW I FIXED IT (THE SOLUTIONS)
 =========================================
 1. Time-Series Deduplication: 
    Used a Window Function partitioned by Warehouse, SKU, AND the exact Snapshot Date. This mathematically guarantees we keep exactly one true inventory record per SKU, per day, without destroying historical timelines.

 2. The Physics Engine: 
    Enforced strict rules on `on_hand_qty`, `reserved_qty`, and `damaged_qty`. If any of these drop below zero, the row is flagged as FALSE and quarantined (`NEGATIVE_ON_HAND_QTY`).

 3. Universal Date Translator & Smart Quarantine: 
    Normalized all dates to standard timestamps and strictly quarantined any records missing core IDs.
 */