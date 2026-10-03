/*
 =========================================
 THE PROBLEMS (Why we build Fact tables)
 =========================================
 1. The Shape-Shifting Product Trap:
    Products change over time. If we join sales directly to the product SKU, the database multiplies the revenue because it doesn't know *which* version of the product was sold.
 
 2. Engineering Clutter:
    Business users need to sum up revenue and quantities. They do not need to see backend tracking metadata (batch IDs, ingestion timestamps), which clutters their BI tools.
 */
--_________________________________________________________________________________________________________________________________________________________________
CREATE OR REPLACE TABLE `mart.fact_sales` AS

select
    product.product_sk,
    sales.order_id,
    sales.order_line,
    sales.warehouse_id,
    sales.order_timestamp,
    sales.ordered_qty,
    sales.fulfilled_qty,
    sales.unit_price_foreign,
    sales.discount_amount_foreign,
    sales.currency_code,
    sales.status,
    sales.cancel_reason,
    sales.customer_promised_delivery_date
FROM
    clean.clean_sales as sales
    LEFT JOIN
     mart.dim_product as product 
     on sales.sku_id = product.sku_id
    and sales.order_timestamp >= product.effective_from
    AND (sales.order_timestamp < product.effective_to OR product.effective_to IS NULL)
WHERE
    sales.is_valid_record = TRUE

--_________________________________________________________________________________________________________________________________________________________________
/*
 =========================================
 THE SOLUTIONS (How we built this Fact)
 =========================================
 1. Point-in-Time Resolution (Time Travel Join):
    Used a temporal `LEFT JOIN` against `dim_product`. By checking that the `order_timestamp` happened strictly between the product's `effective_from` and `effective_to` dates, we grab the exact Surrogate Key (`product_sk`) for what that product looked like at the exact moment of the sale.

 2. The Math Layer:
    Exposed only the Verbs (events, quantities, prices, dates). All descriptive Nouns (categories, names) are pushed out to the Dimension tables, keeping this table extremely fast and optimized for aggregation.
 */