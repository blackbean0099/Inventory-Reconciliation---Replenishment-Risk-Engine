/*
 =========================================
 THE PROBLEMS I FOUND IN THE RAW DATA (raw.telemetry)
 =========================================
 1. The Black Box (JSON Payloads): 
    The Carrier API doesn't send us neat columns. It dumps the entire tracking history (Supplier Handover, Customs Hold, Delivery) into a single, nested JSON text string.
 2. Epoch Timestamps: 
    The API logs events using Unix Epoch time (seconds since 1970) instead of human-readable dates.
 3. The API Clone Army: 
    Carriers fire duplicate webhooks for the exact same event.
 */
--_________________________________________________________________________________________________________________________________________________________________

CREATE OR REPLACE VIEW `clean.clean_telemetry` AS

WITH fixed_telemetry AS (
select
    CASE
            WHEN UPPER(TRIM(tracking_id_raw)) = 'N/A' THEN NULL
            ELSE UPPER(TRIM(tracking_id_raw))
        END AS tracking_id,
    --
    CASE
            WHEN UPPER(TRIM(shipment_id_raw)) = 'N/A' THEN NULL
            ELSE UPPER(TRIM(shipment_id_raw))
        END AS shipment_id,

    ---- Top-level JSON extraction----

    UPPER(TRIM(JSON_VALUE(carrier_payload_raw, '$.status'))) AS delivery_status,
    
    ---- Nested JSON extraction----

    JSON_VALUE(event, '$.event') AS event_name,
    JSON_VALUE(event, '$.location') AS location,
    JSON_VALUE(event, '$.exception_code') AS exception_code,
    
    -- Convert the epoch time to a true timestamp --

    TIMESTAMP_SECONDS(SAFE_CAST(JSON_VALUE(event, '$.epoch_time') AS INT64)) AS event_timestamp,

    --
    CASE
            WHEN UPPER(TRIM(source_system)) = 'N/A' THEN NULL
            ELSE UPPER(TRIM(source_system))
        END AS source_system,
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
    raw.telemetry
-- Used LEFT JOIN UNNEST to safely flatten the array without losing empty payloads
    LEFT JOIN UNNEST(
    JSON_QUERY_ARRAY(carrier_payload_raw, '$.events')
) AS event
ON TRUE
),
clean_telemetry AS (
    SELECT 
        *,
        CASE
            WHEN tracking_id IS NULL THEN FALSE
            WHEN event_timestamp IS NULL THEN FALSE
            ELSE TRUE
        END AS is_valid_record,
        
        CASE
            WHEN tracking_id IS NULL THEN 'MISSING_TRACKING_ID'
            WHEN event_timestamp IS NULL THEN 'MISSING_EVENT_TIMESTAMP'
            ELSE NULL
        END AS exception_reason
    FROM fixed_telemetry
),
deduplicated_telemetry AS (
    SELECT
        *,
        ROW_NUMBER() OVER(
            PARTITION BY tracking_id, event_name 
            ORDER BY record_updated_at_clean DESC
        ) AS row_num
    FROM clean_telemetry
)
SELECT 
    tracking_id,
    shipment_id,
    delivery_status,
    event_name,
    location,
    exception_code,
    event_timestamp,
    source_system,
    record_updated_at_clean,
    ingestion_timestamp_clean,
    clean_batch_id,
    is_valid_record,
    exception_reason
FROM deduplicated_telemetry
WHERE row_num = 1;
--_________________________________________________________________________________________________________________________________________________________________
/*
 =========================================
 HOW I FIXED IT (THE SOLUTIONS)
 =========================================
 1. JSON Array Unnesting: 
    Used `LEFT JOIN UNNEST(JSON_QUERY_ARRAY())` to shatter the JSON array into individual rows, then extracted the specific scalar values (event name, location, exception code) into structured columns.
 2. Time Translation: 
    Converted the JSON epoch timestamps into native BigQuery timestamps for downstream SLA math.
 3. Milestone Deduplication: 
    Partitioned by `tracking_id` AND `event_name` to ensure we only keep the single, freshest update for any given shipping milestone.
 */