-- 003_concurrent_mv_refresh.sql
-- Lets refresh_all_mvs() refresh the 13 shinde_shoes materialized views CONCURRENTLY,
-- so dashboards can keep reading them while an upload refreshes them.
--
--   1. A unique index on every view (REFRESH ... CONCURRENTLY requires one).
--      Each key comes from the view's own GROUP BY / bill key, so the SQL guarantees it.
--   2. log_refresh.mv_durations: seconds taken per view.
--   3. refresh_all_mvs(): CONCURRENTLY when the view has a unique index (plain refresh
--      otherwise), work_mem raised for the refresh only, real timings via clock_timestamp().
--
-- Run WITHOUT a surrounding transaction (CREATE INDEX CONCURRENTLY). In psql run as-is.
-- Safe to run more than once.
-- Rollback: 003_concurrent_mv_refresh_rollback.sql

-- ── 1. Unique indexes ───────────────────────────────────────────────────────
CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS ux_mv_sales_detail_enriched
    ON shinde_shoes.mv_sales_detail_enriched ("BillNoKey", "BillLineNo");

CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS ux_mv_sales_reporting
    ON shinde_shoes.mv_sales_reporting ("BillNoKey", "BillLineNo");

CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS ux_mv_customer_bill_level_v2
    ON shinde_shoes.mv_customer_bill_level_v2 (newbillno);

CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS ux_mv_customer_summary_v2
    ON shinde_shoes.mv_customer_summary_v2 (mobileno);

CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS ux_mv_cy_py_month
    ON shinde_shoes.mv_cy_py_month_location_cat_brand_supplier_salesp_netamt_qty
       (monthno, monthname, "locationName", "CategoryName", "BrandName", "SupplierName", "SalesPersonName");

CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS ux_mv_daily_qty_netamount_full
    ON shinde_shoes.mv_daily_qty_netamount_full
       (sales_date, "locationName", "ProductCodeName", "ProdDescription", "SubCategoryName",
        "CategoryName", "BrandName", "SupplierName", "SalesPersonName", "isWeekend");

CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS ux_mv_monthly_product_sales_trend
    ON shinde_shoes.mv_monthly_product_sales_trend
       (month_start_date, location_name, brand_name, subcategory_name, category_name, product_code, prod_description);

CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS ux_mv_product_bucket_full_store
    ON shinde_shoes.mv_product_bucket_full_store
       (location_name, supplier_name, product_code, subcategory_name, category_name, brand_name);

CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS ux_mv_store_top_products_full_trend
    ON shinde_shoes.mv_store_top_products_full_trend
       (location_name, calendar_year, calendar_quarter, product_code, brand_name, category_name, subcategory_name);

CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS ux_mv_supplier_full_performance
    ON shinde_shoes.mv_supplier_full_performance (supplier_name);

CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS ux_mv_supplier_monthly_trend_full
    ON shinde_shoes.mv_supplier_monthly_trend_full (supplier_name, monthdate);

CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS ux_mv_ytd_samedayspy
    ON shinde_shoes.mv_ytd_samedayspy_month_location_cat_brand_supplier_salesp_neta
       (year_type, "locationName", "CategoryName", "BrandName", "SupplierName", "SalesPersonName");

-- mv_product_kpi_daily_agg already has ux_mv_product_kpi_daily_agg.

-- ── 2. Per-view timings in the refresh log ──────────────────────────────────
ALTER TABLE shinde_shoes.log_refresh
    ADD COLUMN IF NOT EXISTS mv_durations jsonb;

-- ── 3. The refresh procedure ────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE shinde_shoes.refresh_all_mvs()
LANGUAGE plpgsql
AS $procedure$
DECLARE
    -- Same order as before: a view built on another view comes after it
    -- (customer_summary_v2 after customer_bill_level_v2, product_kpi_daily_agg after
    -- daily_qty_netamount_full, supplier_monthly_trend_full after supplier_full_performance).
    v_views       text[] := ARRAY[
        'mv_sales_detail_enriched',
        'mv_customer_bill_level_v2',
        'mv_cy_py_month_location_cat_brand_supplier_salesp_netamt_qty',
        'mv_daily_qty_netamount_full',
        'mv_monthly_product_sales_trend',
        'mv_product_bucket_full_store',
        'mv_sales_reporting',
        'mv_store_top_products_full_trend',
        'mv_supplier_full_performance',
        'mv_ytd_samedayspy_month_location_cat_brand_supplier_salesp_neta',
        'mv_customer_summary_v2',
        'mv_product_kpi_daily_agg',
        'mv_supplier_monthly_trend_full'
    ];
    v_view        text;
    v_refresh_id  bigint;
    v_started_at  timestamp := clock_timestamp()::timestamp;
    v_view_start  timestamp;
    v_completed   timestamp;
    v_concurrent  boolean;
    v_done        text[] := ARRAY[]::text[];
    v_durations   jsonb  := '{}'::jsonb;
BEGIN
    -- More memory for the refresh's sorts and joins; lasts until this transaction ends.
    SET LOCAL work_mem = '32MB';

    INSERT INTO shinde_shoes.log_refresh (started_at, debug_mode, status)
    VALUES (v_started_at, false, 'RUNNING')
    RETURNING refresh_id INTO v_refresh_id;

    FOREACH v_view IN ARRAY v_views LOOP
        v_view_start := clock_timestamp()::timestamp;

        -- CONCURRENTLY keeps the view readable while it refreshes. It needs a populated
        -- view with a valid, non-partial unique index on plain columns.
        SELECT m.ispopulated
               AND EXISTS (
                   SELECT 1
                   FROM   pg_index x
                   WHERE  x.indrelid = format('shinde_shoes.%I', v_view)::regclass
                     AND  x.indisunique AND x.indisvalid
                     AND  x.indpred IS NULL AND x.indexprs IS NULL
               )
        INTO   v_concurrent
        FROM   pg_matviews m
        WHERE  m.schemaname = 'shinde_shoes' AND m.matviewname = v_view;

        IF v_concurrent THEN
            EXECUTE format('REFRESH MATERIALIZED VIEW CONCURRENTLY shinde_shoes.%I', v_view);
        ELSE
            EXECUTE format('REFRESH MATERIALIZED VIEW shinde_shoes.%I', v_view);
        END IF;

        v_done      := array_append(v_done, v_view);
        v_durations := v_durations || jsonb_build_object(
                           v_view,
                           round(extract(epoch FROM clock_timestamp()::timestamp - v_view_start)::numeric, 3));
    END LOOP;

    v_completed := clock_timestamp()::timestamp;

    UPDATE shinde_shoes.log_refresh
    SET    completed_at       = v_completed,
           duration           = v_completed - v_started_at,
           mv_refreshed_count = cardinality(v_done),
           mv_names           = v_done,
           mv_durations       = v_durations,
           status             = 'SUCCESS'
    WHERE  refresh_id = v_refresh_id;
END;
$procedure$;

-- Check after an upload:
-- SELECT refresh_id, started_at, duration, status, mv_durations
-- FROM shinde_shoes.log_refresh ORDER BY refresh_id DESC LIMIT 5;
