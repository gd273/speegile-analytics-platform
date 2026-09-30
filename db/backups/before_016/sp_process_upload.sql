CREATE OR REPLACE PROCEDURE shinde_shoes.sp_process_upload(IN p_load_id integer, IN p_file_type text)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_run_id bigint;   -- public.proc_run_log
    v_from_transaction_id bigint;
BEGIN
    v_run_id := public.fn_proc_run_start('shinde_shoes.sp_process_upload', p_load_id, jsonb_build_object('file_type', p_file_type));

    IF p_file_type IS NULL THEN
        RAISE EXCEPTION
            'p_file_type is required -- pass one of ''inventory'', ''purchase'', ''sales''.';
    END IF;

    SELECT COALESCE(MAX(transaction_id), 0) + 1
    INTO v_from_transaction_id
    FROM shinde_shoes.stock_transaction;

    CASE lower(p_file_type)

        WHEN 'inventory' THEN
            IF p_load_id IS NULL THEN
                RAISE EXCEPTION
                    'p_load_id is required for file_type = ''inventory''.';
            END IF;
            RAISE NOTICE 'sp_process_upload: running INVENTORY (stock count) chain for load_id %', p_load_id;
            CALL shinde_shoes.sp_check_sku_format('inventory', p_load_id);
            CALL shinde_shoes.sp_validate_stock_load(p_load_id);
            CALL shinde_shoes.sp_process_stock_load(p_load_id);

        WHEN 'purchase' THEN
            IF p_load_id IS NULL THEN
                RAISE EXCEPTION
                    'p_load_id is required for file_type = ''purchase''.';
            END IF;
            RAISE NOTICE 'sp_process_upload: running PURCHASE chain for load_id %', p_load_id;
            CALL shinde_shoes.sp_check_sku_format('purchase', p_load_id);
            CALL shinde_shoes.sp_check_purchase_duplicates(p_load_id);
            CALL shinde_shoes.sp_validate_purchase_load(p_load_id);
            CALL shinde_shoes.sp_process_purchase_load(p_load_id);

            -- Remember the bills that were loaded (rows that passed validation)
            INSERT INTO shinde_shoes.purchase_bill_register
                ("Supplier", "BillNo", "LocationName", bill_date, line_count, total_qty, load_id)
            SELECT MIN(s."Supplier"), MIN(s."BillNo"), MIN(s."LocationName"), MIN(s."BillDate"),
                   COUNT(*), SUM(s."Qty"), p_load_id
            FROM   shinde_shoes.stg_purchase_2 s
            WHERE  s.load_id = p_load_id
            GROUP  BY upper(btrim(COALESCE(s."Supplier", ''))), upper(btrim(s."BillNo")), upper(btrim(s."LocationName"));

        WHEN 'sales' THEN
            IF p_load_id IS NOT NULL THEN
                RAISE NOTICE
                    'sp_process_upload: p_load_id % was passed but is ignored for file_type = ''sales'' -- Sales is not load-scoped, sp_process_sales_stock_impact() processes every currently-unposted sale line regardless.',
                    p_load_id;
            END IF;
            RAISE NOTICE 'sp_process_upload: running SALES stock-impact chain';
            CALL shinde_shoes.sp_process_sales_stock_impact();

        ELSE
            RAISE EXCEPTION
                'Unknown p_file_type ''%'' -- must be one of ''inventory'', ''purchase'', ''sales''.',
                p_file_type;

    END CASE;

    -- Recompute stock_fact_master for every SKU + store this upload touched,
    -- so counts, purchases and sales on any date (also back-dated) add up.
    -- A stock file can move its store's stock start date, which affects every
    -- product of that store, so it rebuilds everything.
    IF lower(p_file_type) = 'inventory' THEN
        CALL shinde_shoes.sp_rebuild_stock_fact_master(NULL);
    ELSE
        CALL shinde_shoes.sp_rebuild_stock_fact_master(v_from_transaction_id);
    END IF;

    RAISE NOTICE
        'sp_process_upload: % chain completed. Check: SELECT * FROM shinde_shoes.fn_check_stock_fact_master_reconciliation();',
        upper(p_file_type);

    PERFORM public.fn_proc_run_end(v_run_id, NULL);
END;
$procedure$
;
