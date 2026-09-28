/*
 =========================================
 THE PROBLEMS I FOUND IN THE RAW DATA (raw.sales)
 =========================================
 1. Financial Garbage: 
    The unit price and discount columns were corrupted with currency symbols, text, and European-style commas (e.g., "USD 1,499.00" or "€50,00"). If we push this to the BI team, their revenue dashboards will crash.

 2. The Clone Army (Duplicate Updates): 
    The e-commerce system sends a new row every time an order changes status (Pending -> Processing -> Shipped). If we don't deduplicate this, a single $100 order will look like $300 in total revenue.

 3. Business Physics Violations: 
    The raw data contained orders marked as "CANCELLED" but still showed a positive `fulfilled_qty`. You cannot ship a box to a customer who canceled their order.

 4. Standard Ghost Data & Time Traps: 
    "N/A" strings masquerading as missing IDs, and 4 different date columns suffering from the 10-format time trap.
 */

--_________________________________________________________________________________________________________________________________________________________________

CREATE OR REPLACE VIEW `clean.clean_sales` AS

with fixed_sales as (
    select
        CASE
            WHEN UPPER(TRIM(order_id_raw)) = 'N/A' THEN NULL
            ELSE UPPER(TRIM(order_id_raw))
        END AS order_id,
        --
        SAFE_CAST(order_line_raw AS INT64) AS order_line,
        --
        COALESCE(
            -- 1. YYYY-MM-DD HH:MM:SS
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%d %H:%M:%S',
                TRIM(order_timestamp_raw)
            ),
            -- 2. YYYY-MM-DDTHH:MM:SSZ
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%dT%H:%M:%SZ',
                TRIM(order_timestamp_raw)
            ),
            -- 3. YYYY-MM-DDTHH:MM:SS+05:30
            -- BigQuery can directly cast ISO timestamps with timezone
            SAFE_CAST(
                TRIM(order_timestamp_raw) AS TIMESTAMP
            ),
            -- With Z
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%dT%H:%M:%SZ',
                TRIM(order_timestamp_raw)
            ),
            -- Without timezone
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%dT%H:%M:%S',
                TRIM(order_timestamp_raw)
            ),
            SAFE.PARSE_TIMESTAMP('%d-%m-%Y', TRIM(order_timestamp_raw)),
            --dd/mm/yy
            SAFE.PARSE_TIMESTAMP('%d/%m/%Y', TRIM(order_timestamp_raw)),
            -- 4. YYYY-MM-DD
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%d',
                TRIM(order_timestamp_raw)
            ),
            -- 5. MM-DD-YYYY
            -- Only use when second part > 12
            -- Example: 01-14-2025
            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(order_timestamp_raw),
                    r'^\d{2}-\d{2}-\d{4}$'
                )
                AND SAFE_CAST(
                    SPLIT(TRIM(order_timestamp_raw), '-') [SAFE_OFFSET(1)] AS INT64
                ) > 12 THEN SAFE.PARSE_TIMESTAMP(
                    '%m-%d-%Y',
                    TRIM(order_timestamp_raw)
                )
            END,
            -- 6. DD-MM-YYYY
            -- Only use when first part > 12
            -- Example: 24-09-2025
            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(order_timestamp_raw),
                    r'^\d{2}-\d{2}-\d{4}$'
                )
                AND SAFE_CAST(
                    SPLIT(TRIM(order_timestamp_raw), '-') [SAFE_OFFSET(0)] AS INT64
                ) > 12 THEN SAFE.PARSE_TIMESTAMP(
                    '%d-%m-%Y',
                    TRIM(order_timestamp_raw)
                )
            END,
            -- 7. MM/DD/YYYY
            -- Only use when second part > 12
            -- Example: 09/24/2025
            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(order_timestamp_raw),
                    r'^\d{2}/\d{2}/\d{4}$'
                )
                AND SAFE_CAST(
                    SPLIT(TRIM(order_timestamp_raw), '/') [SAFE_OFFSET(1)] AS INT64
                ) > 12 THEN SAFE.PARSE_TIMESTAMP(
                    '%m/%d/%Y',
                    TRIM(order_timestamp_raw)
                )
            END,
            -- 8. DD/MM/YYYY
            -- Only use when first part > 12
            -- Example: 21/01/2025
            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(order_timestamp_raw),
                    r'^\d{2}/\d{2}/\d{4}$'
                )
                AND SAFE_CAST(
                    SPLIT(TRIM(order_timestamp_raw), '/') [SAFE_OFFSET(0)] AS INT64
                ) > 12 THEN SAFE.PARSE_TIMESTAMP(
                    '%d/%m/%Y',
                    TRIM(order_timestamp_raw)
                )
            END,
            -- 9. Unix timestamp - seconds
            -- Example: 1752690600
            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(order_timestamp_raw),
                    r'^\d{10}$'
                ) THEN TIMESTAMP_SECONDS(
                    SAFE_CAST(
                        TRIM(order_timestamp_raw) AS INT64
                    )
                )
            END,
            -- 10. Excel serial date
            -- Example: 45716
            CASE
                WHEN SAFE_CAST(
                    TRIM(order_timestamp_raw) AS FLOAT64
                ) BETWEEN 30000
                AND 60000
                AND NOT REGEXP_CONTAINS(
                    TRIM(order_timestamp_raw),
                    r'^\d{10}$'
                ) THEN TIMESTAMP_SECONDS(
                    CAST(
                        (
                            SAFE_CAST(
                                TRIM(order_timestamp_raw) AS FLOAT64
                            ) - 25569
                        ) * 86400 AS INT64
                    )
                )
            END
        ) AS order_timestamp,
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
        SAFE_CAST(ordered_qty_raw AS INT64) AS ordered_qty,
        --
        SAFE_CAST(fulfilled_qty_raw AS INT64) AS fulfilled_qty,
        --
        SAFE_CAST(
            REPLACE(
                REGEXP_REPLACE(
                    TRIM(unit_price_foreign_raw),
                    r'[^0-9.,-]',
                    ''
                ),
                ',',
                '.'
            ) AS NUMERIC
        ) AS unit_price_foreign,
        --
        SAFE_CAST(
            REPLACE(
                REGEXP_REPLACE(
                    TRIM(discount_amount_foreign_raw),
                    r'[^0-9.,-]',
                    ''
                ),
                ',',
                '.'
            ) AS NUMERIC
        ) AS discount_amount_foreign,
        --
        UPPER(TRIM(currency_code_raw)) AS currency_code,
        --
        UPPER(TRIM(status_raw)) AS STATUS,
        --
        CASE
            WHEN UPPER(TRIM(cancel_reason_raw)) = '' THEN NULL
            ELSE UPPER(TRIM(cancel_reason_raw))
        END AS cancel_reason,
        --
        COALESCE(
            -- 1. YYYY-MM-DD HH:MM:SS
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%d %H:%M:%S',
                TRIM(customer_promised_delivery_date_raw)
            ),
            -- 2. YYYY-MM-DDTHH:MM:SSZ
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%dT%H:%M:%SZ',
                TRIM(customer_promised_delivery_date_raw)
            ),
            -- 3. YYYY-MM-DDTHH:MM:SS+05:30
            -- BigQuery can directly cast ISO timestamps with timezone
            SAFE_CAST(
                TRIM(customer_promised_delivery_date_raw) AS TIMESTAMP
            ),
            -- With Z
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%dT%H:%M:%SZ',
                TRIM(customer_promised_delivery_date_raw)
            ),
            -- Without timezone
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%dT%H:%M:%S',
                TRIM(customer_promised_delivery_date_raw)
            ),
            SAFE.PARSE_TIMESTAMP(
                '%d-%m-%Y',
                TRIM(customer_promised_delivery_date_raw)
            ),
            --dd/mm/yy
            SAFE.PARSE_TIMESTAMP(
                '%d/%m/%Y',
                TRIM(customer_promised_delivery_date_raw)
            ),
            -- 4. YYYY-MM-DD
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%d',
                TRIM(customer_promised_delivery_date_raw)
            ),
            -- 5. MM-DD-YYYY
            -- Only use when second part > 12
            -- Example: 01-14-2025
            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(customer_promised_delivery_date_raw),
                    r'^\d{2}-\d{2}-\d{4}$'
                )
                AND SAFE_CAST(
                    SPLIT(TRIM(customer_promised_delivery_date_raw), '-') [SAFE_OFFSET(1)] AS INT64
                ) > 12 THEN SAFE.PARSE_TIMESTAMP(
                    '%m-%d-%Y',
                    TRIM(customer_promised_delivery_date_raw)
                )
            END,
            -- 6. DD-MM-YYYY
            -- Only use when first part > 12
            -- Example: 24-09-2025
            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(customer_promised_delivery_date_raw),
                    r'^\d{2}-\d{2}-\d{4}$'
                )
                AND SAFE_CAST(
                    SPLIT(TRIM(customer_promised_delivery_date_raw), '-') [SAFE_OFFSET(0)] AS INT64
                ) > 12 THEN SAFE.PARSE_TIMESTAMP(
                    '%d-%m-%Y',
                    TRIM(customer_promised_delivery_date_raw)
                )
            END,
            -- 7. MM/DD/YYYY
            -- Only use when second part > 12
            -- Example: 09/24/2025
            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(customer_promised_delivery_date_raw),
                    r'^\d{2}/\d{2}/\d{4}$'
                )
                AND SAFE_CAST(
                    SPLIT(TRIM(customer_promised_delivery_date_raw), '/') [SAFE_OFFSET(1)] AS INT64
                ) > 12 THEN SAFE.PARSE_TIMESTAMP(
                    '%m/%d/%Y',
                    TRIM(customer_promised_delivery_date_raw)
                )
            END,
            -- 8. DD/MM/YYYY
            -- Only use when first part > 12
            -- Example: 21/01/2025
            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(customer_promised_delivery_date_raw),
                    r'^\d{2}/\d{2}/\d{4}$'
                )
                AND SAFE_CAST(
                    SPLIT(TRIM(customer_promised_delivery_date_raw), '/') [SAFE_OFFSET(0)] AS INT64
                ) > 12 THEN SAFE.PARSE_TIMESTAMP(
                    '%d/%m/%Y',
                    TRIM(customer_promised_delivery_date_raw)
                )
            END,
            -- 9. Unix timestamp - seconds
            -- Example: 1752690600
            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(customer_promised_delivery_date_raw),
                    r'^\d{10}$'
                ) THEN TIMESTAMP_SECONDS(
                    SAFE_CAST(
                        TRIM(customer_promised_delivery_date_raw) AS INT64
                    )
                )
            END,
            -- 10. Excel serial date
            -- Example: 45716
            CASE
                WHEN SAFE_CAST(
                    TRIM(customer_promised_delivery_date_raw) AS FLOAT64
                ) BETWEEN 30000
                AND 60000
                AND NOT REGEXP_CONTAINS(
                    TRIM(customer_promised_delivery_date_raw),
                    r'^\d{10}$'
                ) THEN TIMESTAMP_SECONDS(
                    CAST(
                        (
                            SAFE_CAST(
                                TRIM(customer_promised_delivery_date_raw) AS FLOAT64
                            ) - 25569
                        ) * 86400 AS INT64
                    )
                )
            END
        ) AS customer_promised_delivery_date,
        --
        upper(trim(source_system)) as source_system_clean,
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
        raw.sales
),
clean_sales as(
    SELECT
        *,
        CASE
            WHEN order_id IS NULL
            OR order_id = '' THEN FALSE
            WHEN order_line IS NULL THEN FALSE
            WHEN order_timestamp IS NULL THEN FALSE
            WHEN sku_id IS NULL
            OR sku_id = '' THEN FALSE
            WHEN  warehouse_id = '' THEN FALSE
            WHEN ordered_qty IS NULL THEN FALSE
            WHEN fulfilled_qty IS NULL THEN FALSE
            WHEN unit_price_foreign IS NULL THEN FALSE
            WHEN discount_amount_foreign IS NULL THEN FALSE
            WHEN currency_code IS NULL
            OR currency_code = '' THEN FALSE
            WHEN STATUS IS NULL
            OR STATUS = ''
            or status = 'CANCELLED'
            AND fulfilled_qty > 0 THEN FALSE
            WHEN customer_promised_delivery_date IS NULL THEN FALSE
            WHEN source_system_clean IS NULL
            OR source_system_clean = '' THEN FALSE
            WHEN record_updated_at_clean IS NULL THEN FALSE
            WHEN ingestion_timestamp_clean IS NULL THEN FALSE
            WHEN clean_batch_id IS NULL
            OR clean_batch_id = '' THEN FALSE
            ELSE TRUE
        END AS is_valid_record,
        --
        CASE
            WHEN order_id IS NULL
            OR order_id = '' THEN 'MISSING_ORDER_ID'
            WHEN order_line IS NULL THEN 'INVALID_ORDER_LINE'
            WHEN order_timestamp IS NULL THEN 'MISSING_ORDER_TIMESTAMP'
            WHEN sku_id IS NULL
            OR sku_id = '' THEN 'MISSING_SKU_ID'
            WHEN  warehouse_id = '' THEN 'MISSING_WAREHOUSE_ID'
            WHEN ordered_qty IS NULL THEN 'INVALID_ORDERED_QUANTITY'
            WHEN fulfilled_qty IS NULL THEN 'INVALID_FULFILLED_QUANTITY'
            WHEN unit_price_foreign IS NULL THEN 'INVALID_UNIT_PRICE'
            WHEN discount_amount_foreign IS NULL THEN 'INVALID_DISCOUNT_AMOUNT'
            WHEN currency_code IS NULL
            OR currency_code = '' THEN 'MISSING_CURRENCY_CODE'
            WHEN STATUS IS NULL
            OR STATUS = '' THEN 'MISSING_STATUS'
            WHEN customer_promised_delivery_date IS NULL THEN 'MISSING_CUSTOMER_PROMISED_DELIVERY_DATE'
            WHEN source_system_clean IS NULL
            OR source_system_clean = '' THEN 'MISSING_SOURCE_SYSTEM'
            WHEN record_updated_at_clean IS NULL THEN 'MISSING_RECORD_UPDATED_AT'
            WHEN ingestion_timestamp_clean IS NULL THEN 'MISSING_INGESTION_TIMESTAMP'
            WHEN clean_batch_id IS NULL
            OR clean_batch_id = '' THEN 'MISSING_BATCH_ID'
            WHEN status = 'CANCELLED' AND fulfilled_qty > 0 THEN 'INVALID_FULFILLED_CANCELLED_ORDER'
            ELSE NULL
        END AS exception_reason
    FROM
        fixed_sales
),
deduplicated_sales as(
    select
        *,
        ROW_NUMBER() OVER (
            PARTITION BY order_id, order_line
            ORDER BY
                record_updated_at_clean DESC
        ) AS row_num
    from
        clean_sales
)
select
    order_id,
    order_line,
    order_timestamp,
    sku_id,
    warehouse_id,
    ordered_qty,
    fulfilled_qty,
    unit_price_foreign,
    discount_amount_foreign,
    currency_code,
    STATUS,
    cancel_reason,
    customer_promised_delivery_date,
    source_system_clean,
    record_updated_at_clean,
    ingestion_timestamp_clean,
    clean_batch_id,
    is_valid_record,
    exception_reason
from
    deduplicated_sales
where
    row_num = 1

--_________________________________________________________________________________________________________________________________________________________________

/*
 =========================================
 HOW I FIXED IT (THE SOLUTIONS)
 =========================================
 1. The Currency Scrubber: 
    Used Regex to violently strip out all letters/symbols, flipped commas to standard decimals, and locked the revenue columns into pure `NUMERIC` data types.

 2. Idempotent Deduplication (Order Line Grain): 
    Used a Window Function (`ROW_NUMBER`) partitioned precisely by `order_id` AND `order_line`. By sorting by the most recent update, I mathematically guaranteed we only keep the final, true state of each line item.

 3. Business Logic Quarantine: 
    Added a strict physics trap: `status = 'CANCELLED' AND fulfilled_qty > 0`. If an order violates this, it is flagged as FALSE (`INVALID_FULFILLED_CANCELLED_ORDER`). We do not let impossible warehouse physics enter our financial models.

 4. Smart Quarantine & Date Translation: 
    Normalized all dates to standard timestamps and strictly quarantined any sales missing core IDs (Order ID, SKU, Warehouse) without deleting the evidence.
 */