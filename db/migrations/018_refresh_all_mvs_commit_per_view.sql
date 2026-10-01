-- 018_refresh_all_mvs_commit_per_view.sql
-- refresh_all_mvs() refreshed all 13 dashboard views in ONE transaction: nothing was saved and no
-- lock or memory was released until the last view finished, and its log row was invisible until
-- then. On the small Render database that made the whole call hang for many minutes, while
-- refreshing the same views one by one worked.
--
-- New behaviour (same name, same call: CALL shinde_shoes.refresh_all_mvs();)
--   * Each view is refreshed and COMMITTED on its own, in the same order as before.
--   * shinde_shoes.log_refresh shows progress live: status RUNNING, mv_names = views done so far,
--     mv_durations = seconds per view. Watch it while it runs:
--       SELECT refresh_id, status, mv_refreshed_count, mv_names[array_upper(mv_names,1)] AS last_done,
--              now()::timestamp - started_at AS running_for
--       FROM shinde_shoes.log_refresh ORDER BY refresh_id DESC LIMIT 1;
--   * A view waiting more than 2 minutes for a lock fails with a clear error instead of hanging.
--   * If a view fails: the views before it stay refreshed, log_refresh says FAILED with the view
--     and error, and the error is raised to the caller.
--
-- Must be called OUTSIDE an explicit transaction (pgAdmin with Auto-commit on, psql, or the upload
-- code, which already uses an autocommit connection). Inside BEGIN ... COMMIT it fails with
-- "invalid transaction termination".
--
-- Old body: db/backups/before_018/refresh_all_mvs.sql
-- Rollback: 018_refresh_all_mvs_commit_per_view_rollback.sql

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
    v_error       text;
BEGIN
    v_run_id := shinde_shoes.fn_proc_run_start('refresh_all_mvs', NULL, NULL);

    INSERT INTO shinde_shoes.log_refresh (started_at, debug_mode, status)
    VALUES (v_started_at, false, 'RUNNING')
    RETURNING refresh_id INTO v_refresh_id;

    COMMIT;   -- the RUNNING rows are visible from now on

    FOREACH v_view IN ARRAY v_views LOOP
        -- Settings last until the next COMMIT, so they are set again for every view.
        PERFORM set_config('work_mem', '32MB', true);
        PERFORM set_config('lock_timeout', '120s', true);

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

        BEGIN
            IF v_concurrent THEN
                EXECUTE format('REFRESH MATERIALIZED VIEW CONCURRENTLY shinde_shoes.%I', v_view);
            ELSE
                EXECUTE format('REFRESH MATERIALIZED VIEW shinde_shoes.%I', v_view);
            END IF;
        EXCEPTION WHEN OTHERS THEN
            v_error := SQLERRM;
        END;

        IF v_error IS NOT NULL THEN
            UPDATE shinde_shoes.log_refresh
            SET    completed_at       = clock_timestamp()::timestamp,
                   duration           = clock_timestamp()::timestamp - v_started_at,
                   mv_refreshed_count = cardinality(v_done),
                   mv_names           = v_done,
                   mv_durations       = v_durations,
                   status             = 'FAILED',
                   error_message      = v_view || ': ' || v_error
            WHERE  refresh_id = v_refresh_id;
            COMMIT;
            RAISE EXCEPTION 'refresh_all_mvs: % failed: % (% of % views were refreshed and kept)',
                v_view, v_error, cardinality(v_done), cardinality(v_views);
        END IF;

        v_done      := array_append(v_done, v_view);
        v_durations := v_durations || jsonb_build_object(
                           v_view,
                           round(extract(epoch FROM clock_timestamp()::timestamp - v_view_start)::numeric, 3));

        UPDATE shinde_shoes.log_refresh
        SET    mv_refreshed_count = cardinality(v_done),
               mv_names           = v_done,
               mv_durations       = v_durations
        WHERE  refresh_id = v_refresh_id;

        COMMIT;   -- this view is done: its locks and memory are released
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
$procedure$;
