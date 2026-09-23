/*
 =========================================
 THE PROBLEMS
 =========================================
 • Mixed-Up Dates: The timestamps were a total mess. Some used US formats, some used European formats, some were giant computer numbers (Unix), and some were weird Excel numbers.
 • Numbers Pretending to be Text: Important numbers, like the quantity of items ordered, were saved as text. You can't do math on text, and bad text (like "N/A") would crash the system.
 • Messy IDs: Important identifiers (like Order IDs and Warehouse IDs) had invisible spaces and random uppercase/lowercase letters, which makes it impossible for the computer to match things up.
 • Missing Critical Data: Some records were missing their Order ID, timestamps, or quantities entirely. If we just deleted them, the warehouse would silently lose track of missing inventory.
 • Cluttered Batch IDs: The batch names had a bunch of useless, messy system text stuck to the end of them.
 */

--_________________________________________________________________________________________________________________________________________________________________

CREATE OR REPLACE VIEW `clean.clean_fulfillments` AS


WITH fixed_fulfillments AS (
    SELECT
        UPPER(TRIM(order_id_raw)) AS order_id,
        SAFE_CAST(order_line_raw AS INT64) AS order_line,
        COALESCE(
            SAFE_CAST(event_timestamp_raw AS TIMESTAMP),
            -- Standard date formats
            SAFE.PARSE_TIMESTAMP(
                '%m/%d/%Y',
                TRIM(event_timestamp_raw)
            ),
            SAFE.PARSE_TIMESTAMP(
                '%d/%m/%Y',
                TRIM(event_timestamp_raw)
            ),
            SAFE.PARSE_TIMESTAMP(
                '%m-%d-%Y',
                TRIM(event_timestamp_raw)
            ),
            SAFE.PARSE_TIMESTAMP(
                '%d-%m-%Y',
                TRIM(event_timestamp_raw)
            ),
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%d',
                TRIM(event_timestamp_raw)
            ),
            -- Standard timestamp formats
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%d %H:%M:%S',
                TRIM(event_timestamp_raw)
            ),
            SAFE.PARSE_TIMESTAMP(
                '%m/%d/%Y %I:%M:%S %p',
                TRIM(event_timestamp_raw)
            ),
            -- Unix timestamp in seconds
            CASE
                WHEN SAFE_CAST(TRIM(event_timestamp_raw) AS INT64) BETWEEN 1000000000
                AND 2000000000 THEN TIMESTAMP_SECONDS(
                    SAFE_CAST(TRIM(event_timestamp_raw) AS INT64)
                )
            END,
            -- Excel serial date
            CASE
                WHEN SAFE_CAST(TRIM(event_timestamp_raw) AS FLOAT64) BETWEEN 30000
                AND 60000 THEN TIMESTAMP_SECONDS(
                    CAST(
                        (
                            SAFE_CAST(TRIM(event_timestamp_raw) AS FLOAT64) - 25569
                        ) * 86400 AS INT64
                    )
                )
            END
        ) AS event_timestamp,
        UPPER(TRIM(warehouse_id_raw)) AS warehouse_id,
        UPPER(TRIM(event_type_raw)) AS event_type,
        SAFE_CAST(qty_raw AS INT64) AS qty,
        UPPER(TRIM(source_system)) AS source_system,
        COALESCE(
            SAFE_CAST(record_updated_at AS TIMESTAMP),
            -- Standard date formats
            SAFE.PARSE_TIMESTAMP(
                '%m/%d/%Y',
                TRIM(record_updated_at)
            ),
            SAFE.PARSE_TIMESTAMP(
                '%d/%m/%Y',
                TRIM(record_updated_at)
            ),
            SAFE.PARSE_TIMESTAMP(
                '%m-%d-%Y',
                TRIM(record_updated_at)
            ),
            SAFE.PARSE_TIMESTAMP(
                '%d-%m-%Y',
                TRIM(record_updated_at)
            ),
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%d',
                TRIM(record_updated_at)
            ),
            -- Standard timestamp formats
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%d %H:%M:%S',
                TRIM(record_updated_at)
            ),
            SAFE.PARSE_TIMESTAMP(
                '%m/%d/%Y %I:%M:%S %p',
                TRIM(record_updated_at)
            ),
            -- Unix timestamp in seconds
            CASE
                WHEN SAFE_CAST(TRIM(record_updated_at) AS INT64) BETWEEN 1000000000
                AND 2000000000 THEN TIMESTAMP_SECONDS(
                    SAFE_CAST(TRIM(record_updated_at) AS INT64)
                )
            END,
            -- Excel serial date
            CASE
                WHEN SAFE_CAST(TRIM(record_updated_at) AS FLOAT64) BETWEEN 30000
                AND 60000 THEN TIMESTAMP_SECONDS(
                    CAST(
                        (
                            SAFE_CAST(TRIM(record_updated_at) AS FLOAT64) - 25569
                        ) * 86400 AS INT64
                    )
                )
            END
        ) AS record_updated_at_cleaned,
        COALESCE(
            SAFE_CAST(ingestion_timestamp AS TIMESTAMP),
            -- Standard date formats
            SAFE.PARSE_TIMESTAMP(
                '%m/%d/%Y',
                TRIM(ingestion_timestamp)
            ),
            SAFE.PARSE_TIMESTAMP(
                '%d/%m/%Y',
                TRIM(ingestion_timestamp)
            ),
            SAFE.PARSE_TIMESTAMP(
                '%m-%d-%Y',
                TRIM(ingestion_timestamp)
            ),
            SAFE.PARSE_TIMESTAMP(
                '%d-%m-%Y',
                TRIM(ingestion_timestamp)
            ),
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%d',
                TRIM(ingestion_timestamp)
            ),
            -- Standard timestamp formats
            SAFE.PARSE_TIMESTAMP(
                '%Y-%m-%d %H:%M:%S',
                TRIM(ingestion_timestamp)
            ),
            SAFE.PARSE_TIMESTAMP(
                '%m/%d/%Y %I:%M:%S %p',
                TRIM(ingestion_timestamp)
            ),
            -- Unix timestamp in seconds
            CASE
                WHEN SAFE_CAST(TRIM(ingestion_timestamp) AS INT64) BETWEEN 1000000000
                AND 2000000000 THEN TIMESTAMP_SECONDS(
                    SAFE_CAST(TRIM(ingestion_timestamp) AS INT64)
                )
            END,
            -- Excel serial date
            CASE
                WHEN SAFE_CAST(TRIM(ingestion_timestamp) AS FLOAT64) BETWEEN 30000
                AND 60000 THEN TIMESTAMP_SECONDS(
                    CAST(
                        (
                            SAFE_CAST(TRIM(ingestion_timestamp) AS FLOAT64) - 25569
                        ) * 86400 AS INT64
                    )
                )
            END
        ) AS ingestion_timestamp_cleaned,
        CONCAT(
            SPLIT(batch_id, '_') [SAFE_OFFSET(0)],
            '_',
            SPLIT(batch_id, '_') [SAFE_OFFSET(1)]
        ) AS clean_batch_id
    FROM
        raw.fulfillments
),
clean_fulfillments AS (
    SELECT
        order_id,
        order_line,
        event_timestamp,
        warehouse_id,
        event_type,
        qty,
        source_system,
        record_updated_at_cleaned,
        ingestion_timestamp_cleaned,
        clean_batch_id,
        CASE
            WHEN order_id IS NULL OR order_id = '' THEN FALSE
            WHEN order_line IS NULL THEN FALSE
            WHEN qty IS NULL THEN FALSE
            WHEN event_timestamp IS NULL THEN FALSE
            WHEN record_updated_at_cleaned IS NULL THEN FALSE
            WHEN ingestion_timestamp_cleaned IS NULL THEN FALSE
            ELSE TRUE
        END AS is_valid_record,
        CASE
            WHEN order_id IS NULL OR order_id = '' THEN 'MISSING_ORDER_ID'
            WHEN order_line IS NULL THEN 'INVALID_ORDER_LINE'
            WHEN qty IS NULL THEN 'INVALID_QUANTITY'
            WHEN event_timestamp IS NULL THEN 'MISSING_EVENT_TIMESTAMP'
            WHEN record_updated_at_cleaned IS NULL THEN 'MISSING_RECORD_UPDATED_AT'
            WHEN ingestion_timestamp_cleaned IS NULL THEN 'MISSING_INGESTION_TIMESTAMP'
            ELSE NULL
        END AS exception_reason
    FROM
        fixed_fulfillments
)
SELECT
    order_id,
    order_line,
    is_valid_record,
    exception_reason,
    event_timestamp,
    warehouse_id,
    event_type,
    qty,
    source_system,
    record_updated_at_cleaned,
    ingestion_timestamp_cleaned,
    clean_batch_id
FROM
    clean_fulfillments

--_________________________________________________________________________________________________________________________________________________________________

/*
 =========================================
 WHAT I FIXED (THE SOLUTIONS)
 =========================================
 • Universal Date Translator: Built a smart parser that checks every single date format one by one (including Unix and Excel numbers) and translates them into one perfect standard time.
 • Safe Number Conversion: Safely converted text numbers into real numbers. If the text was unreadable junk, it safely turns it into a blank (Null) instead of crashing the database.
 • Scrubbed Identifiers: Used TRIM and UPPER to scrub away invisible spaces and force all letters to uppercase, making the IDs perfectly clean and matchable.
 • The Quarantine System: Instead of throwing away broken records and hiding the errors, I kept them. I created an `is_valid_record` column (to flag bad rows as FALSE) and an `exception_reason` column to explain exactly what broke (like "MISSING_ORDER_ID"). 
 • Snipped Batch IDs: Used a splitter tool to chop off the useless system garbage at the end of the batch IDs, keeping only the clean, readable parts.
 */