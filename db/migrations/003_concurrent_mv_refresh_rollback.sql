-- Rollback for 003_concurrent_mv_refresh.sql
-- Run without a surrounding transaction (DROP INDEX CONCURRENTLY).

-- 1. Restore the original refresh_all_mvs() (captured from the local DB before 003)
CREATE OR REPLACE PROCEDURE shinde_shoes.refresh_all_mvs()
 LANGUAGE plpgsql
AS $procedure$

DECLARE

    -- =========================================================
    -- DEBUG SWITCH
    --
    -- FALSE = Normal / Production mode
    -- TRUE  = Debug mode / Show NOTICE messages
    -- =========================================================
    print_notice BOOLEAN := TRUE;

    -- =========================================================
    -- REFRESH LOG VARIABLES
    -- =========================================================
    v_refresh_id       BIGINT;
    v_started_at       TIMESTAMP WITHOUT TIME ZONE;
    v_completed_at     TIMESTAMP WITHOUT TIME ZONE;

    v_mv_count         INTEGER := 0;
    v_mv_names         TEXT[] := ARRAY[]::TEXT[];

BEGIN

    -- =========================================================
    -- START TIMER
    -- =========================================================

    v_started_at := CURRENT_TIMESTAMP;


    -- =========================================================
    -- CREATE LOG RECORD
    -- =========================================================

    INSERT INTO shinde_shoes.log_refresh
    (
        started_at,
        debug_mode,
        status
    )
    VALUES
    (
        v_started_at,
        print_notice,
        'RUNNING'
    )
    RETURNING refresh_id
    INTO v_refresh_id;


    -- =========================================================
    -- START NOTICE
    -- =========================================================

    IF print_notice THEN
        RAISE NOTICE '=========================================';
        RAISE NOTICE 'Starting MV Refresh Process';
        RAISE NOTICE 'Refresh ID: %', v_refresh_id;
        RAISE NOTICE 'Started At: %', v_started_at;
        RAISE NOTICE '=========================================';
    END IF;


    -- =========================================================
    -- 1
    -- mv_sales_detail_enriched
    -- BASE MV
    -- =========================================================

    IF print_notice THEN
        RAISE NOTICE '1 - Refreshing mv_sales_detail_enriched...';
    END IF;

    REFRESH MATERIALIZED VIEW
        shinde_shoes.mv_sales_detail_enriched;

    v_mv_count := v_mv_count + 1;
    v_mv_names := array_append(
        v_mv_names,
        'mv_sales_detail_enriched'
    );


    -- =========================================================
    -- 2
    -- mv_customer_bill_level_v2
    -- =========================================================

    IF print_notice THEN
        RAISE NOTICE '2 - Refreshing mv_customer_bill_level_v2...';
    END IF;

    REFRESH MATERIALIZED VIEW
        shinde_shoes.mv_customer_bill_level_v2;

    v_mv_count := v_mv_count + 1;
    v_mv_names := array_append(
        v_mv_names,
        'mv_customer_bill_level_v2'
    );


    -- =========================================================
    -- 3
    -- mv_cy_py_month_location_cat_brand_supplier_salesp_netamt_qty
    -- =========================================================

    IF print_notice THEN
        RAISE NOTICE '3 - Refreshing mv_cy_py_month_location_cat_brand_supplier_salesp_netamt_qty...';
    END IF;

    REFRESH MATERIALIZED VIEW
        shinde_shoes.mv_cy_py_month_location_cat_brand_supplier_salesp_netamt_qty;

    v_mv_count := v_mv_count + 1;
    v_mv_names := array_append(
        v_mv_names,
        'mv_cy_py_month_location_cat_brand_supplier_salesp_netamt_qty'
    );


    -- =========================================================
    -- 4
    -- mv_daily_qty_netamount_full
    -- =========================================================

    IF print_notice THEN
        RAISE NOTICE '4 - Refreshing mv_daily_qty_netamount_full...';
    END IF;

    REFRESH MATERIALIZED VIEW
        shinde_shoes.mv_daily_qty_netamount_full;

    v_mv_count := v_mv_count + 1;
    v_mv_names := array_append(
        v_mv_names,
        'mv_daily_qty_netamount_full'
    );


    -- =========================================================
    -- 5
    -- mv_monthly_product_sales_trend
    -- =========================================================

    IF print_notice THEN
        RAISE NOTICE '5 - Refreshing mv_monthly_product_sales_trend...';
    END IF;

    REFRESH MATERIALIZED VIEW
        shinde_shoes.mv_monthly_product_sales_trend;

    v_mv_count := v_mv_count + 1;
    v_mv_names := array_append(
        v_mv_names,
        'mv_monthly_product_sales_trend'
    );


    -- =========================================================
    -- 6
    -- mv_product_bucket_full_store
    -- =========================================================

    IF print_notice THEN
        RAISE NOTICE '6 - Refreshing mv_product_bucket_full_store...';
    END IF;

    REFRESH MATERIALIZED VIEW
        shinde_shoes.mv_product_bucket_full_store;

    v_mv_count := v_mv_count + 1;
    v_mv_names := array_append(
        v_mv_names,
        'mv_product_bucket_full_store'
    );


    -- =========================================================
    -- 7
    -- mv_sales_reporting
    -- =========================================================

    IF print_notice THEN
        RAISE NOTICE '7 - Refreshing mv_sales_reporting...';
    END IF;

    REFRESH MATERIALIZED VIEW
        shinde_shoes.mv_sales_reporting;

    v_mv_count := v_mv_count + 1;
    v_mv_names := array_append(
        v_mv_names,
        'mv_sales_reporting'
    );


    -- =========================================================
    -- 8
    -- mv_store_top_products_full_trend
    -- =========================================================

    IF print_notice THEN
        RAISE NOTICE '8 - Refreshing mv_store_top_products_full_trend...';
    END IF;

    REFRESH MATERIALIZED VIEW
        shinde_shoes.mv_store_top_products_full_trend;

    v_mv_count := v_mv_count + 1;
    v_mv_names := array_append(
        v_mv_names,
        'mv_store_top_products_full_trend'
    );


    -- =========================================================
    -- 9
    -- mv_supplier_full_performance
    -- =========================================================

    IF print_notice THEN
        RAISE NOTICE '9 - Refreshing mv_supplier_full_performance...';
    END IF;

    REFRESH MATERIALIZED VIEW
        shinde_shoes.mv_supplier_full_performance;

    v_mv_count := v_mv_count + 1;
    v_mv_names := array_append(
        v_mv_names,
        'mv_supplier_full_performance'
    );


    -- =========================================================
    -- 10
    -- mv_ytd_samedayspy_month_location_cat_brand_supplier_salesp_neta
    -- =========================================================

    IF print_notice THEN
        RAISE NOTICE '10 - Refreshing mv_ytd_samedayspy_month_location_cat_brand_supplier_salesp_neta...';
    END IF;

    REFRESH MATERIALIZED VIEW
        shinde_shoes.mv_ytd_samedayspy_month_location_cat_brand_supplier_salesp_neta;

    v_mv_count := v_mv_count + 1;
    v_mv_names := array_append(
        v_mv_names,
        'mv_ytd_samedayspy_month_location_cat_brand_supplier_salesp_neta'
    );


    -- =========================================================
    -- 11
    -- mv_customer_summary_v2
    -- Depends on mv_customer_bill_level_v2
    -- =========================================================

    IF print_notice THEN
        RAISE NOTICE '11 - Refreshing mv_customer_summary_v2...';
    END IF;

    REFRESH MATERIALIZED VIEW
        shinde_shoes.mv_customer_summary_v2;

    v_mv_count := v_mv_count + 1;
    v_mv_names := array_append(
        v_mv_names,
        'mv_customer_summary_v2'
    );


    -- =========================================================
    -- 12
    -- mv_product_kpi_daily_agg
    -- Depends on mv_daily_qty_netamount_full
    -- =========================================================

    IF print_notice THEN
        RAISE NOTICE '12 - Refreshing mv_product_kpi_daily_agg...';
    END IF;

    REFRESH MATERIALIZED VIEW
        shinde_shoes.mv_product_kpi_daily_agg;

    v_mv_count := v_mv_count + 1;
    v_mv_names := array_append(
        v_mv_names,
        'mv_product_kpi_daily_agg'
    );


    -- =========================================================
    -- 13
    -- mv_supplier_monthly_trend_full
    -- Depends on mv_supplier_full_performance
    -- =========================================================

    IF print_notice THEN
        RAISE NOTICE '13 - Refreshing mv_supplier_monthly_trend_full...';
    END IF;

    REFRESH MATERIALIZED VIEW
        shinde_shoes.mv_supplier_monthly_trend_full;

    v_mv_count := v_mv_count + 1;
    v_mv_names := array_append(
        v_mv_names,
        'mv_supplier_monthly_trend_full'
    );


    -- =========================================================
    -- COMPLETED
    -- =========================================================

    v_completed_at := CURRENT_TIMESTAMP;


    UPDATE shinde_shoes.log_refresh
    SET
        completed_at = v_completed_at,
        duration = v_completed_at - started_at,
        mv_refreshed_count = v_mv_count,
        mv_names = v_mv_names,
        status = 'SUCCESS'
    WHERE refresh_id = v_refresh_id;


    -- =========================================================
    -- FINAL NOTICE
    -- =========================================================

    IF print_notice THEN
        RAISE NOTICE '=========================================';
        RAISE NOTICE 'MV Refresh Completed Successfully';
        RAISE NOTICE 'Refresh ID: %', v_refresh_id;
        RAISE NOTICE 'MVs Refreshed: %', v_mv_count;
        RAISE NOTICE 'Completed At: %', v_completed_at;
        RAISE NOTICE 'Duration: %',
            v_completed_at - v_started_at;
        RAISE NOTICE '=========================================';
    END IF;

