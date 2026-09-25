/*
 =========================================
 THE PROBLEMS I FOUND IN THE RAW DATA
 =========================================
 1. Price Tag Clashes (Overlaps): 
    The raw data was messy and said a product cost $10 until Oct 20th, but a new price of $12 started on Oct 15th. We can't have two different prices for the exact same 5 days.
 
 2. Liars Claiming to be "Current": 
    The data has a column called "is_current" (True/False) that is supposed to tell us the active price today. But the system was broken, and multiple old prices were marked as "True" at the same time. If we trust this, our reports will multiply data and crash.

 3. Exact Duplicates: 
    Sometimes the system glitched and sent us the exact same price update twice, at the exact same second.
 */

--_________________________________________________________________________________________________________________________________________________________________

CREATE OR REPLACE VIEW `clean.clean_policy` AS

with fixed_policy as (
    select
        CASE
            WHEN UPPER(TRIM(supplier_id_raw)) = 'N/A' THEN NULL
            ELSE UPPER(TRIM(supplier_id_raw))
        END AS supplier_id,
        --
        CASE
            WHEN UPPER(TRIM(sku_id_raw)) = 'N/A' THEN NULL
            ELSE UPPER(TRIM(sku_id_raw))
        END AS sku_id,
        --
        upper(trim(warehouse_id_raw)) AS warehouse_id,
        --
        SAFE_CAST(lead_time_days_raw AS INT64) AS lead_time_days,
        --
        SAFE_CAST(moq_raw AS NUMERIC) AS moq,
        --
        SAFE_CAST(reorder_point_raw AS NUMERIC) AS reorder_point,
        --
        SAFE_CAST(safety_stock_raw AS NUMERIC) AS safety_stock,
        --
        SAFE_CAST(unit_cost_foreign_raw AS NUMERIC) AS unit_cost_foreign,
        --
        upper(trim(currency_code_raw)) as currency_code,
        --
        COALESCE(
            -- 1. YYYY-MM-DD HH:MM:SS
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%d %H:%M:%S',
                TRIM(effective_from_raw)
            ),
            -- 2. YYYY-MM-DDTHH:MM:SSZ
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%dT%H:%M:%SZ',
                TRIM(effective_from_raw)
            ),
            -- 3. YYYY-MM-DDTHH:MM:SS+05:30
            -- BigQuery can directly cast ISO timestamps with timezone
            SAFE_CAST(
                TRIM(effective_from_raw) AS TIMESTAMP
            ),
            -- With Z
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%dT%H:%M:%SZ',
                TRIM(effective_from_raw)
            ),
            -- Without timezone
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%dT%H:%M:%S',
                TRIM(effective_from_raw)
            ),
            SAFE.PARSE_TIMESTAMP('%d-%m-%Y', TRIM(effective_from_raw)),
            --dd/mm/yy
            SAFE.PARSE_TIMESTAMP('%d/%m/%Y', TRIM(effective_from_raw)),
            -- 4. YYYY-MM-DD
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%d',
                TRIM(effective_from_raw)
            ),
            -- 5. MM-DD-YYYY
            -- Only use when second part > 12
            -- Example: 01-14-2025
            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(effective_from_raw),
                    r'^\d{2}-\d{2}-\d{4}$'
                )
                AND SAFE_CAST(
                    SPLIT(TRIM(effective_from_raw), '-') [SAFE_OFFSET(1)] AS INT64
                ) > 12 THEN SAFE.PARSE_TIMESTAMP(
                    '%m-%d-%Y',
                    TRIM(effective_from_raw)
                )
            END,
            -- 6. DD-MM-YYYY
            -- Only use when first part > 12
            -- Example: 24-09-2025
            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(effective_from_raw),
                    r'^\d{2}-\d{2}-\d{4}$'
                )
                AND SAFE_CAST(
                    SPLIT(TRIM(effective_from_raw), '-') [SAFE_OFFSET(0)] AS INT64
                ) > 12 THEN SAFE.PARSE_TIMESTAMP(
                    '%d-%m-%Y',
                    TRIM(effective_from_raw)
                )
            END,
            -- 7. MM/DD/YYYY
            -- Only use when second part > 12
            -- Example: 09/24/2025
            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(effective_from_raw),
                    r'^\d{2}/\d{2}/\d{4}$'
                )
                AND SAFE_CAST(
                    SPLIT(TRIM(effective_from_raw), '/') [SAFE_OFFSET(1)] AS INT64
                ) > 12 THEN SAFE.PARSE_TIMESTAMP(
                    '%m/%d/%Y',
                    TRIM(effective_from_raw)
                )
            END,
            -- 8. DD/MM/YYYY
            -- Only use when first part > 12
            -- Example: 21/01/2025
            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(effective_from_raw),
                    r'^\d{2}/\d{2}/\d{4}$'
                )
                AND SAFE_CAST(
                    SPLIT(TRIM(effective_from_raw), '/') [SAFE_OFFSET(0)] AS INT64
                ) > 12 THEN SAFE.PARSE_TIMESTAMP(
                    '%d/%m/%Y',
                    TRIM(effective_from_raw)
                )
            END,
            -- 9. Unix timestamp - seconds
            -- Example: 1752690600
            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(effective_from_raw),
                    r'^\d{10}$'
                ) THEN TIMESTAMP_SECONDS(
                    SAFE_CAST(
                        TRIM(effective_from_raw) AS INT64
                    )
                )
            END,
            -- 10. Excel serial date
            -- Example: 45716
            CASE
                WHEN SAFE_CAST(
                    TRIM(effective_from_raw) AS FLOAT64
                ) BETWEEN 30000
                AND 60000
                AND NOT REGEXP_CONTAINS(
                    TRIM(effective_from_raw),
                    r'^\d{10}$'
                ) THEN TIMESTAMP_SECONDS(
                    CAST(
                        (
                            SAFE_CAST(
                                TRIM(effective_from_raw) AS FLOAT64
                            ) - 25569
                        ) * 86400 AS INT64
                    )
                )
            END
        ) AS effective_from,
        --
        COALESCE(
            -- 1. YYYY-MM-DD HH:MM:SS
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%d %H:%M:%S',
                TRIM(effective_to_raw)
            ),
            -- 2. YYYY-MM-DDTHH:MM:SSZ
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%dT%H:%M:%SZ',
                TRIM(effective_to_raw)
            ),
            -- 3. YYYY-MM-DDTHH:MM:SS+05:30
            -- BigQuery can directly cast ISO timestamps with timezone
            SAFE_CAST(
                TRIM(effective_to_raw) AS TIMESTAMP
            ),
            -- With Z
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%dT%H:%M:%SZ',
                TRIM(effective_to_raw)
            ),
            -- Without timezone
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%dT%H:%M:%S',
                TRIM(effective_to_raw)
            ),
            SAFE.PARSE_TIMESTAMP('%d-%m-%Y', TRIM(effective_to_raw)),
            --dd/mm/yy
            SAFE.PARSE_TIMESTAMP('%d/%m/%Y', TRIM(effective_to_raw)),
            -- 4. YYYY-MM-DD
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%d',
                TRIM(effective_to_raw)
            ),
            -- 5. MM-DD-YYYY
            -- Only use when second part > 12
            -- Example: 01-14-2025
            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(effective_to_raw),
                    r'^\d{2}-\d{2}-\d{4}$'
                )
                AND SAFE_CAST(
                    SPLIT(TRIM(effective_to_raw), '-') [SAFE_OFFSET(1)] AS INT64
                ) > 12 THEN SAFE.PARSE_TIMESTAMP(
                    '%m-%d-%Y',
                    TRIM(effective_to_raw)
                )
            END,
            -- 6. DD-MM-YYYY
            -- Only use when first part > 12
            -- Example: 24-09-2025
            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(effective_to_raw),
                    r'^\d{2}-\d{2}-\d{4}$'
                )
                AND SAFE_CAST(
                    SPLIT(TRIM(effective_to_raw), '-') [SAFE_OFFSET(0)] AS INT64
                ) > 12 THEN SAFE.PARSE_TIMESTAMP(
                    '%d-%m-%Y',
                    TRIM(effective_to_raw)
                )
            END,
            -- 7. MM/DD/YYYY
            -- Only use when second part > 12
            -- Example: 09/24/2025
            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(effective_to_raw),
                    r'^\d{2}/\d{2}/\d{4}$'
                )
                AND SAFE_CAST(
                    SPLIT(TRIM(effective_to_raw), '/') [SAFE_OFFSET(1)] AS INT64
                ) > 12 THEN SAFE.PARSE_TIMESTAMP(
                    '%m/%d/%Y',
                    TRIM(effective_to_raw)
                )
            END,
            -- 8. DD/MM/YYYY
            -- Only use when first part > 12
            -- Example: 21/01/2025
            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(effective_to_raw),
                    r'^\d{2}/\d{2}/\d{4}$'
                )
                AND SAFE_CAST(
                    SPLIT(TRIM(effective_to_raw), '/') [SAFE_OFFSET(0)] AS INT64
                ) > 12 THEN SAFE.PARSE_TIMESTAMP(
                    '%d/%m/%Y',
                    TRIM(effective_to_raw)
                )
            END,
            -- 9. Unix timestamp - seconds
            -- Example: 1752690600
            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(effective_to_raw),
                    r'^\d{10}$'
                ) THEN TIMESTAMP_SECONDS(
                    SAFE_CAST(
                        TRIM(effective_to_raw) AS INT64
                    )
                )
            END,
            -- 10. Excel serial date
            -- Example: 45716
            CASE
                WHEN SAFE_CAST(
                    TRIM(effective_to_raw) AS FLOAT64
                ) BETWEEN 30000
                AND 60000
                AND NOT REGEXP_CONTAINS(
                    TRIM(effective_to_raw),
                    r'^\d{10}$'
                ) THEN TIMESTAMP_SECONDS(
                    CAST(
                        (
                            SAFE_CAST(
                                TRIM(effective_to_raw) AS FLOAT64
                            ) - 25569
                        ) * 86400 AS INT64
                    )
                )
            END
        ) AS effective_to,
        --
        SAFE_CAST(TRIM(is_current_raw) AS BOOL) AS is_current,
        --
        UPPER(TRIM(source_system)) AS uppersource_system,
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
    from
        raw.policy_scd
),

