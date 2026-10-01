-- Rollback for 018: restores refresh_all_mvs() as one transaction (as after 016/017).

CREATE OR REPLACE PROCEDURE shinde_shoes.refresh_all_mvs()
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_run_id bigint;   -- shinde_shoes.proc_run_log
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
    v_run_id := shinde_shoes.fn_proc_run_start('refresh_all_mvs', NULL, NULL);
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
    PERFORM shinde_shoes.fn_proc_run_end(v_run_id, jsonb_build_object('views', cardinality(v_done)));
END;
$procedure$

;