END;
$procedure$
;

-- 2. Remove the per-view timing column
ALTER TABLE shinde_shoes.log_refresh DROP COLUMN IF EXISTS mv_durations;

-- 3. Remove the unique indexes added by 003 (ux_mv_product_kpi_daily_agg existed before and stays)
DROP INDEX CONCURRENTLY IF EXISTS shinde_shoes.ux_mv_sales_detail_enriched;
DROP INDEX CONCURRENTLY IF EXISTS shinde_shoes.ux_mv_sales_reporting;
DROP INDEX CONCURRENTLY IF EXISTS shinde_shoes.ux_mv_customer_bill_level_v2;
DROP INDEX CONCURRENTLY IF EXISTS shinde_shoes.ux_mv_customer_summary_v2;
DROP INDEX CONCURRENTLY IF EXISTS shinde_shoes.ux_mv_cy_py_month;
DROP INDEX CONCURRENTLY IF EXISTS shinde_shoes.ux_mv_daily_qty_netamount_full;
DROP INDEX CONCURRENTLY IF EXISTS shinde_shoes.ux_mv_monthly_product_sales_trend;
DROP INDEX CONCURRENTLY IF EXISTS shinde_shoes.ux_mv_product_bucket_full_store;
DROP INDEX CONCURRENTLY IF EXISTS shinde_shoes.ux_mv_store_top_products_full_trend;
DROP INDEX CONCURRENTLY IF EXISTS shinde_shoes.ux_mv_supplier_full_performance;
DROP INDEX CONCURRENTLY IF EXISTS shinde_shoes.ux_mv_supplier_monthly_trend_full;
DROP INDEX CONCURRENTLY IF EXISTS shinde_shoes.ux_mv_ytd_samedayspy;