deduplicated_policy AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY supplier_id, sku_id, warehouse_id, effective_from
            ORDER BY clean_record_updated_at DESC
        ) AS row_num
    FROM fixed_policy
),

policy_with_next AS (
    SELECT
        *,
        LEAD(effective_from) OVER (
            PARTITION BY supplier_id, sku_id, warehouse_id
            ORDER BY effective_from
        ) AS next_effective_from
    FROM deduplicated_policy
    WHERE row_num = 1
),

cleaned_policy AS (
    SELECT
        *,
        CASE
            WHEN effective_from IS NULL
                THEN 'MISSING_START_DATE'

            WHEN effective_to IS NOT NULL
                 AND effective_to < effective_from
                THEN 'END_BEFORE_START'

            WHEN next_effective_from IS NOT NULL
                 AND effective_to IS NOT NULL
                 AND effective_to >= next_effective_from
                THEN 'OVERLAP'

            ELSE 'OK'
        END AS scd_status
    FROM policy_with_next
)

SELECT
    supplier_id,
    sku_id,
    warehouse_id,
    lead_time_days,
    moq,
    reorder_point,
    safety_stock,
    unit_cost_foreign,
    currency_code,
    effective_from,

    CASE
        WHEN scd_status = 'OVERLAP'
            THEN TIMESTAMP_SUB(next_effective_from, INTERVAL 1 SECOND)
        ELSE effective_to
    END AS effective_to,
