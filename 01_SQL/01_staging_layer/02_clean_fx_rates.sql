/*
 =========================================
 THE PROBLEMS
 =========================================
 • Time-Travel Dates: Just like the fulfillments table, the dates here were a complete mess. The API sent a mix of normal dates, giant Unix computer numbers, and Excel serial numbers.
 • Messy Currency Names: The currency codes (like USD or EUR) had invisible spaces and lowercase letters. To a computer, " usd " and "USD" look like two completely different things, which ruins financial matching.
 • Fragile Exchange Rates: The actual exchange rate numbers were stored as text. If any bad data slipped in, trying to do math on it would crash the pipeline.
 • Missing Money Data: Some rows were missing their dates, currency codes, or exchange rates. Deleting them hides the fact that the API feed is broken.
 • Cluttered Batch IDs: The batch names had useless system garbage stuck to the end of them.
 */

--_________________________________________________________________________________________________________________________________________________________________

CREATE OR REPLACE VIEW `clean.clean_fx_rates` AS

with fixed_fx_rates as(
    SELECT
        COALESCE(
            -- 1. YYYY-MM-DD HH:MM:SS
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%d %H:%M:%S',
                TRIM(rate_date_raw)
            ),
            -- 2. YYYY-MM-DDTHH:MM:SSZ
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%dT%H:%M:%SZ',
                TRIM(rate_date_raw)
            ),
            -- 3. YYYY-MM-DDTHH:MM:SS+05:30
            -- BigQuery can directly cast ISO timestamps with timezone
            SAFE_CAST(
                TRIM(rate_date_raw) AS TIMESTAMP
            ),
            -- With Z
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%dT%H:%M:%SZ',
                TRIM(rate_date_raw)
            ),
            -- Without timezone
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%dT%H:%M:%S',
                TRIM(rate_date_raw)
            ),
            SAFE.PARSE_TIMESTAMP('%d-%m-%Y', TRIM(rate_date_raw)),
            --dd/mm/yy
            SAFE.PARSE_TIMESTAMP('%d/%m/%Y', TRIM(rate_date_raw)),
            -- 4. YYYY-MM-DD
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%d',
                TRIM(rate_date_raw)
            ),
            -- 5. MM-DD-YYYY
            -- Only use when second part > 12
            -- Example: 01-14-2025
            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(rate_date_raw),
                    r'^\d{2}-\d{2}-\d{4}$'
                )
                AND SAFE_CAST(
                    SPLIT(TRIM(rate_date_raw), '-') [SAFE_OFFSET(1)] AS INT64
                ) > 12 THEN SAFE.PARSE_TIMESTAMP(
                    '%m-%d-%Y',
                    TRIM(rate_date_raw)
                )
            END,
            -- 6. DD-MM-YYYY
            -- Only use when first part > 12
            -- Example: 24-09-2025
            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(rate_date_raw),
                    r'^\d{2}-\d{2}-\d{4}$'
                )
                AND SAFE_CAST(
                    SPLIT(TRIM(rate_date_raw), '-') [SAFE_OFFSET(0)] AS INT64
                ) > 12 THEN SAFE.PARSE_TIMESTAMP(
                    '%d-%m-%Y',
                    TRIM(rate_date_raw)
                )
            END,
            -- 7. MM/DD/YYYY
            -- Only use when second part > 12
            -- Example: 09/24/2025
            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(rate_date_raw),
                    r'^\d{2}/\d{2}/\d{4}$'
                )
                AND SAFE_CAST(
                    SPLIT(TRIM(rate_date_raw), '/') [SAFE_OFFSET(1)] AS INT64
                ) > 12 THEN SAFE.PARSE_TIMESTAMP(
                    '%m/%d/%Y',
                    TRIM(rate_date_raw)
                )
            END,
            -- 8. DD/MM/YYYY
            -- Only use when first part > 12
            -- Example: 21/01/2025
            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(rate_date_raw),
                    r'^\d{2}/\d{2}/\d{4}$'
                )
                AND SAFE_CAST(
                    SPLIT(TRIM(rate_date_raw), '/') [SAFE_OFFSET(0)] AS INT64
                ) > 12 THEN SAFE.PARSE_TIMESTAMP(
                    '%d/%m/%Y',
                    TRIM(rate_date_raw)
                )
            END,
            -- 9. Unix timestamp - seconds
            -- Example: 1752690600
            CASE
                WHEN REGEXP_CONTAINS(
                    TRIM(rate_date_raw),
                    r'^\d{10}$'
                ) THEN TIMESTAMP_SECONDS(
                    SAFE_CAST(
                        TRIM(rate_date_raw) AS INT64
                    )
                )
            END,
            -- 10. Excel serial date
            -- Example: 45716
            CASE
                WHEN SAFE_CAST(
                    TRIM(rate_date_raw) AS FLOAT64
                ) BETWEEN 30000
                AND 60000
                AND NOT REGEXP_CONTAINS(
                    TRIM(rate_date_raw),
                    r'^\d{10}$'
                ) THEN TIMESTAMP_SECONDS(
                    CAST(
                        (
                            SAFE_CAST(
                                TRIM(rate_date_raw) AS FLOAT64
                            ) - 25569
                        ) * 86400 AS INT64
                    )
                )
            END
        ) AS rate_date_cleaned,
        --
        upper(trim(base_currency_raw)) AS base_currency,
        --
        upper(trim(target_currency_raw)) AS target_currency,
        --
        ROUND(SAFE_CAST(exchange_rate_raw AS FLOAT64), 2) AS exchange_rate,
        --
        upper(trim(source_system)) AS clean_source_system,
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
        raw.fx_rates
),
clean_fx_rates AS (
    SELECT
        rate_date_cleaned,
        base_currency,
        target_currency,
        exchange_rate,
        clean_source_system,
        clean_record_updated_at,
        clean_ingestion_timestamp,
        clean_batch_id,
        CASE
            WHEN rate_date_cleaned IS NULL THEN FALSE
            WHEN base_currency IS NULL THEN FALSE
            WHEN target_currency IS NULL THEN FALSE
            WHEN exchange_rate IS NULL THEN FALSE
            WHEN clean_source_system IS NULL THEN FALSE
            WHEN clean_record_updated_at IS NULL THEN FALSE
            WHEN clean_ingestion_timestamp IS NULL THEN FALSE
            ELSE TRUE
        END AS is_valid_record,
        CASE
            WHEN rate_date_cleaned IS NULL THEN 'INVALID_OR_MISSING_RATE_DATE'
            WHEN base_currency IS NULL
            OR base_currency = '' THEN 'MISSING_BASE_CURRENCY'
            WHEN target_currency IS NULL
            OR target_currency = '' THEN 'MISSING_TARGET_CURRENCY'
            WHEN exchange_rate IS NULL THEN 'INVALID_OR_MISSING_EXCHANGE_RATE'
            WHEN clean_source_system IS NULL
            OR clean_source_system = '' THEN 'MISSING_SOURCE_SYSTEM'
            WHEN clean_record_updated_at IS NULL THEN 'MISSING_RECORD_UPDATED_AT'
            WHEN clean_ingestion_timestamp IS NULL THEN 'MISSING_INGESTION_TIMESTAMP'
            ELSE NULL
        END AS exception_reason
    FROM
        fixed_fx_rates
)
select
    is_valid_record,
    exception_reason,
    rate_date_cleaned,
    base_currency,
    target_currency,
    exchange_rate,
    clean_source_system,
    clean_record_updated_at,
    clean_ingestion_timestamp,
    clean_batch_id
from
    clean_fx_rates

/*
 =========================================
 WHAT I FIXED (THE SOLUTIONS)
 =========================================
 • Universal Date Translator: Reused the master date parser to automatically detect and translate every weird format (Unix, Excel, ISO) into one perfect, standard timestamp.
 • The Currency Scrubber: Used TRIM and UPPER to wash away all invisible spaces and force every letter to uppercase. Now, " usd " gets perfectly cleaned into "USD" every time.
 • Safe Money Math: Safely converted the exchange rate text into real decimals (FLOAT64) and rounded them to two decimal places so they are perfectly ready for financial reports.
 • The Quarantine System: Applied the 2-step factory architecture. If an exchange rate or currency code is missing, the row isn't deleted. It gets flagged as FALSE with a specific reason (like 'MISSING_BASE_CURRENCY') so IT can investigate the broken API.
 • Snipped Batch IDs: Used a splitter tool to chop off the useless system garbage at the end of the batch IDs, keeping only the readable parts.
 */