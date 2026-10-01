/*
 =========================================
 THE PROBLEMS I FOUND IN THE RAW DATA (raw.suppliers)
 =========================================
 1. Dirty Strings & Ghost Data: 
    The usual ERP mess. Inconsistent casing, hidden spaces, and "N/A" strings masquerading as missing data.
 2. The Time Trap: 
    Audit dates suffering from the standard 10-format timestamp chaos.
 */
--_________________________________________________________________________________________________________________________________________________________________
CREATE OR REPLACE VIEW `clean.clean_suppliers` AS

WITH fixed_suppliers AS (
select
    CASE
            WHEN UPPER(TRIM(supplier_id_raw)) = 'N/A' THEN NULL
            ELSE UPPER(TRIM(supplier_id_raw))
        END AS supplier_id,
    --
    CASE
            WHEN UPPER(TRIM(supplier_name_raw)) = 'N/A' THEN NULL
            ELSE UPPER(TRIM(supplier_name_raw))
        END AS supplier_name,
    --
    CASE
            WHEN UPPER(TRIM(country_raw)) = 'N/A' THEN NULL
            ELSE UPPER(TRIM(country_raw))
        END AS country,
    --
    upper(trim(timezone_raw)) as timezone,
    --
    upper(trim(status_raw)) as status,
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
    raw.suppliers
)
SELECT 
    supplier_id,
    supplier_name,
    country,
    timezone,
    status,
    source_system,
    record_updated_at_clean,
    ingestion_timestamp_clean,
    clean_batch_id,
    -- The Quarantine Logic
    CASE
        WHEN supplier_id IS NULL OR supplier_id = '' THEN FALSE
        WHEN record_updated_at_clean IS NULL THEN FALSE
        WHEN ingestion_timestamp_clean IS NULL THEN FALSE
        ELSE TRUE
    END AS is_valid_record,
    CASE
        WHEN supplier_id IS NULL OR supplier_id = '' THEN 'MISSING_SUPPLIER_ID'
        WHEN record_updated_at_clean IS NULL THEN 'MISSING_RECORD_UPDATED_AT'
        WHEN ingestion_timestamp_clean IS NULL THEN 'MISSING_INGESTION_TIMESTAMP'
        ELSE NULL
    END AS exception_reason
FROM fixed_suppliers;
--_________________________________________________________________________________________________________________________________________________________________
/*
 =========================================
 HOW I FIXED IT (THE SOLUTIONS)
 =========================================
 1. Standard Scrubbing: 
    Forced all text fields to uppercase and trimmed spaces to ensure perfect downstream joins. Converted fake "N/A" strings to true SQL NULLs.
 2. Universal Date Translator: 
    Normalized all audit dates to clean BigQuery timestamps.
 */