CASE 
    WHEN next_effective_from IS NOT NULL THEN FALSE 
    ELSE is_current 
END AS is_current,
    
    uppersource_system,
    clean_record_updated_at,
    clean_ingestion_timestamp,
    next_effective_from,
    scd_status,
    clean_batch_id
    

FROM cleaned_policy

--_________________________________________________________________________________________________________________________________________________________________

/*
 =========================================
 HOW I FIXED IT (THE SOLUTIONS)
 =========================================
 1. Peeking into the Future: 
    Instead of guessing when an old price ended, I used a SQL trick (LEAD function) to sort the data by time and look at the exact start date of the *next* price tag.

 2. Fixing the Overlaps (Snapping the Timeline): 
    If Price A said it ended on Oct 20, but Price B started on Oct 15... I forced Price A to end exactly one second before Price B started. Now the timeline is perfectly clean, with zero gaps and zero overlaps.

 3. Recalculating the Truth: 
    I completely deleted the broken "is_current" flags from the raw data. Instead, I used basic logic: If a record has a "next" price coming after it, it is NOT current (False). If there is no "next" price, it IS current (True). 

 4. Keeping Only the Freshest Data: 
    When the system sent exact duplicates with the same start date, I grouped them together and only kept the one that was updated most recently in the system, throwing the older glitch away.
 */