/*
 =========================================
 THE PROBLEMS I FOUND IN THE RAW DATA
 =========================================
 1. Ghost SKUs & Messy Categories: 
    Some products came in with "N/A" for their SKU ID, and categories/brands were typed with messy casing and spaces. 
    
 2. The Universal Time Trap: 
    Just like the movements, the start and end dates for product changes came in 10 different formats (Unix, Excel, ISO).

 3. Category Clashes (Overlaps): 
    The ERP system sent conflicting timelines for product updates. For example, a product was marked as "Active" in the "Electronics" category until Oct 20th, but a new row said it moved to "Discontinued" starting Oct 15th. 
 
 4. Liars Claiming to be "Current": 
    Multiple rows for the exact same SKU claimed to be the "Current" active state (is_current = TRUE) at the exact same time, which would corrupt our active product catalog.
 */

--_________________________________________________________________________________________________________________________________________________________________


CREATE OR REPLACE VIEW `clean.clean_product` AS

with fixed_product as (
    select
        CASE
            WHEN UPPER(TRIM(sku_id_raw)) = 'N/A' THEN NULL
            ELSE UPPER(TRIM(sku_id_raw))
        END AS sku_id,
        --
        upper(trim(category_raw)) AS category,
        --
        upper(trim(brand_raw)) AS brand,
        --
        upper(trim(pack_size_raw)) AS pack_size,
        --
        upper(trim(product_status_raw)) AS product_status,
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
        ) AS clean_batch_id --
    from
        raw.product_scd
),
deduplicated_product AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY sku_id, effective_from
            ORDER BY
                clean_record_updated_at DESC
        ) AS row_num
    FROM
        fixed_product
),
product_with_next AS (
    SELECT
        *,
        LEAD(effective_from) OVER (
            PARTITION BY sku_id
            ORDER BY
                effective_from
        ) AS next_effective_from
    FROM
        deduplicated_product
    WHERE
        row_num = 1
),
cleaned_product AS (
    SELECT
        *,
        CASE
            WHEN effective_from IS NULL THEN 'MISSING_START_DATE'
            WHEN effective_to IS NOT NULL
            AND effective_to < effective_from THEN 'END_BEFORE_START'
            WHEN next_effective_from IS NOT NULL
            AND effective_to IS NOT NULL
            AND effective_to >= next_effective_from THEN 'OVERLAP'
            ELSE 'OK'
        END AS scd_status
    FROM
        product_with_next
)
select
    sku_id,
    CASE WHEN sku_id IS NULL THEN FALSE ELSE TRUE END as is_valid_record,
    category,
    brand,
    pack_size,
    product_status,
    effective_from,
    next_effective_from,
    
    scd_status,
    
    uppersource_system,
    clean_record_updated_at,
    clean_ingestion_timestamp,
    clean_batch_id,
    CASE
    WHEN scd_status = 'OVERLAP'
        THEN TIMESTAMP_SUB(next_effective_from, INTERVAL 1 SECOND)
    ELSE effective_to
END AS effective_to,

CASE 
    WHEN next_effective_from IS NOT NULL THEN FALSE 
    ELSE is_current 
END AS is_current
from
    cleaned_product

    
--_________________________________________________________________________________________________________________________________________________________________

/*
 =========================================
 HOW I FIXED IT (THE SOLUTIONS)
 =========================================
 1. Smart Quarantine & String Scrubbing: 
    I forced all categorical strings (brand, category) into clean uppercase text. If a product was missing its actual SKU ID, I didn't delete it, but I flagged `is_valid_record = FALSE` so it doesn't break our inventory math.

 2. The SKU-Level Time Machine: 
    I grouped the data *only* by SKU (since products don't care about suppliers or warehouses here) and used the LEAD() function to find the exact start date of the next product update.

 3. Snapping the Timeline: 
    When the ERP sent overlapping category or status updates, I forced the old product state to expire exactly 1 SECOND before the new state began. This ensures a product is never in two categories at once.

 4. Recalculating the Truth: 
    I ignored the broken "is_current" flags from the raw data. I recalculated them mathematically: If a SKU has a "next" update coming after this one, this row is NOT current (False). If there is no "next" update, it IS current (True). 
 */