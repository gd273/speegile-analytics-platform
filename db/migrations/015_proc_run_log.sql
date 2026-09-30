-- 015_proc_run_log.sql
-- Tracks the heavy procedures: one row per run in public.proc_run_log with start, end,
-- duration, status, load id, parent run (which procedure called it) and a few counts.
--
-- Tracked (shinde_shoes): sp_process_upload, sp_validate_stock_load, sp_process_stock_load,
-- sp_validate_purchase_load, sp_process_purchase_load, sp_load_sales_set,
-- sp_process_sales_stock_impact, sp_rebuild_stock_fact_master, refresh_dimdate_offsets,
-- refresh_all_mvs. Each gets one line at its start and one at every exit; nothing else
-- in them changes. Old bodies: db/backups/before_015/.
--
-- How it works
--   public.fn_proc_run_start(name, load_id, details) -> run_id   (status RUNNING)
--   public.fn_proc_run_end(run_id, details)                      (status SUCCESS + duration)
--   The load id comes from the argument, else from the setting proc_run.load_id, which the
--   upload code sets at the start of each upload. The current run id is kept in the
--   setting proc_run.current_run_id, so a procedure called by another gets parent_run_id.
--
-- Log rows are written in the caller's transaction: a successful upload commits them with
-- its data. A failed upload rolls them back with everything else, so the upload code
-- (app.py, _mark_load_failed) writes one FAILED row instead, naming the procedure that
-- raised the error.
-- Rollback: 015_proc_run_log_rollback.sql

BEGIN;

CREATE TABLE public.proc_run_log (
    run_id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    parent_run_id  bigint,
    schema_name    text          NOT NULL,
    proc_name      text          NOT NULL,
    load_id        integer,
    status         varchar(10)   NOT NULL DEFAULT 'RUNNING',   -- RUNNING / SUCCESS / FAILED
    started_at     timestamp     NOT NULL DEFAULT clock_timestamp(),
    finished_at    timestamp,
    duration_sec   numeric(12,3),
    details        jsonb,
    error_message  text,
    backend_pid    integer       DEFAULT pg_backend_pid()
);
CREATE INDEX ix_proc_run_log_started ON public.proc_run_log (started_at DESC);
CREATE INDEX ix_proc_run_log_load_id ON public.proc_run_log (load_id);
CREATE INDEX ix_proc_run_log_proc    ON public.proc_run_log (schema_name, proc_name);
CREATE INDEX ix_proc_run_log_parent  ON public.proc_run_log (parent_run_id);

CREATE OR REPLACE FUNCTION public.fn_proc_run_start(p_proc_name text, p_load_id integer DEFAULT NULL,
                                                    p_details jsonb DEFAULT NULL)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_run_id bigint;
BEGIN
    INSERT INTO public.proc_run_log (parent_run_id, schema_name, proc_name, load_id, details)
    VALUES (
        NULLIF(current_setting('proc_run.current_run_id', true), '')::bigint,
        CASE WHEN position('.' IN p_proc_name) > 0 THEN split_part(p_proc_name, '.', 1) ELSE 'public' END,
        CASE WHEN position('.' IN p_proc_name) > 0 THEN split_part(p_proc_name, '.', 2) ELSE p_proc_name END,
        COALESCE(p_load_id, NULLIF(current_setting('proc_run.load_id', true), '')::integer),
        p_details
    )
    RETURNING run_id INTO v_run_id;

    PERFORM set_config('proc_run.current_run_id', v_run_id::text, true);
    RETURN v_run_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_proc_run_end(p_run_id bigint, p_details jsonb DEFAULT NULL)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_parent bigint;
BEGIN
    UPDATE public.proc_run_log
    SET    status       = 'SUCCESS',
           finished_at  = clock_timestamp(),
           duration_sec = round(extract(epoch FROM clock_timestamp() - started_at)::numeric, 3),
           details      = CASE WHEN p_details IS NULL THEN details
                               ELSE COALESCE(details, '{}'::jsonb) || p_details END
    WHERE  run_id = p_run_id
    RETURNING parent_run_id INTO v_parent;

    PERFORM set_config('proc_run.current_run_id', COALESCE(v_parent::text, ''), true);
END;
$function$;

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


CREATE OR REPLACE PROCEDURE shinde_shoes.sp_validate_stock_load(IN p_load_id integer)
 LANGUAGE plpgsql
AS $procedure$

DECLARE
    v_run_id bigint;   -- public.proc_run_log
    v_total_rows   integer := 0;
    v_invalid_rows integer := 0;
    v_valid_rows   integer := 0;

BEGIN
    v_run_id := public.fn_proc_run_start('shinde_shoes.sp_validate_stock_load', p_load_id, NULL);

    -- ============================================================
    -- STEP 1: Check load
    -- ============================================================

    SELECT COUNT(*)
    INTO v_total_rows
    FROM shinde_shoes.stg_stock_1
    WHERE load_id = p_load_id;

    IF v_total_rows = 0 THEN
        RAISE EXCEPTION
            'No inventory records found for load_id %',
            p_load_id;
    END IF;


    -- ============================================================
    -- STEP 2: Validate all rows
    --
    -- One INSERT handles all validation rules.
    --
    -- Required fields:
    --     SKU (presence only -- no longer checked against DimProduct)
    --     BranchName
    --     Qty
    --
    -- Optional numeric fields:
    --     NULL / empty = 0
    --
    -- Invalid numeric values:
    --     validation error
    -- ============================================================

    INSERT INTO shinde_shoes.validation_error
    (
        load_id,
        row_no,
        file_type,
        error_code,
        error_column,
        error_value,
        error_message,
        created_by
    )

    SELECT
        i.load_id,
        i.row_no,
        'inventory',
        v.error_code,
        v.error_column,
        v.error_value,
        v.error_message,
        i.created_by

    FROM shinde_shoes.stg_stock_1 i

    CROSS JOIN LATERAL
    (
        VALUES

        -- ========================================================
        -- SKU -- presence only, DimProduct is no longer checked
        -- ========================================================

        (
            'SKU_REQUIRED',
            'SKU',
            i."SKU",
            'SKU is required.',
            NULLIF(TRIM(i."SKU"), '') IS NULL
        ),


        -- ========================================================
        -- LOCATION
        -- ========================================================

        (
            'LOCATION_REQUIRED',
            'BranchName',
            i."BranchName",
            'BranchName is required.',
            NULLIF(TRIM(i."BranchName"), '') IS NULL
        ),

        (
            'LOCATION_NOT_FOUND',
            'BranchName',
            i."BranchName",
            'BranchName does not exist in DimLocation.',
            NULLIF(TRIM(i."BranchName"), '') IS NOT NULL
            AND NOT EXISTS
            (
                SELECT 1
                FROM shinde_shoes."DimLocation" l
                WHERE TRIM(l."locationName") = TRIM(i."BranchName")
            )
        ),


        -- ========================================================
        -- QUANTITY
        -- ========================================================

        (
            'QTY_REQUIRED',
            'Qty',
            i."Qty",
            'Quantity is required.',
            NULLIF(TRIM(i."Qty"), '') IS NULL
        ),

        (
            'INVALID_QTY',
            'Qty',
            i."Qty",
            'Quantity must be numeric and cannot be negative.',
            NULLIF(TRIM(i."Qty"), '') IS NOT NULL
            AND
            (
                TRIM(i."Qty")
                    !~ '^[+-]?([0-9]+(\.[0-9]+)?|\.[0-9]+)$'
                OR TRIM(i."Qty")::numeric < 0
            )
        ),


        -- ========================================================
        -- MRP
        -- NULL / empty = 0
        -- ========================================================

        (
            'INVALID_MRP',
            'MRP',
            i."MRP",
            'MRP must be numeric and cannot be negative.',
            NULLIF(TRIM(i."MRP"), '') IS NOT NULL
            AND
            (
                TRIM(i."MRP")
                    !~ '^[+-]?([0-9]+(\.[0-9]+)?|\.[0-9]+)$'
                OR TRIM(i."MRP")::numeric < 0
            )
        ),


        -- ========================================================
        -- SELL PRICE
        -- NULL / empty = 0
        -- ========================================================

        (
            'INVALID_SELLPRICE',
            'SellPrice',
            i."SellPrice",
            'SellPrice must be numeric and cannot be negative.',
            NULLIF(TRIM(i."SellPrice"), '') IS NOT NULL
            AND
            (
                TRIM(i."SellPrice")
                    !~ '^[+-]?([0-9]+(\.[0-9]+)?|\.[0-9]+)$'
                OR TRIM(i."SellPrice")::numeric < 0
            )
        ),


        -- ========================================================
        -- COST
        -- NULL / empty = 0
        -- ========================================================

        (
            'INVALID_COST',
            'Cost',
            i."Cost",
            'Cost must be numeric and cannot be negative.',
            NULLIF(TRIM(i."Cost"), '') IS NOT NULL
            AND
            (
                TRIM(i."Cost")
                    !~ '^[+-]?([0-9]+(\.[0-9]+)?|\.[0-9]+)$'
                OR TRIM(i."Cost")::numeric < 0
            )
        ),


        -- ========================================================
        -- COST AMOUNT
        -- NULL / empty = 0
        -- ========================================================

        (
            'INVALID_COST_AMOUNT',
            'CostAmount',
            i."CostAmount",
            'CostAmount must be numeric and cannot be negative.',
            NULLIF(TRIM(i."CostAmount"), '') IS NOT NULL
            AND
            (
                TRIM(i."CostAmount")
                    !~ '^[+-]?([0-9]+(\.[0-9]+)?|\.[0-9]+)$'
                OR TRIM(i."CostAmount")::numeric < 0
            )
        ),


        -- ========================================================
        -- BASE COST
        -- NULL / empty = 0
        -- ========================================================

        (
            'INVALID_BASE_COST',
            'BaseCost',
            i."BaseCost",
            'BaseCost must be numeric and cannot be negative.',
            NULLIF(TRIM(i."BaseCost"), '') IS NOT NULL
            AND
            (
                TRIM(i."BaseCost")
                    !~ '^[+-]?([0-9]+(\.[0-9]+)?|\.[0-9]+)$'
                OR TRIM(i."BaseCost")::numeric < 0
            )
        ),


        -- ========================================================
        -- BASE COST AMOUNT
        -- NULL / empty = 0
        -- ========================================================

        (
            'INVALID_BASE_COST_AMOUNT',
            'BaseCostAmount',
            i."BaseCostAmount",
            'BaseCostAmount must be numeric and cannot be negative.',
            NULLIF(TRIM(i."BaseCostAmount"), '') IS NOT NULL
            AND
            (
                TRIM(i."BaseCostAmount")
                    !~ '^[+-]?([0-9]+(\.[0-9]+)?|\.[0-9]+)$'
                OR TRIM(i."BaseCostAmount")::numeric < 0
            )
        ),


        -- ========================================================
        -- SALESMAN POINTS
        -- NULL / empty = 0
        -- ========================================================

        (
            'INVALID_SALESMAN_POINTS',
            'SalesManPoints',
            i."SalesManPoints",
            'SalesManPoints must be numeric.',
            NULLIF(TRIM(i."SalesManPoints"), '') IS NOT NULL
            AND
            TRIM(i."SalesManPoints")
                !~ '^[+-]?([0-9]+(\.[0-9]+)?|\.[0-9]+)$'
        ),


        -- ========================================================
        -- PERIOD DAYS
        -- NULL / empty = 0
        -- Must be a whole number >= 0
        -- ========================================================

        (
            'INVALID_PERIOD_DAYS',
            'PeriodDays',
            i."PeriodDays",
            'PeriodDays must be a whole number and cannot be negative.',
            NULLIF(TRIM(i."PeriodDays"), '') IS NOT NULL
            AND
            (
                TRIM(i."PeriodDays") !~ '^\d+$'
                OR TRIM(i."PeriodDays")::integer < 0
            )
        ),


        -- ========================================================
        -- STOCK DAYS
        -- NULL / empty = 0
        -- Must be a whole number >= 0
        -- ========================================================

        (
            'INVALID_STOCK_DAYS',
            'StockDays',
            i."StockDays",
            'StockDays must be a whole number and cannot be negative.',
            NULLIF(TRIM(i."StockDays"), '') IS NOT NULL
            AND
            (
                TRIM(i."StockDays") !~ '^\d+$'
                OR TRIM(i."StockDays")::integer < 0
            )
        ),


        -- ========================================================
        -- EXPIRY DAYS
        -- NULL / empty = 0
        -- Must be a whole number >= 0
        -- ========================================================

        (
            'INVALID_EXPIRY_DAYS',
            'ExpiryDays',
            i."ExpiryDays",
            'ExpiryDays must be a whole number and cannot be negative.',
            NULLIF(TRIM(i."ExpiryDays"), '') IS NOT NULL
            AND
            (
                TRIM(i."ExpiryDays") !~ '^\d+$'
                OR TRIM(i."ExpiryDays")::integer < 0
            )
        )

        -- BillDate and Expiry are not checked: stock files use the upload date,
        -- so an odd date in the file must not block a product's stock update.

    ) AS v
    (
        error_code,
        error_column,
        error_value,
        error_message,
        is_error
    )

    WHERE i.load_id = p_load_id
      AND v.is_error = true;


    -- ============================================================
    -- STEP 3: Count invalid rows
    -- ============================================================

    SELECT COUNT(DISTINCT i.row_no)
    INTO v_invalid_rows
    FROM shinde_shoes.stg_stock_1 i
    WHERE i.load_id = p_load_id
      AND EXISTS
      (
          SELECT 1
          FROM shinde_shoes.validation_error e
          WHERE e.load_id = i.load_id
            AND e.row_no = i.row_no
            AND e.file_type = 'inventory'
      );


    v_valid_rows := v_total_rows - v_invalid_rows;


    -- ============================================================
    -- STEP 4: Insert VALID rows into backup_stg_stock_2
    --
    -- Optional numeric NULL/empty values become 0.
    -- ============================================================

    INSERT INTO shinde_shoes.backup_stg_stock_2
    (
        row_no,
        load_id,
        "SKU",
        "Source",
        "AlternateCode",
        "Expiry",
        "SalesManPoints",
        "CostChar",
        "ProductGroup",
        "CollectionName",
        "FitName",
        "WashName",
        "MRP",
        "SellPrice",
        "PurchaseNo",
        "BillNo",
        "BillDate",
        "PeriodDays",
        "StockDays",
        "ExpiryDays",
        "Qty",
        "Product",
        "ProductDesc",
        "Composite",
        "ColorCode",
        "ColorDesc",
        "SizeCode",
        "SizeDesc",
        "Size",
        "OptionalCategory",
        "Category",
        "CategoryDesc",
        "Subcategory",
        "SubcategoryDesc",
        "Supplier",
        "Brand",
        "Unit",
        "Cost",
        "CostAmount",
        "BaseCost",
        "BaseCostAmount",
        "StockType",
        "HSN",
        "BranchName",
        "created_at",
        "created_by"
    )

    SELECT
        i.row_no,
        i.load_id,
        i."SKU",
        i."Source",
        i."AlternateCode",

        CASE
            WHEN NULLIF(TRIM(i."Expiry"), '') IS NULL
            THEN NULL
            ELSE shinde_shoes.fn_try_parse_stock_date(i."Expiry")
        END,

        COALESCE(
            NULLIF(TRIM(i."SalesManPoints"), '')::numeric,
            0
        ),

        i."CostChar",
        i."ProductGroup",
        i."CollectionName",
        i."FitName",
        i."WashName",

        COALESCE(
            NULLIF(TRIM(i."MRP"), '')::numeric,
            0
        ),

        COALESCE(
            NULLIF(TRIM(i."SellPrice"), '')::numeric,
            0
        ),

        i."PurchaseNo",
        i."BillNo",

        CASE
            WHEN NULLIF(TRIM(i."BillDate"), '') IS NULL
            THEN NULL
            ELSE shinde_shoes.fn_try_parse_stock_date(i."BillDate")
        END,

        COALESCE(
            NULLIF(TRIM(i."PeriodDays"), '')::integer,
            0
        ),

        COALESCE(
            NULLIF(TRIM(i."StockDays"), '')::integer,
            0
        ),

        COALESCE(
            NULLIF(TRIM(i."ExpiryDays"), '')::integer,
            0
        ),

        TRIM(i."Qty")::numeric,

        i."Product",
        i."ProductDesc",
        i."Composite",
        i."ColorCode",
        i."ColorDesc",
        i."SizeCode",
        i."SizeDesc",
        i."Size",
        i."OptionalCategory",
        i."Category",
        i."CategoryDesc",
        i."Subcategory",
        i."SubcategoryDesc",
        i."Supplier",
        i."Brand",
        i."Unit",

        COALESCE(
            NULLIF(TRIM(i."Cost"), '')::numeric,
            0
        ),

        COALESCE(
            NULLIF(TRIM(i."CostAmount"), '')::numeric,
            0
        ),

        COALESCE(
            NULLIF(TRIM(i."BaseCost"), '')::numeric,
            0
        ),

        COALESCE(
            NULLIF(TRIM(i."BaseCostAmount"), '')::numeric,
            0
        ),

        i."StockType",
        i."HSN",
        i."BranchName",
        i.created_at,
        i.created_by

    FROM shinde_shoes.stg_stock_1 i

    WHERE i.load_id = p_load_id
      AND NOT EXISTS
      (
          SELECT 1
          FROM shinde_shoes.validation_error e
          WHERE e.load_id = i.load_id
            AND e.row_no = i.row_no
            AND e.file_type = 'inventory'
      );


    -- ============================================================
    -- STEP 5: Insert VALID rows into stg_stock_2
    -- ============================================================

    INSERT INTO shinde_shoes.stg_stock_2
    (
        row_no,
        load_id,
        "SKU",
        "Source",
        "AlternateCode",
        "Expiry",
        "SalesManPoints",
        "CostChar",
        "ProductGroup",
        "CollectionName",
        "FitName",
        "WashName",
        "MRP",
        "SellPrice",
        "PurchaseNo",
        "BillNo",
        "BillDate",
        "PeriodDays",
        "StockDays",
        "ExpiryDays",
        "Qty",
        "Product",
        "ProductDesc",
        "Composite",
        "ColorCode",
        "ColorDesc",
        "SizeCode",
        "SizeDesc",
        "Size",
        "OptionalCategory",
        "Category",
        "CategoryDesc",
        "Subcategory",
        "SubcategoryDesc",
        "Supplier",
        "Brand",
        "Unit",
        "Cost",
        "CostAmount",
        "BaseCost",
        "BaseCostAmount",
        "StockType",
        "HSN",
        "BranchName",
        "created_at",
        "created_by"
    )

    SELECT
        i.row_no,
        i.load_id,
        i."SKU",
        i."Source",
        i."AlternateCode",

        CASE
            WHEN NULLIF(TRIM(i."Expiry"), '') IS NULL
            THEN NULL
            ELSE shinde_shoes.fn_try_parse_stock_date(i."Expiry")
        END,

        COALESCE(
            NULLIF(TRIM(i."SalesManPoints"), '')::numeric,
            0
        ),

        i."CostChar",
        i."ProductGroup",
        i."CollectionName",
        i."FitName",
        i."WashName",

        COALESCE(
            NULLIF(TRIM(i."MRP"), '')::numeric,
            0
        ),

        COALESCE(
            NULLIF(TRIM(i."SellPrice"), '')::numeric,
            0
        ),

        i."PurchaseNo",
        i."BillNo",

        CASE
            WHEN NULLIF(TRIM(i."BillDate"), '') IS NULL
            THEN NULL
            ELSE shinde_shoes.fn_try_parse_stock_date(i."BillDate")
        END,

        COALESCE(
            NULLIF(TRIM(i."PeriodDays"), '')::integer,
            0
        ),

        COALESCE(
            NULLIF(TRIM(i."StockDays"), '')::integer,
            0
        ),

        COALESCE(
            NULLIF(TRIM(i."ExpiryDays"), '')::integer,
            0
        ),

        TRIM(i."Qty")::numeric,

        i."Product",
        i."ProductDesc",
        i."Composite",
        i."ColorCode",
        i."ColorDesc",
        i."SizeCode",
        i."SizeDesc",
        i."Size",
        i."OptionalCategory",
        i."Category",
        i."CategoryDesc",
        i."Subcategory",
        i."SubcategoryDesc",
        i."Supplier",
        i."Brand",
        i."Unit",

        COALESCE(
            NULLIF(TRIM(i."Cost"), '')::numeric,
            0
        ),

        COALESCE(
            NULLIF(TRIM(i."CostAmount"), '')::numeric,
            0
        ),

        COALESCE(
            NULLIF(TRIM(i."BaseCost"), '')::numeric,
            0
        ),

        COALESCE(
            NULLIF(TRIM(i."BaseCostAmount"), '')::numeric,
            0
        ),

        i."StockType",
        i."HSN",
        i."BranchName",
        i.created_at,
        i.created_by

    FROM shinde_shoes.stg_stock_1 i

    WHERE i.load_id = p_load_id
      AND NOT EXISTS
      (
          SELECT 1
          FROM shinde_shoes.validation_error e
          WHERE e.load_id = i.load_id
            AND e.row_no = i.row_no
            AND e.file_type = 'inventory'
      );


    -- ============================================================
    -- STEP 6: Final summary
    -- ============================================================

    RAISE NOTICE
        'stock validation completed. Load ID: %, Total: %, Valid: %, Invalid: %',
        p_load_id,
        v_total_rows,
        v_valid_rows,
        v_invalid_rows;

    PERFORM public.fn_proc_run_end(v_run_id, jsonb_build_object('total_rows', v_total_rows, 'valid_rows', v_valid_rows, 'invalid_rows', v_invalid_rows));
END;
$procedure$
;


CREATE OR REPLACE PROCEDURE shinde_shoes.sp_process_stock_load(IN p_load_id integer)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_run_id bigint;   -- public.proc_run_log
    v_total_rows       integer := 0;
    v_stock_date       date;
    v_filename         text;
    v_upload_date      date;
    v_name_date        text[];
    v_new_skus_created integer := 0;
    v_unresolvable     integer := 0;
    v_counted          integer := 0;
    v_replaced         integer := 0;
BEGIN
    v_run_id := public.fn_proc_run_start('shinde_shoes.sp_process_stock_load', p_load_id, NULL);
    SELECT COUNT(*) INTO v_total_rows
    FROM shinde_shoes.stg_stock_2
    WHERE load_id = p_load_id;

    IF v_total_rows = 0 THEN
        RAISE EXCEPTION 'No validated stock records found for load_id % in stg_stock_2', p_load_id;
    END IF;

    -- ------------------------------------------------------------------
    -- 1. Stock date = the date in the file name, DD_MM_YYYY (the day the
    --    stock was counted; closing stock of that day), e.g.
    --    shindeshoes_inventory_14_09_2026.xlsx. The dates inside stock files
    --    are not reliable. No date in the name -> the upload date.
    -- ------------------------------------------------------------------
    SELECT filename, started_at::date
    INTO v_filename, v_upload_date
    FROM public.load_master
    WHERE id = p_load_id;

    v_upload_date := COALESCE(v_upload_date, CURRENT_DATE);

    SELECT r.m INTO v_name_date
    FROM regexp_matches(COALESCE(v_filename, ''), '(\d{1,2})[-_.](\d{1,2})[-_.](\d{4})', 'g')
         WITH ORDINALITY AS r(m, n)
    ORDER BY r.n DESC
    LIMIT 1;

    IF v_name_date IS NULL THEN
        v_stock_date := v_upload_date;
    ELSE
        BEGIN
            v_stock_date := make_date(v_name_date[3]::int, v_name_date[2]::int, v_name_date[1]::int);
        EXCEPTION WHEN others THEN
            RAISE EXCEPTION
                'Stock file name "%" has an invalid date (%-%-%). Name it like shindeshoes_inventory_14_09_2026.xlsx, with the day the stock was counted as DD_MM_YYYY.',
                v_filename, v_name_date[1], v_name_date[2], v_name_date[3];
        END;
        IF v_stock_date > v_upload_date THEN
            RAISE EXCEPTION
                'Stock file name "%" has the date %, which is after today (%). Use the day the stock was counted, as DD_MM_YYYY.',
                v_filename, to_char(v_stock_date, 'DD-MM-YYYY'), to_char(v_upload_date, 'DD-MM-YYYY');
        END IF;
    END IF;

    -- ------------------------------------------------------------------
    -- 2. Resolve each row's store and product attributes
    -- ------------------------------------------------------------------
    DROP TABLE IF EXISTS _stock_attrs;
    CREATE TEMP TABLE _stock_attrs ON COMMIT DROP AS
    SELECT
        i.row_no,
        i.created_by,
        TRIM(i."SKU")              AS "SKU",
        loc."LocationKey",
        brand_lookup."BrandKey",
        productcode_lookup."ProductCodeKey",
        color_lookup."ColorKey",
        size_lookup."SizeKey",
        supplier_lookup."SupplierKey",
        COALESCE(i."Qty", 0)       AS "Qty",
        i."ProductDesc",
        i."CategoryDesc",
        COALESCE(i."MRP", 0)       AS "MRP",
        COALESCE(i."SellPrice", 0) AS "SaleRate"
    FROM shinde_shoes.stg_stock_2 i
    CROSS JOIN LATERAL (
        SELECT NULLIF(shinde_shoes."Fn_Validate_Location"(TRIM(i."BranchName"), i."SKU", NULL::integer), 0) AS "LocationKey"
    ) loc
    CROSS JOIN LATERAL (
        SELECT NULLIF(shinde_shoes."Fn_Validate_Brand"(TRIM(i."Brand"), i."SKU"), 0) AS "BrandKey"
    ) brand_lookup
    CROSS JOIN LATERAL (
        SELECT NULLIF(shinde_shoes."Fn_Validate_Category"(TRIM(i."CategoryDesc"), TRIM(i."Category"), i."SKU"), 0) AS "CategoryKey"
    ) category_lookup
    CROSS JOIN LATERAL (
        SELECT NULLIF(shinde_shoes."Fn_Validate_SubCategory"(
            category_lookup."CategoryKey", TRIM(i."Subcategory"), TRIM(i."SubcategoryDesc"), i."SKU"), 0) AS "SubCategoryKey"
    ) subcategory_lookup
    CROSS JOIN LATERAL (
        SELECT NULLIF(shinde_shoes."Fn_Validate_ProductCode"(
            subcategory_lookup."SubCategoryKey", TRIM(i."Product"), TRIM(i."ProductDesc"), i."SKU"), 0) AS "ProductCodeKey"
    ) productcode_lookup
    CROSS JOIN LATERAL (
        SELECT NULLIF(shinde_shoes."Fn_Validate_Color"(TRIM(i."ColorDesc"), TRIM(i."ColorCode"), i."SKU"), 0) AS "ColorKey"
    ) color_lookup
    CROSS JOIN LATERAL (
        SELECT NULLIF(shinde_shoes."Fn_Validate_Size"(TRIM(i."SizeDesc"), TRIM(i."Size"), i."SKU"), 0) AS "SizeKey"
    ) size_lookup
    CROSS JOIN LATERAL (
        SELECT NULLIF(shinde_shoes."Fn_Validate_Supplier"(TRIM(i."Supplier"), i."SKU"), 0) AS "SupplierKey"
    ) supplier_lookup
    WHERE i.load_id = p_load_id;

    -- New SKUs go into DimProduct when all their attributes were found.
    INSERT INTO shinde_shoes."DimProduct"
    (
        "BrandKey", "ProductCodeKey", "ColorKey", "SizeKey", "SupplierKey",
        "SKU", "ProductDesc", "CategoryDesc", "MRP", "SaleRate"
    )
    SELECT DISTINCT ON (a."SKU")
        a."BrandKey", a."ProductCodeKey", a."ColorKey", a."SizeKey", a."SupplierKey",
        a."SKU", a."ProductDesc", a."CategoryDesc", a."MRP", a."SaleRate"
    FROM _stock_attrs a
    WHERE NOT EXISTS (SELECT 1 FROM shinde_shoes."DimProduct" dp WHERE dp."SKU" = a."SKU")
      AND a."BrandKey" IS NOT NULL
      AND a."ProductCodeKey" IS NOT NULL
      AND a."ColorKey" IS NOT NULL
      AND a."SizeKey" IS NOT NULL
      AND a."SupplierKey" IS NOT NULL
    ORDER BY a."SKU", a.row_no DESC
    ON CONFLICT ("SKU") DO NOTHING;

    GET DIAGNOSTICS v_new_skus_created = ROW_COUNT;

    SELECT COUNT(*) INTO v_unresolvable
    FROM _stock_attrs a
    WHERE a."LocationKey" IS NULL
       OR NOT EXISTS (SELECT 1 FROM shinde_shoes."DimProduct" dp WHERE dp."SKU" = a."SKU");

    -- ------------------------------------------------------------------
    -- 3. Counted qty per SKU + store (a SKU listed twice is added up)
    -- ------------------------------------------------------------------
    DROP TABLE IF EXISTS _stock_count;
    CREATE TEMP TABLE _stock_count ON COMMIT DROP AS
    SELECT
        dp."SKUKey",
        a."LocationKey",
        SUM(a."Qty")      AS counted_qty,
        MAX(a.row_no)     AS row_no,
        MAX(a.created_by) AS created_by
    FROM _stock_attrs a
    JOIN shinde_shoes."DimProduct" dp ON dp."SKU" = a."SKU"
    WHERE a."LocationKey" IS NOT NULL
    GROUP BY dp."SKUKey", a."LocationKey";

    SELECT COUNT(*) INTO v_counted FROM _stock_count;

    IF v_counted = 0 THEN
        RAISE EXCEPTION 'Stock file for load_id % has no rows with a known store and SKU.', p_load_id;
    END IF;

    -- ------------------------------------------------------------------
    -- 4. A product counted again on the same stock date: the new count
    --    replaces the old one. Products not in this file are not touched.
    -- ------------------------------------------------------------------
    DROP TABLE IF EXISTS _replaced_counts;
    CREATE TEMP TABLE _replaced_counts ON COMMIT DROP AS
    SELECT t.transaction_id, t."SKUKey", t."LocationKey"
    FROM shinde_shoes.stock_transaction t
    JOIN _stock_count c ON c."SKUKey" = t."SKUKey" AND c."LocationKey" = t."LocationKey"
    WHERE t.movement_type = 'OPENING'
      AND t.transaction_date = v_stock_date;

    SELECT COUNT(DISTINCT ("SKUKey", "LocationKey")) INTO v_replaced FROM _replaced_counts;

    UPDATE shinde_shoes.stock_fact_master
    SET    last_transaction_id = NULL
    WHERE  last_transaction_id IN (SELECT transaction_id FROM _replaced_counts);

    DELETE FROM shinde_shoes.stock_transaction
    WHERE transaction_id IN (SELECT transaction_id FROM _replaced_counts);

    -- ------------------------------------------------------------------
    -- 5. Stock the system expected at the end of the stock date
    --    = latest earlier count + purchases - sales after it, up to that day
    --    (only movements that count for stock, see v_stock_effective_transaction)
    -- ------------------------------------------------------------------
    DROP TABLE IF EXISTS _stock_before;
    CREATE TEMP TABLE _stock_before ON COMMIT DROP AS
    WITH last_count AS (
        SELECT "SKUKey", "LocationKey", MAX(transaction_date) AS count_date
        FROM shinde_shoes.v_stock_effective_transaction
        WHERE movement_type = 'OPENING'
          AND transaction_date < v_stock_date
        GROUP BY "SKUKey", "LocationKey"
    )
    SELECT
        t."SKUKey", t."LocationKey",
        SUM(CASE WHEN t.movement_type = 'SALE' THEN -t.quantity ELSE t.quantity END) AS qty_before
    FROM shinde_shoes.v_stock_effective_transaction t
    JOIN _stock_count c ON c."SKUKey" = t."SKUKey" AND c."LocationKey" = t."LocationKey"
    LEFT JOIN last_count lc ON lc."SKUKey" = t."SKUKey" AND lc."LocationKey" = t."LocationKey"
    WHERE t.transaction_date <= v_stock_date
      AND (lc.count_date IS NULL
           OR t.transaction_date > lc.count_date
           OR (t.movement_type = 'OPENING' AND t.transaction_date = lc.count_date))
    GROUP BY t."SKUKey", t."LocationKey";

    -- ------------------------------------------------------------------
    -- 6. Post the counts and record the history
    -- ------------------------------------------------------------------
    INSERT INTO shinde_shoes.stock_transaction
    (
        "SKUKey", "LocationKey", transaction_date, movement_type,
        quantity, load_id, row_no, source_file_type, created_by
    )
    SELECT
        c."SKUKey", c."LocationKey", v_stock_date, 'OPENING',
        c.counted_qty, p_load_id, c.row_no, 'inventory', c.created_by
    FROM _stock_count c;

    INSERT INTO shinde_shoes.stock_count_history
    (
        "SKUKey", "SKU", "ProductCode", "LocationKey", stock_date,
        counted_qty, system_qty_before, qty_difference, load_id, created_by
    )
    SELECT
        c."SKUKey", dp."SKU", pc."ProductCodeName", c."LocationKey", v_stock_date,
        c.counted_qty,
        COALESCE(b.qty_before, 0),
        c.counted_qty - COALESCE(b.qty_before, 0),
        p_load_id, c.created_by
    FROM _stock_count c
    JOIN shinde_shoes."DimProduct" dp          ON dp."SKUKey" = c."SKUKey"
    LEFT JOIN shinde_shoes."DimProductCode" pc ON pc."ProductCodeKey" = dp."ProductCodeKey"
    LEFT JOIN _stock_before b                  ON b."SKUKey" = c."SKUKey" AND b."LocationKey" = c."LocationKey"
    ON CONFLICT ("SKUKey", "LocationKey", stock_date) DO UPDATE SET
        "SKU"             = EXCLUDED."SKU",
        "ProductCode"     = EXCLUDED."ProductCode",
        counted_qty       = EXCLUDED.counted_qty,
        system_qty_before = EXCLUDED.system_qty_before,
        qty_difference    = EXCLUDED.qty_difference,
        load_id           = EXCLUDED.load_id,
        created_by        = EXCLUDED.created_by,
        updated_at        = CURRENT_TIMESTAMP;

    RAISE NOTICE
        'Stock count posted. Load ID: %, stock date: %, file rows: %, SKU+store counted: %, replaced earlier count for same date: %, new SKUs created: %, rows skipped (unknown store or SKU): %',
        p_load_id, v_stock_date, v_total_rows, v_counted, v_replaced, v_new_skus_created, v_unresolvable;
    PERFORM public.fn_proc_run_end(v_run_id, jsonb_build_object('stock_date', v_stock_date, 'file_rows', v_total_rows, 'counted', v_counted, 'replaced', v_replaced, 'new_skus', v_new_skus_created, 'skipped', v_unresolvable));
END;
$procedure$
;


CREATE OR REPLACE PROCEDURE shinde_shoes.sp_validate_purchase_load(IN p_load_id integer)
 LANGUAGE plpgsql
AS $procedure$

DECLARE
    v_run_id bigint;   -- public.proc_run_log
    v_total_rows   integer := 0;
    v_invalid_rows integer := 0;
    v_valid_rows   integer := 0;

BEGIN
    v_run_id := public.fn_proc_run_start('shinde_shoes.sp_validate_purchase_load', p_load_id, NULL);

    -- ============================================================
    -- STEP 1: Check load
    -- ============================================================

    SELECT COUNT(*)
    INTO v_total_rows
    FROM shinde_shoes.stg_purchase_1
    WHERE load_id = p_load_id;

    IF v_total_rows = 0 THEN
        RAISE EXCEPTION
            'No purchase records found for load_id %',
            p_load_id;
    END IF;


    -- ============================================================
    -- STEP 2: Validate all rows (single set-based INSERT)
    -- ============================================================

    INSERT INTO shinde_shoes.validation_error
    (
        load_id,
        row_no,
        file_type,
        error_code,
        error_column,
        error_value,
        error_message,
        created_by
    )

    SELECT
        i.load_id,
        i.row_no,
        'purchase',
        v.error_code,
        v.error_column,
        v.error_value,
        v.error_message,
        i.created_by

    FROM shinde_shoes.stg_purchase_1 i

    CROSS JOIN LATERAL
    (
        VALUES

        -- ========================================================
        -- SKU -- presence only, DimProduct is no longer checked
        -- ========================================================
        (
            'SKU_REQUIRED', 'SKU', i."SKU",
            'SKU is required.',
            NULLIF(TRIM(i."SKU"), '') IS NULL
        ),

        -- ========================================================
        -- PRODUCT CODE / DESC / BRAND / SIZE / COLOR
        -- ========================================================
        (
            'PRODUCTCODE_REQUIRED', 'ProductCode', i."ProductCode",
            'ProductCode is required.',
            NULLIF(TRIM(i."ProductCode"), '') IS NULL
        ),
        (
            'PRODUCTDESC_REQUIRED', 'ProductDesc', i."ProductDesc",
            'ProductDesc is required.',
            NULLIF(TRIM(i."ProductDesc"), '') IS NULL
        ),
        (
            'BRAND_REQUIRED', 'Brand', i."Brand",
            'Brand is required.',
            NULLIF(TRIM(i."Brand"), '') IS NULL
        ),
        (
            'SIZE_REQUIRED', 'Size', i."Size",
            'Size is required.',
            NULLIF(TRIM(i."Size"), '') IS NULL
        ),
        (
            'COLORCODE_REQUIRED', 'ColorCode', i."ColorCode",
            'ColorCode is required.',
            NULLIF(TRIM(i."ColorCode"), '') IS NULL
        ),

        -- ========================================================
        -- QTY (required)
        -- ========================================================
        (
            'QTY_REQUIRED', 'Qty', i."Qty",
            'Quantity is required.',
            NULLIF(TRIM(i."Qty"), '') IS NULL
        ),
        (
            'INVALID_QTY', 'Qty', i."Qty",
            'Quantity must be numeric and cannot be negative.',
            NULLIF(TRIM(i."Qty"), '') IS NOT NULL
            AND (
                TRIM(i."Qty") !~ '^[+-]?([0-9]+(\.[0-9]+)?|\.[0-9]+)$'
                OR TRIM(i."Qty")::numeric < 0
            )
        ),

        -- ========================================================
        -- MRP (required)
        -- ========================================================
        (
            'MRP_REQUIRED', 'MRP', i."MRP",
            'MRP is required.',
            NULLIF(TRIM(i."MRP"), '') IS NULL
        ),
        (
            'INVALID_MRP', 'MRP', i."MRP",
            'MRP must be numeric and cannot be negative.',
            NULLIF(TRIM(i."MRP"), '') IS NOT NULL
            AND (
                TRIM(i."MRP") !~ '^[+-]?([0-9]+(\.[0-9]+)?|\.[0-9]+)$'
                OR TRIM(i."MRP")::numeric < 0
            )
        ),

        -- ========================================================
        -- SALE RATE (required)
        -- ========================================================
        (
            'SALERATE_REQUIRED', 'SaleRate', i."SaleRate",
            'SaleRate is required.',
            NULLIF(TRIM(i."SaleRate"), '') IS NULL
        ),
        (
            'INVALID_SALERATE', 'SaleRate', i."SaleRate",
            'SaleRate must be numeric and cannot be negative.',
            NULLIF(TRIM(i."SaleRate"), '') IS NOT NULL
            AND (
                TRIM(i."SaleRate") !~ '^[+-]?([0-9]+(\.[0-9]+)?|\.[0-9]+)$'
                OR TRIM(i."SaleRate")::numeric < 0
            )
        ),

        -- ========================================================
        -- PURCHASE RATE (required)
        -- ========================================================
        (
            'PURCHASERATE_REQUIRED', 'PurchaseRate', i."PurchaseRate",
            'PurchaseRate is required.',
            NULLIF(TRIM(i."PurchaseRate"), '') IS NULL
        ),
        (
            'INVALID_PURCHASERATE', 'PurchaseRate', i."PurchaseRate",
            'PurchaseRate must be numeric and cannot be negative.',
            NULLIF(TRIM(i."PurchaseRate"), '') IS NOT NULL
            AND (
                TRIM(i."PurchaseRate") !~ '^[+-]?([0-9]+(\.[0-9]+)?|\.[0-9]+)$'
                OR TRIM(i."PurchaseRate")::numeric < 0
            )
        ),

        -- ========================================================
        -- BILL NO (required)
        -- ========================================================
        (
            'BILLNO_REQUIRED', 'BillNo', i."BillNo",
            'BillNo is required.',
            NULLIF(TRIM(i."BillNo"), '') IS NULL
        ),

        -- ========================================================
        -- BILL DATE (required, must parse)
        -- ========================================================
        (
            'BILLDATE_REQUIRED', 'BillDate', i."BillDate",
            'BillDate is required.',
            NULLIF(TRIM(i."BillDate"), '') IS NULL
        ),
        (
            'INVALID_BILLDATE', 'BillDate', i."BillDate",
            'BillDate must be a valid DD-MM-YYYY date.',
            NULLIF(TRIM(i."BillDate"), '') IS NOT NULL
            AND shinde_shoes.parse_date_dd_mm_yyyy(i."BillDate") IS NULL
        ),

        -- ========================================================
        -- LOCATION (required, must exist in DimLocation)
        -- ========================================================
        (
            'LOCATION_REQUIRED', 'LocationName', i."LocationName",
            'LocationName is required.',
            NULLIF(TRIM(i."LocationName"), '') IS NULL
        ),
        (
            'LOCATION_NOT_FOUND', 'LocationName', i."LocationName",
            'LocationName does not exist in DimLocation.',
            NULLIF(TRIM(i."LocationName"), '') IS NOT NULL
            AND NOT EXISTS (
                SELECT 1 FROM shinde_shoes."DimLocation" l
                WHERE TRIM(l."locationName") = TRIM(i."LocationName")
            )
        ),

        -- ========================================================
        -- OPTIONAL NUMERIC FIELDS -- blank OK, invalid/negative = error
        -- ========================================================
        (
            'INVALID_PACKQTY', 'PackQty', i."PackQty",
            'PackQty must be numeric and cannot be negative.',
            NULLIF(TRIM(i."PackQty"), '') IS NOT NULL
            AND (TRIM(i."PackQty") !~ '^[+-]?([0-9]+(\.[0-9]+)?|\.[0-9]+)$' OR TRIM(i."PackQty")::numeric < 0)
        ),
        (
            'INVALID_TOTALQTY', 'TotalQty', i."TotalQty",
            'TotalQty must be numeric and cannot be negative.',
            NULLIF(TRIM(i."TotalQty"), '') IS NOT NULL
            AND (TRIM(i."TotalQty") !~ '^[+-]?([0-9]+(\.[0-9]+)?|\.[0-9]+)$' OR TRIM(i."TotalQty")::numeric < 0)
        ),
        (
            'INVALID_PRODUCT_DISCOUNT_PERCENT', 'ProductDiscountPercent', i."ProductDiscountPercent",
            'ProductDiscountPercent must be numeric and cannot be negative.',
            NULLIF(TRIM(i."ProductDiscountPercent"), '') IS NOT NULL
            AND (TRIM(i."ProductDiscountPercent") !~ '^[+-]?([0-9]+(\.[0-9]+)?|\.[0-9]+)$' OR TRIM(i."ProductDiscountPercent")::numeric < 0)
        ),
        (
            'INVALID_PRODUCT_DISCOUNT_AMOUNT', 'ProductDiscountAmount', i."ProductDiscountAmount",
            'ProductDiscountAmount must be numeric and cannot be negative.',
            NULLIF(TRIM(i."ProductDiscountAmount"), '') IS NOT NULL
            AND (TRIM(i."ProductDiscountAmount") !~ '^[+-]?([0-9]+(\.[0-9]+)?|\.[0-9]+)$' OR TRIM(i."ProductDiscountAmount")::numeric < 0)
        ),
        (
            'INVALID_AMOUNT', 'Amount', i."Amount",
            'Amount must be numeric and cannot be negative.',
            NULLIF(TRIM(i."Amount"), '') IS NOT NULL
            AND (TRIM(i."Amount") !~ '^[+-]?([0-9]+(\.[0-9]+)?|\.[0-9]+)$' OR TRIM(i."Amount")::numeric < 0)
        ),
        (
            'INVALID_BILL_DISCOUNT', 'BillDiscount', i."BillDiscount",
            'BillDiscount must be numeric and cannot be negative.',
            NULLIF(TRIM(i."BillDiscount"), '') IS NOT NULL
            AND (TRIM(i."BillDiscount") !~ '^[+-]?([0-9]+(\.[0-9]+)?|\.[0-9]+)$' OR TRIM(i."BillDiscount")::numeric < 0)
        ),
        (
            'INVALID_RATE_AFTER_DISCOUNT', 'RateAfterDiscount', i."RateAfterDiscount",
            'RateAfterDiscount must be numeric and cannot be negative.',
            NULLIF(TRIM(i."RateAfterDiscount"), '') IS NOT NULL
            AND (TRIM(i."RateAfterDiscount") !~ '^[+-]?([0-9]+(\.[0-9]+)?|\.[0-9]+)$' OR TRIM(i."RateAfterDiscount")::numeric < 0)
        ),
        (
            'INVALID_TOTAL_DISCOUNT_AMOUNT', 'TotalDiscountAmount', i."TotalDiscountAmount",
            'TotalDiscountAmount must be numeric and cannot be negative.',
            NULLIF(TRIM(i."TotalDiscountAmount"), '') IS NOT NULL
            AND (TRIM(i."TotalDiscountAmount") !~ '^[+-]?([0-9]+(\.[0-9]+)?|\.[0-9]+)$' OR TRIM(i."TotalDiscountAmount")::numeric < 0)
        ),
        (
            'INVALID_TAXABLE_AMOUNT', 'TaxableAmount', i."TaxableAmount",
            'TaxableAmount must be numeric and cannot be negative.',
            NULLIF(TRIM(i."TaxableAmount"), '') IS NOT NULL
            AND (TRIM(i."TaxableAmount") !~ '^[+-]?([0-9]+(\.[0-9]+)?|\.[0-9]+)$' OR TRIM(i."TaxableAmount")::numeric < 0)
        ),
        (
            'INVALID_TAX_RATE', 'TaxRate', i."TaxRate",
            'TaxRate must be numeric and cannot be negative.',
            NULLIF(TRIM(i."TaxRate"), '') IS NOT NULL
            AND (TRIM(i."TaxRate") !~ '^[+-]?([0-9]+(\.[0-9]+)?|\.[0-9]+)$' OR TRIM(i."TaxRate")::numeric < 0)
        ),
        (
            'INVALID_TAX_AMT', 'TaxAmt', i."TaxAmt",
            'TaxAmt must be numeric and cannot be negative.',
            NULLIF(TRIM(i."TaxAmt"), '') IS NOT NULL
            AND (TRIM(i."TaxAmt") !~ '^[+-]?([0-9]+(\.[0-9]+)?|\.[0-9]+)$' OR TRIM(i."TaxAmt")::numeric < 0)
        ),
        (
            'INVALID_NET_AMOUNT', 'NetAmount', i."NetAmount",
            'NetAmount must be numeric and cannot be negative.',
            NULLIF(TRIM(i."NetAmount"), '') IS NOT NULL
            AND (TRIM(i."NetAmount") !~ '^[+-]?([0-9]+(\.[0-9]+)?|\.[0-9]+)$' OR TRIM(i."NetAmount")::numeric < 0)
        ),
        (
            'INVALID_COST', 'Cost', i."Cost",
            'Cost must be numeric and cannot be negative.',
            NULLIF(TRIM(i."Cost"), '') IS NOT NULL
            AND (TRIM(i."Cost") !~ '^[+-]?([0-9]+(\.[0-9]+)?|\.[0-9]+)$' OR TRIM(i."Cost")::numeric < 0)
        ),
        (
            'INVALID_COST_AMT', 'CostAmt', i."CostAmt",
            'CostAmt must be numeric and cannot be negative.',
            NULLIF(TRIM(i."CostAmt"), '') IS NOT NULL
            AND (TRIM(i."CostAmt") !~ '^[+-]?([0-9]+(\.[0-9]+)?|\.[0-9]+)$' OR TRIM(i."CostAmt")::numeric < 0)
        ),
        (
            'INVALID_TCS_RATE', 'TCSRate', i."TCSRate",
            'TCSRate must be numeric and cannot be negative.',
            NULLIF(TRIM(i."TCSRate"), '') IS NOT NULL
            AND (TRIM(i."TCSRate") !~ '^[+-]?([0-9]+(\.[0-9]+)?|\.[0-9]+)$' OR TRIM(i."TCSRate")::numeric < 0)
        ),
        (
            'INVALID_TCS_AMOUNT', 'TCSAmount', i."TCSAmount",
            'TCSAmount must be numeric and cannot be negative.',
            NULLIF(TRIM(i."TCSAmount"), '') IS NOT NULL
            AND (TRIM(i."TCSAmount") !~ '^[+-]?([0-9]+(\.[0-9]+)?|\.[0-9]+)$' OR TRIM(i."TCSAmount")::numeric < 0)
        ),

        -- ========================================================
        -- OPTIONAL DATE -- PurchaeBillRefDate (source column name, sic)
        -- ========================================================
        (
            'INVALID_PURCHASE_BILL_REF_DATE', 'PurchaeBillRefDate', i."PurchaeBillRefDate",
            'PurchaeBillRefDate must be a valid DD-MM-YYYY date.',
            NULLIF(TRIM(i."PurchaeBillRefDate"), '') IS NOT NULL
            AND shinde_shoes.parse_date_dd_mm_yyyy(i."PurchaeBillRefDate") IS NULL
        )

    ) AS v
    (
        error_code,
        error_column,
        error_value,
        error_message,
        is_error
    )

    WHERE i.load_id = p_load_id
      AND v.is_error = true;


    -- ============================================================
    -- STEP 3: Count invalid rows
    -- ============================================================

    SELECT COUNT(DISTINCT i.row_no)
    INTO v_invalid_rows
    FROM shinde_shoes.stg_purchase_1 i
    WHERE i.load_id = p_load_id
      AND EXISTS (
          SELECT 1 FROM shinde_shoes.validation_error e
          WHERE e.load_id = i.load_id
            AND e.row_no = i.row_no
            AND e.file_type = 'purchase'
      );

    v_valid_rows := v_total_rows - v_invalid_rows;


    -- ============================================================
    -- STEP 4: Insert VALID rows into backup_stg_purchase_2 (append-only)
    -- ============================================================

    INSERT INTO shinde_shoes.backup_stg_purchase_2
    (
        row_no, load_id, "AlternateCode", "ProductCode", "ProductDesc",
        "Composite", "BatchCode", "CategoryCode", "CategoryDesc",
        "SubCategoryCode", "SubCategoryDesc", "OptionalCategory",
        "ProductGroup", "CollectionDesc", "WashName", "FitName",
        "ColorCode", "ColorDesc", "Brand", "Size", "SizeRange",
        "Qty", "PackQty", "TotalQty", "MRP", "SaleRate",
        "ProductDiscountPercent", "ProductDiscountAmount", "PurchaseRate",
        "Amount", "BillDiscount", "RateAfterDiscount",
        "TotalDiscountAmount", "TaxableAmount", "HSNCode", "HSNDesc",
        "TaxDesc", "TaxRate", "TaxAmt", "NetAmount", "CPCode", "Cost",
        "CostAmt", "Supplier", "GSTIN", "Merchandiser", "StockType",
        "GodownCode", "GodownDesc", "RackCode", "RackDesc",
        "BillComment", "ProductComment", "CreatedOn", "CreatedUser",
        "ModifiedUser", "ChargeProductType", "LocationName",
        "PurchaseBillRefNo", "PurchaeBillRefDate", "TCSRate",
        "TCSAmount", "ERPItem_ID", "BillNo", "BillDate", "SKU",
        "SourceCode", created_at, created_by
    )

    SELECT
        i.row_no, i.load_id, i."AlternateCode", i."ProductCode", i."ProductDesc",
        i."Composite", i."BatchCode", i."CategoryCode", i."CategoryDesc",
        i."SubCategoryCode", i."SubCategoryDesc", i."OptionalCategory",
        i."ProductGroup", i."CollectionDesc", i."WashName", i."FitName",
        i."ColorCode", i."ColorDesc", i."Brand", i."Size", i."SizeRange",

        TRIM(i."Qty")::numeric,
        COALESCE(NULLIF(TRIM(i."PackQty"), '')::numeric, 0),
        COALESCE(NULLIF(TRIM(i."TotalQty"), '')::numeric, 0),
        TRIM(i."MRP")::numeric,
        TRIM(i."SaleRate")::numeric,

        COALESCE(NULLIF(TRIM(i."ProductDiscountPercent"), '')::numeric, 0),
        COALESCE(NULLIF(TRIM(i."ProductDiscountAmount"), '')::numeric, 0),
        TRIM(i."PurchaseRate")::numeric,
        COALESCE(NULLIF(TRIM(i."Amount"), '')::numeric, 0),
        COALESCE(NULLIF(TRIM(i."BillDiscount"), '')::numeric, 0),
        COALESCE(NULLIF(TRIM(i."RateAfterDiscount"), '')::numeric, 0),
        COALESCE(NULLIF(TRIM(i."TotalDiscountAmount"), '')::numeric, 0),
        COALESCE(NULLIF(TRIM(i."TaxableAmount"), '')::numeric, 0),

        i."HSNCode", i."HSNDesc", i."TaxDesc",

        COALESCE(NULLIF(TRIM(i."TaxRate"), '')::numeric, 0),
        COALESCE(NULLIF(TRIM(i."TaxAmt"), '')::numeric, 0),
        COALESCE(NULLIF(TRIM(i."NetAmount"), '')::numeric, 0),

        i."CPCode",

        COALESCE(NULLIF(TRIM(i."Cost"), '')::numeric, 0),
        COALESCE(NULLIF(TRIM(i."CostAmt"), '')::numeric, 0),

        i."Supplier", i."GSTIN", i."Merchandiser", i."StockType",
        i."GodownCode", i."GodownDesc", i."RackCode", i."RackDesc",
        i."BillComment", i."ProductComment",

        CASE
            WHEN TRIM(i."CreatedOn") ~ '^\d{4}-\d{2}-\d{2}([ T]\d{2}:\d{2}(:\d{2})?)?$'
            THEN TRIM(i."CreatedOn")::timestamp
            ELSE NULL
        END,

        i."CreatedUser", i."ModifiedUser", i."ChargeProductType",
        i."LocationName", i."PurchaseBillRefNo",

        CASE
            WHEN NULLIF(TRIM(i."PurchaeBillRefDate"), '') IS NULL THEN NULL
            ELSE shinde_shoes.parse_date_dd_mm_yyyy(i."PurchaeBillRefDate")
        END,

        COALESCE(NULLIF(TRIM(i."TCSRate"), '')::numeric, 0),
        COALESCE(NULLIF(TRIM(i."TCSAmount"), '')::numeric, 0),

        i."ERPItem_ID", i."BillNo",
        shinde_shoes.parse_date_dd_mm_yyyy(i."BillDate"),
        i."SKU", i."SourceCode",
        i.created_at, i.created_by

    FROM shinde_shoes.stg_purchase_1 i
    WHERE i.load_id = p_load_id
      AND NOT EXISTS (
          SELECT 1 FROM shinde_shoes.validation_error e
          WHERE e.load_id = i.load_id
            AND e.row_no = i.row_no
            AND e.file_type = 'purchase'
      );


    -- ============================================================
    -- STEP 5: Insert VALID rows into stg_purchase_2 (identical to step 4)
    -- ============================================================

    INSERT INTO shinde_shoes.stg_purchase_2
    (
        row_no, load_id, "AlternateCode", "ProductCode", "ProductDesc",
        "Composite", "BatchCode", "CategoryCode", "CategoryDesc",
        "SubCategoryCode", "SubCategoryDesc", "OptionalCategory",
        "ProductGroup", "CollectionDesc", "WashName", "FitName",
        "ColorCode", "ColorDesc", "Brand", "Size", "SizeRange",
        "Qty", "PackQty", "TotalQty", "MRP", "SaleRate",
        "ProductDiscountPercent", "ProductDiscountAmount", "PurchaseRate",
        "Amount", "BillDiscount", "RateAfterDiscount",
        "TotalDiscountAmount", "TaxableAmount", "HSNCode", "HSNDesc",
        "TaxDesc", "TaxRate", "TaxAmt", "NetAmount", "CPCode", "Cost",
        "CostAmt", "Supplier", "GSTIN", "Merchandiser", "StockType",
        "GodownCode", "GodownDesc", "RackCode", "RackDesc",
        "BillComment", "ProductComment", "CreatedOn", "CreatedUser",
        "ModifiedUser", "ChargeProductType", "LocationName",
        "PurchaseBillRefNo", "PurchaeBillRefDate", "TCSRate",
        "TCSAmount", "ERPItem_ID", "BillNo", "BillDate", "SKU",
        "SourceCode", created_at, created_by
    )

    SELECT
        i.row_no, i.load_id, i."AlternateCode", i."ProductCode", i."ProductDesc",
        i."Composite", i."BatchCode", i."CategoryCode", i."CategoryDesc",
        i."SubCategoryCode", i."SubCategoryDesc", i."OptionalCategory",
        i."ProductGroup", i."CollectionDesc", i."WashName", i."FitName",
        i."ColorCode", i."ColorDesc", i."Brand", i."Size", i."SizeRange",

        TRIM(i."Qty")::numeric,
        COALESCE(NULLIF(TRIM(i."PackQty"), '')::numeric, 0),
        COALESCE(NULLIF(TRIM(i."TotalQty"), '')::numeric, 0),
        TRIM(i."MRP")::numeric,
        TRIM(i."SaleRate")::numeric,

        COALESCE(NULLIF(TRIM(i."ProductDiscountPercent"), '')::numeric, 0),
        COALESCE(NULLIF(TRIM(i."ProductDiscountAmount"), '')::numeric, 0),
        TRIM(i."PurchaseRate")::numeric,
        COALESCE(NULLIF(TRIM(i."Amount"), '')::numeric, 0),
        COALESCE(NULLIF(TRIM(i."BillDiscount"), '')::numeric, 0),
        COALESCE(NULLIF(TRIM(i."RateAfterDiscount"), '')::numeric, 0),
        COALESCE(NULLIF(TRIM(i."TotalDiscountAmount"), '')::numeric, 0),
        COALESCE(NULLIF(TRIM(i."TaxableAmount"), '')::numeric, 0),

        i."HSNCode", i."HSNDesc", i."TaxDesc",

        COALESCE(NULLIF(TRIM(i."TaxRate"), '')::numeric, 0),
        COALESCE(NULLIF(TRIM(i."TaxAmt"), '')::numeric, 0),
        COALESCE(NULLIF(TRIM(i."NetAmount"), '')::numeric, 0),

        i."CPCode",

        COALESCE(NULLIF(TRIM(i."Cost"), '')::numeric, 0),
        COALESCE(NULLIF(TRIM(i."CostAmt"), '')::numeric, 0),

        i."Supplier", i."GSTIN", i."Merchandiser", i."StockType",
        i."GodownCode", i."GodownDesc", i."RackCode", i."RackDesc",
        i."BillComment", i."ProductComment",

        CASE
            WHEN TRIM(i."CreatedOn") ~ '^\d{4}-\d{2}-\d{2}([ T]\d{2}:\d{2}(:\d{2})?)?$'
            THEN TRIM(i."CreatedOn")::timestamp
            ELSE NULL
        END,

        i."CreatedUser", i."ModifiedUser", i."ChargeProductType",
        i."LocationName", i."PurchaseBillRefNo",

        CASE
            WHEN NULLIF(TRIM(i."PurchaeBillRefDate"), '') IS NULL THEN NULL
            ELSE shinde_shoes.parse_date_dd_mm_yyyy(i."PurchaeBillRefDate")
        END,

        COALESCE(NULLIF(TRIM(i."TCSRate"), '')::numeric, 0),
        COALESCE(NULLIF(TRIM(i."TCSAmount"), '')::numeric, 0),

        i."ERPItem_ID", i."BillNo",
        shinde_shoes.parse_date_dd_mm_yyyy(i."BillDate"),
        i."SKU", i."SourceCode",
        i.created_at, i.created_by

    FROM shinde_shoes.stg_purchase_1 i
    WHERE i.load_id = p_load_id
      AND NOT EXISTS (
          SELECT 1 FROM shinde_shoes.validation_error e
          WHERE e.load_id = i.load_id
            AND e.row_no = i.row_no
            AND e.file_type = 'purchase'
      );


    -- ============================================================
    -- STEP 6: Final summary
    -- ============================================================

    RAISE NOTICE
        'Purchase validation completed. Load ID: %, Total: %, Valid: %, Invalid: %',
        p_load_id,
        v_total_rows,
        v_valid_rows,
        v_invalid_rows;

    PERFORM public.fn_proc_run_end(v_run_id, jsonb_build_object('total_rows', v_total_rows, 'valid_rows', v_valid_rows, 'invalid_rows', v_invalid_rows));
END;
$procedure$
;


CREATE OR REPLACE PROCEDURE shinde_shoes.sp_process_purchase_load(IN p_load_id integer)
 LANGUAGE plpgsql
AS $procedure$

-- These variables only feed the summary message printed at the very end --
-- they don't affect any of the actual data logic.
DECLARE
    v_run_id bigint;   -- public.proc_run_log
    v_total_rows          integer := 0;
    v_existing_sku_rows   integer := 0;
    v_new_sku_rows        integer := 0;
    v_new_skus_created    integer := 0;
    v_unresolvable_rows   integer := 0;
    v_purchase_posted_rows integer := 0;
    v_stock_posted_rows    integer := 0;

BEGIN
    v_run_id := public.fn_proc_run_start('shinde_shoes.sp_process_purchase_load', p_load_id, NULL);

    -- ========================================================================
    -- STEP 1: Make sure there's actually something to process.
    -- ========================================================================

    SELECT COUNT(*)
    INTO v_total_rows
    FROM shinde_shoes.stg_purchase_2
    WHERE load_id = p_load_id;

    IF v_total_rows = 0 THEN
        RAISE EXCEPTION
            'No validated purchase records found for load_id % in stg_purchase_2',
            p_load_id;
    END IF;

    -- ========================================================================
    -- STEP 2: Resolve every dimension key, auto-create any missing
    -- DimProduct (SKU) row, post the movement, and update BOTH
    -- purchase_fact_master (whole-load, cumulative) and stock_fact_master
    -- (per-date, date-wise) -- all in one statement, one CTE block at a time.
    -- ========================================================================

    WITH

    -- ------------------------------------------------------------------
    -- BLOCK: attrs
    -- For every row in this load, resolve the key for every attribute --
    -- "LocationKey", "BrandKey", "CategoryKey", "SubCategoryKey",
    -- "ProductCodeKey", "ColorKey", "SizeKey", "SupplierKey" -- using the
    -- existing Fn_Validate_* functions, one call per row per attribute.
    -- ------------------------------------------------------------------
    attrs AS (
        SELECT
            i.load_id,
            i.row_no,
            i.created_by,
            TRIM(i."SKU")              AS "SKU",
            loc."LocationKey",
            brand_lookup."BrandKey",
            category_lookup."CategoryKey",
            subcategory_lookup."SubCategoryKey",
            productcode_lookup."ProductCodeKey",
            color_lookup."ColorKey",
            size_lookup."SizeKey",
            supplier_lookup."SupplierKey",
            date_lookup."DateKey",
            COALESCE(i."Qty", 0)       AS "Qty",
            COALESCE(i."BillDate", CURRENT_DATE) AS "BillDate",
            i."ProductDesc"            AS "ProductDesc",
            i."CategoryDesc"           AS "CategoryDesc",
            COALESCE(i."MRP", 0)       AS "MRP",
            COALESCE(i."SaleRate", 0)  AS "SaleRate"

        FROM shinde_shoes.stg_purchase_2 i

        CROSS JOIN LATERAL (
            SELECT NULLIF(
                shinde_shoes."Fn_Validate_Location"(TRIM(i."LocationName"), i."SKU", NULL::integer), 0
            ) AS "LocationKey"
        ) loc

        CROSS JOIN LATERAL (
            SELECT NULLIF(
                shinde_shoes."Fn_Validate_Brand"(TRIM(i."Brand"), i."SKU"), 0
            ) AS "BrandKey"
        ) brand_lookup

        CROSS JOIN LATERAL (
            SELECT NULLIF(
                shinde_shoes."Fn_Validate_Category"(
                    TRIM(i."CategoryDesc"), TRIM(i."CategoryCode"), i."SKU"
                ), 0
            ) AS "CategoryKey"
        ) category_lookup

        CROSS JOIN LATERAL (
            SELECT NULLIF(
                shinde_shoes."Fn_Validate_SubCategory"(
                    category_lookup."CategoryKey", TRIM(i."SubCategoryCode"), TRIM(i."SubCategoryDesc"), i."SKU"
                ), 0
            ) AS "SubCategoryKey"
        ) subcategory_lookup

        CROSS JOIN LATERAL (
            SELECT NULLIF(
                shinde_shoes."Fn_Validate_ProductCode"(
                    subcategory_lookup."SubCategoryKey", TRIM(i."ProductCode"), TRIM(i."ProductDesc"), i."SKU"
                ), 0
            ) AS "ProductCodeKey"
        ) productcode_lookup

        CROSS JOIN LATERAL (
            SELECT NULLIF(
                shinde_shoes."Fn_Validate_Color"(
                    TRIM(i."ColorDesc"), TRIM(i."ColorCode"), i."SKU"
                ), 0
            ) AS "ColorKey"
        ) color_lookup

        CROSS JOIN LATERAL (
            SELECT NULLIF(
                shinde_shoes."Fn_Validate_Size"(
                    TRIM(i."Size"), TRIM(i."SizeRange"), i."SKU"
                ), 0
            ) AS "SizeKey"
        ) size_lookup

        CROSS JOIN LATERAL (
            SELECT NULLIF(
                shinde_shoes."Fn_Validate_Supplier"(TRIM(i."Supplier"), i."SKU"), 0
            ) AS "SupplierKey"
        ) supplier_lookup

        CROSS JOIN LATERAL (
            SELECT shinde_shoes."Fn_Load_DimDate"(
                COALESCE(i."BillDate", CURRENT_DATE)
            ) AS "DateKey"
        ) date_lookup

        WHERE i.load_id = p_load_id
    ),

    -- ------------------------------------------------------------------
    -- BLOCK: new_sku_candidates
    -- ------------------------------------------------------------------
    new_sku_candidates AS (
        SELECT DISTINCT ON (a."SKU")
            a."SKU", a."BrandKey", a."ProductCodeKey", a."ColorKey",
            a."SizeKey", a."SupplierKey", a."ProductDesc", a."CategoryDesc",
            a."MRP", a."SaleRate", a."BillDate"
        FROM attrs a
        WHERE NOT EXISTS (
                SELECT 1 FROM shinde_shoes."DimProduct" dp
                WHERE dp."SKU" = a."SKU"
              )
          AND a."BrandKey" IS NOT NULL
          AND a."ProductCodeKey" IS NOT NULL
          AND a."ColorKey" IS NOT NULL
          AND a."SizeKey" IS NOT NULL
          AND a."SupplierKey" IS NOT NULL
        ORDER BY a."SKU", a.row_no DESC
    ),

    -- ------------------------------------------------------------------
    -- BLOCK: new_products
    -- ------------------------------------------------------------------
    new_products AS (
        INSERT INTO shinde_shoes."DimProduct"
        (
            "BrandKey", "ProductCodeKey", "ColorKey", "SizeKey", "SupplierKey",
            "SKU", "ProductDesc", "CategoryDesc", "MRP", "SaleRate", "PurchaseDate"
        )
        SELECT
            "BrandKey", "ProductCodeKey", "ColorKey", "SizeKey", "SupplierKey",
            "SKU", "ProductDesc", "CategoryDesc", "MRP", "SaleRate", "BillDate"
        FROM new_sku_candidates
        ON CONFLICT ("SKU") DO NOTHING
        RETURNING "SKUKey", "SKU"
    ),

    -- ------------------------------------------------------------------
    -- BLOCK: resolved
    -- ------------------------------------------------------------------
    resolved AS (
        SELECT
            a.load_id, a.row_no, a.created_by,
            COALESCE(dp."SKUKey", np."SKUKey") AS "SKUKey",
            a."LocationKey", a."BrandKey", a."CategoryKey", a."SubCategoryKey",
            a."ProductCodeKey", a."ColorKey", a."SizeKey", a."SupplierKey",
            a."Qty", a."BillDate", a."DateKey"
        FROM attrs a
        LEFT JOIN shinde_shoes."DimProduct" dp ON dp."SKU" = a."SKU"
        LEFT JOIN new_products np ON np."SKU" = a."SKU"
        WHERE COALESCE(dp."SKUKey", np."SKUKey") IS NOT NULL
    ),

    -- ------------------------------------------------------------------
    -- BLOCK: inserted
    -- ------------------------------------------------------------------
    inserted AS (
        INSERT INTO shinde_shoes.stock_transaction
        (
            "SKUKey", "LocationKey", transaction_date, movement_type,
            quantity, load_id, row_no, source_file_type, created_by
        )
        SELECT
            r."SKUKey", r."LocationKey", r."BillDate", 'PURCHASE',
            r."Qty", r.load_id, r.row_no, 'purchase', r.created_by
        FROM resolved r
        WHERE r."LocationKey" IS NOT NULL
        ON CONFLICT (load_id, row_no, source_file_type)
            WHERE load_id IS NOT NULL AND row_no IS NOT NULL
            DO NOTHING
        RETURNING transaction_id, "SKUKey", "LocationKey", row_no, quantity, transaction_date
    ),

    -- ------------------------------------------------------------------
    -- BLOCK: qty_totals, then latest_per_sku_location
    -- Whole-load totals -- feeds purchase_fact_master ONLY now.
    -- ------------------------------------------------------------------
    qty_totals AS (
        SELECT "SKUKey", "LocationKey",
               SUM(quantity)   AS total_qty,
               MAX(row_no)     AS latest_row_no
        FROM inserted
        GROUP BY "SKUKey", "LocationKey"
    ),

    latest_per_sku_location AS (
        SELECT
            qt."SKUKey", qt."LocationKey", qt.total_qty,
            r."BrandKey", r."CategoryKey", r."SubCategoryKey", r."ProductCodeKey",
            r."ColorKey", r."SizeKey", r."SupplierKey",
            r."DateKey",
            ins.transaction_id AS latest_transaction_id
        FROM qty_totals qt
        JOIN inserted ins
            ON ins."SKUKey" = qt."SKUKey" AND ins."LocationKey" = qt."LocationKey"
           AND ins.row_no = qt.latest_row_no
        JOIN resolved r
            ON r."SKUKey" = qt."SKUKey" AND r."LocationKey" = qt."LocationKey"
           AND r.row_no = qt.latest_row_no
    ),

    -- ------------------------------------------------------------------
    -- BLOCK: purchase_fact_upsert
    -- purchase_fact_master stays whole-load / cumulative / 2-column key --
    -- outside the date-wise redesign, unchanged.
    -- ------------------------------------------------------------------
    purchase_fact_upsert AS (
        INSERT INTO shinde_shoes.purchase_fact_master
        (
            "SKUKey", "LocationKey", "BrandKey", "ProductCodeKey", "ColorKey",
            "SizeKey", "SupplierKey", "CategoryKey", "SubCategoryKey", "DateKey",
            total_purchased_qty, last_transaction_id, created_by, last_updated_by
        )
        SELECT
            "SKUKey", "LocationKey", "BrandKey", "ProductCodeKey", "ColorKey",
            "SizeKey", "SupplierKey", "CategoryKey", "SubCategoryKey", "DateKey",
            total_qty, latest_transaction_id,
            'load_' || p_load_id, 'load_' || p_load_id
        FROM latest_per_sku_location
        ON CONFLICT ("SKUKey", "LocationKey") DO UPDATE SET
            total_purchased_qty  = shinde_shoes.purchase_fact_master.total_purchased_qty + EXCLUDED.total_purchased_qty,
            "BrandKey"           = EXCLUDED."BrandKey",
            "ProductCodeKey"     = EXCLUDED."ProductCodeKey",
            "ColorKey"           = EXCLUDED."ColorKey",
            "SizeKey"            = EXCLUDED."SizeKey",
            "SupplierKey"        = EXCLUDED."SupplierKey",
            "CategoryKey"        = EXCLUDED."CategoryKey",
            "SubCategoryKey"     = EXCLUDED."SubCategoryKey",
            "DateKey"            = EXCLUDED."DateKey",
            last_transaction_id  = EXCLUDED.last_transaction_id,
            last_updated_by      = EXCLUDED.last_updated_by
        RETURNING 1
    ),

    -- ------------------------------------------------------------------
    -- BLOCK: date_totals
    -- THE FIX: group this call's OWN newly-inserted rows per calendar
    -- date (not per whole load), since one Purchase file/load can span
    -- several dates (e.g. 07-Sep..14-Sep-2026).
    -- ------------------------------------------------------------------
    date_totals AS (
        SELECT "SKUKey", "LocationKey", transaction_date AS batch_date,
               SUM(quantity) AS day_qty,
               MAX(row_no)   AS latest_row_no_for_day
        FROM inserted
        GROUP BY "SKUKey", "LocationKey", transaction_date
    ),

    -- ------------------------------------------------------------------
    -- BLOCK: per_date
    -- Attach attribute values (from the highest row_no on that date)
    -- and that date's latest transaction_id to each date_totals row.
    -- ------------------------------------------------------------------
    per_date AS (
        SELECT
            dt."SKUKey", dt."LocationKey", dt.batch_date, dt.day_qty,
            r."BrandKey", r."CategoryKey", r."SubCategoryKey", r."ProductCodeKey",
            r."ColorKey", r."SizeKey", r."SupplierKey", r."DateKey",
            ins.transaction_id AS day_latest_transaction_id
        FROM date_totals dt
        JOIN inserted ins
            ON ins."SKUKey" = dt."SKUKey" AND ins."LocationKey" = dt."LocationKey"
           AND ins.row_no = dt.latest_row_no_for_day
        JOIN resolved r
            ON r."SKUKey" = dt."SKUKey" AND r."LocationKey" = dt."LocationKey"
           AND r.row_no = dt.latest_row_no_for_day
    ),

    -- ------------------------------------------------------------------
    -- BLOCK: prior_baseline
    -- The single existing stock_fact_master row (per SKU+Location) whose
    -- last_date is strictly BEFORE this batch's earliest date -- gives
    -- the starting current_qty to carry forward into this batch's dates.
    -- ------------------------------------------------------------------
    prior_baseline AS (
        SELECT DISTINCT ON (sfm."SKUKey", sfm."LocationKey")
            sfm."SKUKey", sfm."LocationKey", sfm.current_qty AS baseline_qty
        FROM shinde_shoes.stock_fact_master sfm
        JOIN (
            SELECT "SKUKey", "LocationKey", MIN(batch_date) AS earliest_date
            FROM per_date GROUP BY "SKUKey", "LocationKey"
        ) eb ON eb."SKUKey" = sfm."SKUKey" AND eb."LocationKey" = sfm."LocationKey"
        WHERE sfm.last_date < eb.earliest_date
        ORDER BY sfm."SKUKey", sfm."LocationKey", sfm.last_date DESC
    ),

    -- ------------------------------------------------------------------
    -- BLOCK: with_running
    -- Cumulative running stock across THIS batch's own dates, starting
    -- from prior_baseline (0 if this is the very first record ever for
    -- that SKU+Location).
    -- ------------------------------------------------------------------
    with_running AS (
        SELECT
            pd.*,
            COALESCE(pb.baseline_qty, 0)
                + SUM(pd.day_qty) OVER (
                      PARTITION BY pd."SKUKey", pd."LocationKey" ORDER BY pd.batch_date
                  ) AS running_current_qty
        FROM per_date pd
        LEFT JOIN prior_baseline pb ON pb."SKUKey" = pd."SKUKey" AND pb."LocationKey" = pd."LocationKey"
    ),

    -- ------------------------------------------------------------------
    -- BLOCK: stock_fact_upsert
    -- One row PER DATE. current_qty is always an absolute SET (the
    -- cumulative running balance through that date). as_of_purchases is
    -- additive on DO UPDATE (handles a same-date repeat call safely);
    -- as_of_inventory and as_of_sales are left OUT of the DO UPDATE SET
    -- list entirely so a Purchase load never touches those columns.
    -- ------------------------------------------------------------------
    stock_fact_upsert AS (
        INSERT INTO shinde_shoes.stock_fact_master
        (
            "SKUKey", "LocationKey", "BrandKey", "ProductCodeKey", "ColorKey",
            "SizeKey", "SupplierKey", "CategoryKey", "SubCategoryKey", "DateKey",
            current_qty, as_of_inventory, as_of_purchases, as_of_sales,
            last_date, last_transaction_id,
            created_by, last_updated_by
        )
        SELECT
            "SKUKey", "LocationKey", "BrandKey", "ProductCodeKey", "ColorKey",
            "SizeKey", "SupplierKey", "CategoryKey", "SubCategoryKey", "DateKey",
            running_current_qty,
            0, day_qty, 0,
            batch_date, day_latest_transaction_id,
            'load_' || p_load_id, 'load_' || p_load_id
        FROM with_running
        ON CONFLICT ("SKUKey", "LocationKey", last_date) DO UPDATE SET
            current_qty          = EXCLUDED.current_qty,
            as_of_purchases      = shinde_shoes.stock_fact_master.as_of_purchases + EXCLUDED.as_of_purchases,
            "BrandKey"           = EXCLUDED."BrandKey",
            "ProductCodeKey"     = EXCLUDED."ProductCodeKey",
            "ColorKey"           = EXCLUDED."ColorKey",
            "SizeKey"            = EXCLUDED."SizeKey",
            "SupplierKey"        = EXCLUDED."SupplierKey",
            "CategoryKey"        = EXCLUDED."CategoryKey",
            "SubCategoryKey"     = EXCLUDED."SubCategoryKey",
            "DateKey"            = EXCLUDED."DateKey",
            last_transaction_id  = EXCLUDED.last_transaction_id,
            last_updated_by      = EXCLUDED.last_updated_by
        RETURNING 1
    )

    -- ------------------------------------------------------------------
    -- FINAL PART OF STEP 2: read some counts back for the Step 3 summary.
    -- Changes no data.
    -- ------------------------------------------------------------------
    SELECT
        (SELECT COUNT(*) FROM attrs a
           WHERE EXISTS (SELECT 1 FROM shinde_shoes."DimProduct" dp WHERE dp."SKU" = a."SKU")),
        (SELECT COUNT(*) FROM attrs a
           WHERE EXISTS (SELECT 1 FROM new_products np WHERE np."SKU" = a."SKU")),
        (SELECT COUNT(*) FROM new_products),
        (SELECT COUNT(*) FROM attrs a
           WHERE NOT EXISTS (SELECT 1 FROM shinde_shoes."DimProduct" dp WHERE dp."SKU" = a."SKU")
             AND NOT EXISTS (SELECT 1 FROM new_products np WHERE np."SKU" = a."SKU")),
        (SELECT COUNT(*) FROM purchase_fact_upsert),
        (SELECT COUNT(*) FROM stock_fact_upsert)
    INTO v_existing_sku_rows, v_new_sku_rows, v_new_skus_created, v_unresolvable_rows,
         v_purchase_posted_rows, v_stock_posted_rows;

    -- ========================================================================
    -- STEP 3: Summary
    -- ========================================================================

    RAISE NOTICE
        'Purchase processing completed. Load ID: %, Total rows: %, Already in DimProduct: %, New-SKU rows (auto-created): % (% distinct new SKUs), Unresolvable (new SKU, missing required attribute -- skipped): %, purchase_fact_master rows posted/updated: %, stock_fact_master rows posted/updated: %',
        p_load_id, v_total_rows, v_existing_sku_rows, v_new_sku_rows, v_new_skus_created, v_unresolvable_rows, v_purchase_posted_rows, v_stock_posted_rows;

    PERFORM public.fn_proc_run_end(v_run_id, jsonb_build_object('total_rows', v_total_rows, 'new_skus', v_new_skus_created, 'skipped', v_unresolvable_rows, 'purchase_rows_posted', v_purchase_posted_rows, 'stock_rows_posted', v_stock_posted_rows));
END;
$procedure$
;


CREATE OR REPLACE PROCEDURE shinde_shoes.sp_load_sales_set()
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_run_id bigint;   -- public.proc_run_log
    v_max_rowno  integer;
    v_bad        text;
    v_grp        record;
    v_new_billno integer;
BEGIN
    v_run_id := public.fn_proc_run_start('shinde_shoes.sp_load_sales_set', NULL, NULL);
    SELECT COALESCE(MAX(row_no), 0) INTO v_max_rowno FROM shinde_shoes."FactSalesDetail";

    -- ── 1. Parse every staging row once ────────────────────────────────────
    DROP TABLE IF EXISTS pg_temp._sales_rows;
    CREATE TEMP TABLE _sales_rows ON COMMIT DROP AS
    SELECT s.*,
           shinde_shoes."ParseDate_dd_mm_yyyy"(s."BillDate")    AS map_date,       -- used for bill numbering
           shinde_shoes.parse_date_dd_mm_yyyy(s."BillDate")     AS bill_date,      -- used for DateFrKey
           shinde_shoes.parse_date_dd_mm_yyyy(s."LastPurDate")  AS last_pur_date
    FROM   shinde_shoes."stg-1" s;

    -- Bad rows stop the load (row numbers are the data rows of the uploaded file).
    SELECT string_agg(row_no::text, ', ' ORDER BY row_no) INTO v_bad
    FROM   (SELECT row_no FROM _sales_rows WHERE map_date IS NULL OR bill_date IS NULL ORDER BY row_no LIMIT 20) b;
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION 'Sales file has an invalid BillDate in row(s): %', v_bad;
    END IF;

    SELECT string_agg(row_no::text, ', ' ORDER BY row_no) INTO v_bad
    FROM   (SELECT row_no FROM _sales_rows WHERE "BillNo" IS NULL ORDER BY row_no LIMIT 20) b;
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION 'Sales file has an empty BillNo in row(s): %', v_bad;
    END IF;

    SELECT string_agg(row_no::text, ', ' ORDER BY row_no) INTO v_bad
    FROM   (SELECT row_no FROM _sales_rows WHERE "SKU" IS NULL OR trim("SKU") = '' ORDER BY row_no LIMIT 20) b;
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION 'Sales file has an empty SKU in row(s): %', v_bad;
    END IF;

    -- SKU must be 12 digits (catches Excel's "1.01E+11")
    CALL shinde_shoes.sp_check_sku_format('sales', NULL);

    SELECT string_agg(row_no::text, ', ' ORDER BY row_no) INTO v_bad
    FROM   (SELECT row_no FROM _sales_rows
            WHERE  NULLIF("Counter", '') IS NOT NULL AND "Counter" !~ '^\s*-?\d+(\.\d+)?\s*$'
            ORDER BY row_no LIMIT 20) b;
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION 'Sales file has a non-numeric Counter in row(s): %', v_bad;
    END IF;

    -- ── 2. Bill numbers (same rules as sp_batch_insert_dummy_to_stagging_to_dim) ──
    ALTER TABLE _sales_rows
        ADD COLUMN map_date_key integer,
        ADD COLUMN map_loc_key  integer,
        ADD COLUMN new_billno   integer;

    UPDATE _sales_rows r
    SET    map_date_key = COALESCE((SELECT dd."DateKey" FROM shinde_shoes."DimDate" dd
                                    WHERE dd."Fulldate" = r.map_date LIMIT 1), 0),
           map_loc_key  = COALESCE((SELECT dl."LocationKey" FROM shinde_shoes."DimLocation" dl
                                    WHERE dl."locationName" = r."LocationName" LIMIT 1), 0);

    -- A bill already loaded for the same original bill no + date + store keeps its number.
    UPDATE _sales_rows r
    SET    new_billno = (SELECT MIN(m."BillNo") FROM shinde_shoes."FactSalesMaster" m
                         WHERE  m."Og_BillNo"     = r."BillNo"
                           AND  m."DateFrKey"     = r.map_date_key
                           AND  m."LocationFrKey" = r.map_loc_key);

    -- New bills: one number per (original bill no, store), in file order, never reusing a
    -- number already in FactSalesMaster or already given out in this load.
    DROP TABLE IF EXISTS pg_temp._used_billnos;
    CREATE TEMP TABLE _used_billnos (billno integer PRIMARY KEY) ON COMMIT DROP;
    INSERT INTO _used_billnos SELECT DISTINCT new_billno FROM _sales_rows WHERE new_billno IS NOT NULL;

    DROP TABLE IF EXISTS pg_temp._bill_groups;
    CREATE TEMP TABLE _bill_groups (og_billno integer, map_loc_key integer, new_billno integer) ON COMMIT DROP;

    -- Groups are numbered in the order their first row appears in the file (the old
    -- row-by-row order), which decides who gets the "+1" when numbers clash.
    FOR v_grp IN
        SELECT "BillNo", map_loc_key,
               (array_agg("LocationName" ORDER BY row_no))[1] AS "LocationName",
               MIN(row_no) AS first_row
        FROM   _sales_rows
        WHERE  new_billno IS NULL
        GROUP  BY "BillNo", map_loc_key
        ORDER  BY first_row
    LOOP
        v_new_billno := v_grp."BillNo" + CASE
            WHEN v_grp."LocationName" = 'LT ROAD BRANCH'        THEN 990000
            WHEN v_grp."LocationName" = 'GORAI BRANCH'          THEN 790000
            WHEN v_grp."LocationName" = 'SHINDE SHOES (WOMENS)' THEN 590000
            WHEN v_grp."LocationName" = 'MAHARASTRA NAGAR'      THEN 390000
            ELSE 5000
        END;
        -- Smallest free number >= the candidate (same result as the old "+1 until free" loop).
        -- If the candidate is taken, jump straight past the run of taken numbers that starts
        -- at it, instead of testing one number at a time.
        IF EXISTS (SELECT 1 FROM shinde_shoes."FactSalesMaster" WHERE "BillNo" = v_new_billno)
           OR EXISTS (SELECT 1 FROM _used_billnos WHERE billno = v_new_billno)
        THEN
            SELECT t.n + 1 INTO v_new_billno
            FROM  (SELECT u.n, lead(u.n) OVER (ORDER BY u.n) AS next_n
                   FROM  (SELECT "BillNo" AS n FROM shinde_shoes."FactSalesMaster" WHERE "BillNo" >= v_new_billno
                          UNION ALL
                          SELECT billno FROM _used_billnos WHERE billno >= v_new_billno) u
                  ) t
            WHERE  t.next_n IS NULL OR t.next_n > t.n + 1
            ORDER  BY t.n
            LIMIT  1;
        END IF;
        INSERT INTO _used_billnos VALUES (v_new_billno);
        INSERT INTO _bill_groups  VALUES (v_grp."BillNo", v_grp.map_loc_key, v_new_billno);
    END LOOP;

    UPDATE _sales_rows r
    SET    new_billno = g.new_billno
    FROM   _bill_groups g
    WHERE  r.new_billno IS NULL
      AND  r."BillNo"    = g.og_billno
      AND  r.map_loc_key = g.map_loc_key;

    -- The old path groups by bill no + store only (not date); keep that, but process
    -- rows in the old order: new bill no, then file row.
    ALTER TABLE _sales_rows ADD COLUMN proc_order bigint;
    UPDATE _sales_rows r SET proc_order = o.n
    FROM  (SELECT row_no, row_number() OVER (ORDER BY new_billno, row_no) AS n FROM _sales_rows) o
    WHERE  o.row_no = r.row_no;

    -- Staging copy, as before (stg-2 is read by the reconciliation scripts).
    TRUNCATE shinde_shoes."stg-2";
    INSERT INTO shinde_shoes."stg-2" (
        "Og_BillNO", "BillNo", "BillDate", "Brand", "CategoryDesc", "ProductDesc", "ColorCode",
        "Size", "SKU", "TotalQty", "MRP", "SaleRate", "NetAmount", "MobileNo", "SalesMan1Name",
        "Supplier", "Time", "LocationName", "CreatedUser", "CategoryCode", "SubCategoryCode",
        "SubCategoryDesc", "ProductCode", "ColorDesc", "SizeRange", "BillDiscount",
        "TotalDiscountAmount", "TaxableAmount", "HSNCode", "HSNDesc", "TaxDesc", "TaxRate",
        "TaxAmount", "BillAmount", "Customer", "GSTIN", "BillComment", "Counter", "ModifiedUser",
        "DisplayStockDays", "LastPurDate", "row_no")
    SELECT "BillNo", new_billno, "BillDate", "Brand", "CategoryDesc", "ProductDesc", "ColorCode",
           "Size", "SKU", "TotalQty", "MRP", "SaleRate", "NetAmount", "MobileNo", "SalesMan1Name",
           "Supplier", "Time", "LocationName", "CreatedUser", "CategoryCode", "SubCategoryCode",
           "SubCategoryDesc", "ProductCode", "ColorDesc", "SizeRange", "BillDiscount",
           "TotalDiscountAmount", "TaxableAmount", "HSNCode", "HSNDesc", "TaxDesc", "TaxRate",
           "TaxAmount", "BillAmount", "Customer", "GSTIN", "BillComment", "Counter", "ModifiedUser",
           "DisplayStockDays", "LastPurDate", row_no + v_max_rowno
    FROM   _sales_rows
    ORDER  BY row_no;

    -- ── 3. Product dimensions (first value seen wins, like ON CONFLICT DO NOTHING) ──
    INSERT INTO shinde_shoes."DimBrand" ("BrandName")
    SELECT DISTINCT trim("Brand") FROM _sales_rows
    WHERE  "Brand" IS NOT NULL AND trim("Brand") <> '' AND "Brand" <> '0'
    ON CONFLICT ("BrandName") DO NOTHING;

    INSERT INTO shinde_shoes."DimCategory" ("CategoryName", "CategoryCode")
    SELECT DISTINCT ON (trim("CategoryDesc")) trim("CategoryDesc"), COALESCE(NULLIF(trim("CategoryCode"), ''), '0')
    FROM   _sales_rows
    WHERE  "CategoryDesc" IS NOT NULL AND trim("CategoryDesc") <> '' AND "CategoryDesc" <> '0'
      AND  "CategoryCode" IS NOT NULL AND trim("CategoryCode") <> '' AND "CategoryCode" <> '0'
    ORDER  BY trim("CategoryDesc"), proc_order
    ON CONFLICT ("CategoryName") DO NOTHING;

    ALTER TABLE _sales_rows
        ADD COLUMN brand_key integer, ADD COLUMN category_key integer, ADD COLUMN subcategory_key integer,
        ADD COLUMN productcode_key integer, ADD COLUMN colour_key integer, ADD COLUMN size_key integer,
        ADD COLUMN supplier_key integer, ADD COLUMN sku_key integer, ADD COLUMN customer_key integer,
        ADD COLUMN location_key integer, ADD COLUMN salesperson_key integer, ADD COLUMN date_key integer,
        ADD COLUMN time_key integer;

    UPDATE _sales_rows r SET
        brand_key = CASE WHEN r."Brand" IS NULL OR trim(r."Brand") = '' OR r."Brand" = '0' THEN 0
                         ELSE COALESCE((SELECT b."BrandKey" FROM shinde_shoes."DimBrand" b
                                        WHERE b."BrandName" = trim(r."Brand")), 0) END,
        category_key = CASE WHEN r."CategoryDesc" IS NULL OR trim(r."CategoryDesc") = '' OR r."CategoryDesc" = '0'
                              OR r."CategoryCode" IS NULL OR trim(r."CategoryCode") = '' OR r."CategoryCode" = '0' THEN 0
                         ELSE COALESCE((SELECT c."CategoryKey" FROM shinde_shoes."DimCategory" c
                                        WHERE c."CategoryName" = trim(r."CategoryDesc")), 0) END;

    INSERT INTO shinde_shoes."DimSubCategory" ("SubCategoryName", "SubCategoryCode", "CategoryKey")
    SELECT DISTINCT ON (trim("SubCategoryDesc")) trim("SubCategoryDesc"), COALESCE(NULLIF(trim("SubCategoryCode"), ''), '0'), category_key
    FROM   _sales_rows
    WHERE  "SubCategoryDesc" IS NOT NULL AND trim("SubCategoryDesc") <> '' AND "SubCategoryDesc" <> '0'
      AND  "SubCategoryCode" IS NOT NULL AND trim("SubCategoryCode") <> '' AND "SubCategoryCode" <> '0'
    ORDER  BY trim("SubCategoryDesc"), proc_order
    ON CONFLICT ("SubCategoryName") DO NOTHING;

    UPDATE _sales_rows r SET
        subcategory_key = CASE WHEN r."SubCategoryDesc" IS NULL OR trim(r."SubCategoryDesc") = '' OR r."SubCategoryDesc" = '0'
                                 OR r."SubCategoryCode" IS NULL OR trim(r."SubCategoryCode") = '' OR r."SubCategoryCode" = '0' THEN 0
                            ELSE COALESCE((SELECT s."SubCategoryKey" FROM shinde_shoes."DimSubCategory" s
                                           WHERE s."SubCategoryName" = trim(r."SubCategoryDesc")), 0) END;

    INSERT INTO shinde_shoes."DimProductCode" ("ProductCodeName", "ProdDescription", "SubCategoryKey")
    SELECT DISTINCT ON (trim("ProductCode")) trim("ProductCode"), COALESCE(NULLIF(trim("ProductDesc"), ''), '0'), subcategory_key
    FROM   _sales_rows
    WHERE  "ProductCode" IS NOT NULL AND trim("ProductCode") <> '' AND "ProductCode" <> '0'
      AND  "ProductDesc" IS NOT NULL AND trim("ProductDesc") <> '' AND "ProductDesc" <> '0'
    ORDER  BY trim("ProductCode"), proc_order
    ON CONFLICT DO NOTHING;

    INSERT INTO shinde_shoes."DimColour" ("ColourName", "ColourCode")
    SELECT DISTINCT ON (trim("ColorDesc")) trim("ColorDesc"), trim("ColorCode")
    FROM   _sales_rows
    WHERE  "ColorDesc" IS NOT NULL AND trim("ColorDesc") <> '' AND "ColorDesc" <> '0'
      AND  "ColorCode" IS NOT NULL AND trim("ColorCode") <> '' AND "ColorCode" <> '0'
    ORDER  BY trim("ColorDesc"), proc_order
    ON CONFLICT ("ColourName") DO NOTHING;

    -- Old call passed (SizeRange, Size) into (sizename, sizerange): kept as-is.
    INSERT INTO shinde_shoes."DimSize" ("SizeName", "SizeRange")
    SELECT DISTINCT ON (trim("SizeRange")) trim("SizeRange"), trim("Size")
    FROM   _sales_rows
    WHERE  "SizeRange" IS NOT NULL AND trim("SizeRange") <> '' AND "SizeRange" <> '0'
      AND  "Size" IS NOT NULL AND trim("Size") <> '' AND "Size" <> '0'
    ORDER  BY trim("SizeRange"), proc_order
    ON CONFLICT ("SizeName") DO NOTHING;

    INSERT INTO shinde_shoes."DimSupplier" ("SupplierName")
    SELECT DISTINCT trim("Supplier") FROM _sales_rows
    WHERE  "Supplier" IS NOT NULL AND trim("Supplier") <> '' AND "Supplier" <> '0'
    ON CONFLICT ("SupplierName") DO NOTHING;

    UPDATE _sales_rows r SET
        productcode_key = CASE WHEN r."ProductCode" IS NULL OR trim(r."ProductCode") = '' OR r."ProductCode" = '0'
                                 OR r."ProductDesc" IS NULL OR trim(r."ProductDesc") = '' OR r."ProductDesc" = '0' THEN 0
                            ELSE COALESCE((SELECT p."ProductCodeKey" FROM shinde_shoes."DimProductCode" p
                                           WHERE p."ProductCodeName" = trim(r."ProductCode")), 0) END,
        -- Colour / Size / Supplier: looked up by the untrimmed value, as before.
        colour_key = CASE WHEN r."ColorDesc" IS NULL OR trim(r."ColorDesc") = '' OR r."ColorDesc" = '0'
                            OR r."ColorCode" IS NULL OR trim(r."ColorCode") = '' OR r."ColorCode" = '0' THEN 0
                       ELSE COALESCE((SELECT c."ColourKey" FROM shinde_shoes."DimColour" c
                                      WHERE c."ColourName" = r."ColorDesc"), 0) END,
        size_key = CASE WHEN r."SizeRange" IS NULL OR trim(r."SizeRange") = '' OR r."SizeRange" = '0'
                          OR r."Size" IS NULL OR trim(r."Size") = '' OR r."Size" = '0' THEN 0
                     ELSE COALESCE((SELECT z."SizeKey" FROM shinde_shoes."DimSize" z
                                    WHERE z."SizeName" = r."SizeRange"), 0) END,
        supplier_key = CASE WHEN r."Supplier" IS NULL OR trim(r."Supplier") = '' OR r."Supplier" = '0' THEN 0
                         ELSE COALESCE((SELECT s."SupplierKey" FROM shinde_shoes."DimSupplier" s
                                        WHERE s."SupplierName" = r."Supplier"), 0) END;

    INSERT INTO shinde_shoes."DimProduct"
        ("BrandKey", "ProductCodeKey", "ColorKey", "SizeKey", "SupplierKey",
         "SKU", "ProductDesc", "CategoryDesc", "MRP", "SaleRate", "PurchaseDate")
    SELECT DISTINCT ON ("SKU")
           brand_key, productcode_key, colour_key, size_key, supplier_key,
           "SKU", "ProductDesc", "CategoryDesc", "MRP", "SaleRate", last_pur_date
    FROM   _sales_rows
    ORDER  BY "SKU", proc_order
    ON CONFLICT ("SKU") DO NOTHING;

    -- ── 4. Customer / store / salesperson (customer: last value seen wins) ──
    INSERT INTO shinde_shoes."DimCustomer" ("MobileNo", "Customer", "GSTIN")
    SELECT DISTINCT ON ("MobileNo")
           "MobileNo",
           COALESCE(NULLIF(trim("Customer"), ''), "MobileNo"::varchar),
           COALESCE(NULLIF(trim("GSTIN"), ''), '0')
    FROM   _sales_rows
    WHERE  "MobileNo" IS NOT NULL AND "MobileNo" <> 0
    ORDER  BY "MobileNo", proc_order DESC
    ON CONFLICT ("MobileNo") DO UPDATE
    SET    "Customer" = EXCLUDED."Customer",
           "GSTIN"    = EXCLUDED."GSTIN";

    INSERT INTO shinde_shoes."DimLocation" ("locationName")
    SELECT DISTINCT trim("LocationName") FROM _sales_rows
    WHERE  trim("LocationName") IS NOT NULL AND trim("LocationName") <> '' AND trim("LocationName") <> '0'
    ON CONFLICT ("locationName") DO NOTHING;

    INSERT INTO shinde_shoes."DimSalesPerson" ("SalesPersonName")
    SELECT DISTINCT trim("SalesMan1Name") FROM _sales_rows
    WHERE  trim("SalesMan1Name") IS NOT NULL AND trim("SalesMan1Name") <> '' AND trim("SalesMan1Name") <> '0'
    ON CONFLICT ("SalesPersonName") DO NOTHING;

    UPDATE _sales_rows r SET
        sku_key         = (SELECT p."SKUKey" FROM shinde_shoes."DimProduct" p WHERE p."SKU" = r."SKU"),
        customer_key    = CASE WHEN r."MobileNo" IS NULL OR r."MobileNo" = 0 THEN 0
                               ELSE COALESCE((SELECT c."CustomerKey" FROM shinde_shoes."DimCustomer" c
                                              WHERE c."MobileNo" = r."MobileNo"), 0) END,
        location_key    = CASE WHEN trim(r."LocationName") IS NULL OR trim(r."LocationName") IN ('', '0') THEN 0
                               ELSE COALESCE((SELECT l."LocationKey" FROM shinde_shoes."DimLocation" l
                                              WHERE l."locationName" = trim(r."LocationName")), 0) END,
        salesperson_key = CASE WHEN trim(r."SalesMan1Name") IS NULL OR trim(r."SalesMan1Name") IN ('', '0') THEN 0
                               ELSE COALESCE((SELECT s."SalesPersonKey" FROM shinde_shoes."DimSalesPerson" s
                                              WHERE s."SalesPersonName" = trim(r."SalesMan1Name")), 0) END,
        date_key        = COALESCE((SELECT d."DateKey" FROM shinde_shoes."DimDate" d
                                    WHERE d."Fulldate" = r.bill_date), 0),
        time_key        = CASE WHEN r."Time" IS NULL THEN 0
                               ELSE COALESCE((SELECT t."TimeKey" FROM shinde_shoes."DimTime" t
                                              WHERE t."Time" = make_time(extract(hour FROM r."Time")::int, 0, 0)), 0) END;

    -- ── 5. Bills: one row per new bill, taken from its first line ──────────
    INSERT INTO shinde_shoes."FactSalesMaster"
        ("DateFrKey", "TimeFrKey", "CustomerFrKey", "SalesPersonFrKey", "LocationFrKey",
         "BillNo", "BILLNetAmount", "BillTime", "BillComment", "BillCounter",
         "BillCreatedBy", "BillModifiedBy", "BILLNetAmountAsIs", "NewBillNo", "Og_BillNo")
    SELECT DISTINCT ON (new_billno)
           date_key, time_key, COALESCE(customer_key, 0), COALESCE(salesperson_key, 0), COALESCE(location_key, 0),
           new_billno,
           0,                                   -- set to the sum of the lines in step 7
           COALESCE("Time", '00:00:00'::time),
           COALESCE("BillComment", '0'),
           COALESCE(ROUND(NULLIF("Counter", '')::numeric)::int, 0),
           COALESCE("CreatedUser", '0'),
           COALESCE("ModifiedUser", '0'),
           COALESCE("BillAmount", 0),
           new_billno,
           COALESCE("BillNo", 0)
    FROM   _sales_rows
    ORDER  BY new_billno, proc_order
    ON CONFLICT ("BillNo") DO NOTHING;

    -- ── 6. Bill lines ──────────────────────────────────────────────────────
    -- Line numbers restart at 1 per bill, in file order. A bill that was already loaded
    -- would clash with its existing lines: stop with a clear message instead of skipping.
    SELECT string_agg(DISTINCT r."BillNo"::text, ', ') INTO v_bad
    FROM   _sales_rows r
    JOIN   shinde_shoes."FactSalesMaster" m ON m."BillNo" = r.new_billno
    WHERE  EXISTS (SELECT 1 FROM shinde_shoes."FactSalesDetail" d WHERE d."BillNoKey" = m."BillNoKey");
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION 'These bills were already loaded for the same date and store: %', v_bad;
    END IF;

    INSERT INTO shinde_shoes."FactSalesDetail"
        ("BillNoKey", "BillLineNo", "SKUKey", "SaleQty", "SKUMRP", "SKUSELLPRICE",
         "BillDiscount", "TotalDiscountAmount", "TaxableAmount", "TaxRate", "TaxAmount",
         "NetAmount", "DisplayStockDays", "LastPurDate", "BSaleStatus", "row_no", "Og_BillNo")
    SELECT m."BillNoKey",
           row_number() OVER (PARTITION BY r.new_billno ORDER BY r.row_no)::int,
           r.sku_key,
           COALESCE(r."TotalQty", 0),
           COALESCE(r."MRP", 0),
           COALESCE(r."SaleRate", 0),
           COALESCE(r."BillDiscount", 0),
           COALESCE(r."TotalDiscountAmount", 0),
           COALESCE(r."TaxableAmount", 0),
           COALESCE(r."TaxRate", 0),
           COALESCE(r."TaxAmount", 0),
           COALESCE(r."NetAmount", COALESCE(r."SaleRate", 0) * COALESCE(r."TotalQty", 0)),
           COALESCE(r."DisplayStockDays", 0),
           r.last_pur_date,
           TRUE,
           r.row_no + v_max_rowno,
           COALESCE(r."BillNo", 0)
    FROM   _sales_rows r
    JOIN   shinde_shoes."FactSalesMaster" m ON m."BillNo" = r.new_billno;

    -- ── 7. Bill amount = sum of its lines (fixes the old running-total bug) ──
    UPDATE shinde_shoes."FactSalesMaster" m
    SET    "BILLNetAmount" = d.total
    FROM  (SELECT "BillNoKey", SUM("NetAmount") AS total
           FROM   shinde_shoes."FactSalesDetail"
           WHERE  "BillNoKey" IN (SELECT m2."BillNoKey" FROM shinde_shoes."FactSalesMaster" m2
                                  WHERE m2."BillNo" IN (SELECT DISTINCT new_billno FROM _sales_rows))
           GROUP  BY "BillNoKey") d
    WHERE  m."BillNoKey" = d."BillNoKey"
      AND  m."BILLNetAmount" IS DISTINCT FROM d.total;
    PERFORM public.fn_proc_run_end(v_run_id, jsonb_build_object('rows', (SELECT count(*) FROM _sales_rows)));
END;
$procedure$
;


CREATE OR REPLACE PROCEDURE shinde_shoes.sp_process_sales_stock_impact()
 LANGUAGE plpgsql
AS $procedure$

DECLARE
    v_run_id bigint;   -- public.proc_run_log
    v_candidate_rows       integer := 0;
    v_skus_updated         integer := 0;
    v_rows_marked_posted   integer := 0;

BEGIN
    v_run_id := public.fn_proc_run_start('shinde_shoes.sp_process_sales_stock_impact', NULL, NULL);

    SELECT COUNT(*)
    INTO v_candidate_rows
    FROM shinde_shoes."FactSalesDetail" fsd
    WHERE fsd.posted_to_stock = false;

    IF v_candidate_rows = 0 THEN
        RAISE NOTICE 'Sales stock-impact processing: nothing to do -- no rows with posted_to_stock = false.';
        PERFORM public.fn_proc_run_end(v_run_id, jsonb_build_object('sale_lines', 0));
        RETURN;
    END IF;

    WITH

    candidates AS (
        SELECT
            fsd."BillNoKey",
            fsd."BillLineNo",
            fsd."SKUKey",
            fsd."SaleQty",
            fsd.row_no,
            fsm."DateFrKey",
            fsm."LocationFrKey" AS "LocationKey"
        FROM shinde_shoes."FactSalesDetail" fsd
        JOIN shinde_shoes."FactSalesMaster" fsm
            ON fsm."BillNoKey" = fsd."BillNoKey"
        WHERE fsd.posted_to_stock = false
    ),

    dated AS (
        SELECT
            c.*,
            dd."Fulldate" AS transaction_date
        FROM candidates c
        JOIN shinde_shoes."DimDate" dd
            ON dd."DateKey" = c."DateFrKey"
    ),

    inserted AS (
        INSERT INTO shinde_shoes.stock_transaction
        (
            "SKUKey", "LocationKey", transaction_date, movement_type,
            quantity, load_id, row_no, source_file_type, created_by
        )
        SELECT
            d."SKUKey", d."LocationKey", d.transaction_date, 'SALE',
            d."SaleQty", NULL, d.row_no, 'sales', 'sales_stock_impact'
        FROM dated d
        RETURNING transaction_id, "SKUKey", "LocationKey", quantity, transaction_date
    ),

    date_totals AS (
        SELECT "SKUKey", "LocationKey", transaction_date AS batch_date,
               SUM(quantity) AS day_sold_qty,
               MAX(transaction_id) AS day_latest_transaction_id
        FROM inserted
        GROUP BY "SKUKey", "LocationKey", transaction_date
    ),

    sku_attrs AS (
        SELECT DISTINCT
            dt."SKUKey",
            dp."BrandKey",
            dp."ProductCodeKey",
            dp."ColorKey",
            dp."SizeKey",
            dp."SupplierKey",
            sc."CategoryKey",
            pc."SubCategoryKey"
        FROM date_totals dt
        JOIN shinde_shoes."DimProduct" dp
            ON dp."SKUKey" = dt."SKUKey"
        LEFT JOIN shinde_shoes."DimProductCode" pc
            ON pc."ProductCodeKey" = dp."ProductCodeKey"
        LEFT JOIN shinde_shoes."DimSubCategory" sc
            ON sc."SubCategoryKey" = pc."SubCategoryKey"
    ),

    prior_baseline AS (
        SELECT DISTINCT ON (sfm."SKUKey", sfm."LocationKey")
            sfm."SKUKey", sfm."LocationKey", sfm.current_qty AS baseline_qty
        FROM shinde_shoes.stock_fact_master sfm
        JOIN (
            SELECT "SKUKey", "LocationKey", MIN(batch_date) AS earliest_date
            FROM date_totals GROUP BY "SKUKey", "LocationKey"
        ) eb ON eb."SKUKey" = sfm."SKUKey" AND eb."LocationKey" = sfm."LocationKey"
        WHERE sfm.last_date < eb.earliest_date
        ORDER BY sfm."SKUKey", sfm."LocationKey", sfm.last_date DESC
    ),

    with_running AS (
        SELECT
            dt.*,
            COALESCE(pb.baseline_qty, 0)
                - SUM(dt.day_sold_qty) OVER (PARTITION BY dt."SKUKey", dt."LocationKey" ORDER BY dt.batch_date)
                AS running_current_qty
        FROM date_totals dt
        LEFT JOIN prior_baseline pb ON pb."SKUKey" = dt."SKUKey" AND pb."LocationKey" = dt."LocationKey"
    ),

    fact_upsert AS (
        INSERT INTO shinde_shoes.stock_fact_master
        (
            "SKUKey", "LocationKey", current_qty, as_of_inventory, as_of_purchases, as_of_sales,
            last_date, last_transaction_id,
            "BrandKey", "ProductCodeKey", "ColorKey", "SizeKey", "SupplierKey",
            "CategoryKey", "SubCategoryKey",
            created_by, last_updated_by
        )
        SELECT
            wr."SKUKey", wr."LocationKey",
            wr.running_current_qty,
            0, 0, wr.day_sold_qty,
            wr.batch_date, wr.day_latest_transaction_id,
            sa."BrandKey", sa."ProductCodeKey", sa."ColorKey", sa."SizeKey", sa."SupplierKey",
            sa."CategoryKey", sa."SubCategoryKey",
            'sales_stock_impact', 'sales_stock_impact'
        FROM with_running wr
        JOIN sku_attrs sa ON sa."SKUKey" = wr."SKUKey"
        ON CONFLICT ("SKUKey", "LocationKey", last_date) DO UPDATE SET
            current_qty          = EXCLUDED.current_qty,
            as_of_sales          = shinde_shoes.stock_fact_master.as_of_sales + EXCLUDED.as_of_sales,
            last_transaction_id  = EXCLUDED.last_transaction_id,
            last_updated_by      = EXCLUDED.last_updated_by
        RETURNING 1
    ),

    marked AS (
        UPDATE shinde_shoes."FactSalesDetail" fsd
        SET posted_to_stock = true
        FROM candidates c
        WHERE fsd."BillNoKey" = c."BillNoKey"
          AND fsd."BillLineNo" = c."BillLineNo"
        RETURNING 1
    )

    SELECT
        (SELECT COUNT(DISTINCT "SKUKey") FROM date_totals),
        (SELECT COUNT(*) FROM marked)
    INTO v_skus_updated, v_rows_marked_posted;

    RAISE NOTICE
        'Sales stock-impact processing completed. Sale lines processed: %, distinct SKUs updated in stock_fact_master: %, FactSalesDetail rows marked posted_to_stock: %.',
        v_candidate_rows, v_skus_updated, v_rows_marked_posted;

    PERFORM public.fn_proc_run_end(v_run_id, jsonb_build_object('sale_lines', v_candidate_rows, 'skus', v_skus_updated, 'lines_posted', v_rows_marked_posted));
END;
$procedure$
;


CREATE OR REPLACE PROCEDURE shinde_shoes.sp_rebuild_stock_fact_master(IN p_from_transaction_id bigint DEFAULT NULL::bigint)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_run_id bigint;   -- public.proc_run_log
    v_pairs integer := 0;
    v_rows  integer := 0;
BEGIN
    v_run_id := public.fn_proc_run_start('shinde_shoes.sp_rebuild_stock_fact_master', NULL, jsonb_build_object('scope', CASE WHEN p_from_transaction_id IS NULL THEN 'all' ELSE 'from transaction ' || p_from_transaction_id END));
    DROP TABLE IF EXISTS _rebuild_pairs;
    CREATE TEMP TABLE _rebuild_pairs ON COMMIT DROP AS
    SELECT DISTINCT "SKUKey", "LocationKey"
    FROM shinde_shoes.stock_transaction
    WHERE p_from_transaction_id IS NULL OR transaction_id >= p_from_transaction_id;

    IF p_from_transaction_id IS NULL THEN
        -- also clear rows whose transactions are all gone
        INSERT INTO _rebuild_pairs
        SELECT "SKUKey", "LocationKey" FROM shinde_shoes.stock_fact_master
        EXCEPT
        SELECT "SKUKey", "LocationKey" FROM _rebuild_pairs;
    END IF;

    SELECT count(*) INTO v_pairs FROM _rebuild_pairs;
    IF v_pairs = 0 THEN
        PERFORM public.fn_proc_run_end(v_run_id, jsonb_build_object('pairs', 0));
        RETURN;
    END IF;

    DELETE FROM shinde_shoes.stock_fact_master f
    USING _rebuild_pairs p
    WHERE f."SKUKey" = p."SKUKey" AND f."LocationKey" = p."LocationKey";

    INSERT INTO shinde_shoes.stock_fact_master
    (
        "SKUKey", "LocationKey", "BrandKey", "ProductCodeKey", "ColorKey",
        "SizeKey", "SupplierKey", "CategoryKey", "SubCategoryKey", "DateKey",
        current_qty, as_of_inventory, as_of_purchases, as_of_sales,
        last_date, last_transaction_id, created_by, last_updated_by
    )
    WITH daily AS (
        SELECT
            t."SKUKey", t."LocationKey", t.transaction_date AS day,
            bool_or(t.movement_type = 'OPENING')                                   AS has_count,
            COALESCE(SUM(t.quantity) FILTER (WHERE t.movement_type = 'OPENING'), 0)  AS counted,
            COALESCE(SUM(t.quantity) FILTER (WHERE t.movement_type = 'PURCHASE'), 0) AS purchased,
            COALESCE(SUM(t.quantity) FILTER (WHERE t.movement_type = 'SALE'), 0)     AS sold,
            MAX(t.transaction_id)                                                   AS last_transaction_id
        FROM shinde_shoes.v_stock_effective_transaction t
        JOIN _rebuild_pairs p ON p."SKUKey" = t."SKUKey" AND p."LocationKey" = t."LocationKey"
        GROUP BY t."SKUKey", t."LocationKey", t.transaction_date
    ),
    -- each count starts a new segment; the running total restarts there.
    -- A count is the closing stock of its day, so that day's own purchases
    -- and sales are already inside it.
    segmented AS (
        SELECT d.*,
               COUNT(*) FILTER (WHERE d.has_count) OVER (
                   PARTITION BY d."SKUKey", d."LocationKey" ORDER BY d.day
               ) AS segment_no
        FROM daily d
    ),
    balanced AS (
        SELECT s.*,
               SUM(CASE WHEN s.has_count THEN s.counted ELSE s.purchased - s.sold END) OVER (
                   PARTITION BY s."SKUKey", s."LocationKey", s.segment_no ORDER BY s.day
               ) AS end_of_day_qty
        FROM segmented s
    )
    SELECT
        b."SKUKey", b."LocationKey", dp."BrandKey", dp."ProductCodeKey", dp."ColorKey",
        dp."SizeKey", dp."SupplierKey", sc."CategoryKey", pc."SubCategoryKey",
        COALESCE(dd."DateKey", 0),
        b.end_of_day_qty, b.counted, b.purchased, b.sold,
        b.day, b.last_transaction_id, 'stock_rebuild', 'stock_rebuild'
    FROM balanced b
    JOIN shinde_shoes."DimProduct" dp           ON dp."SKUKey" = b."SKUKey"
    LEFT JOIN shinde_shoes."DimProductCode" pc  ON pc."ProductCodeKey" = dp."ProductCodeKey"
    LEFT JOIN shinde_shoes."DimSubCategory" sc  ON sc."SubCategoryKey" = pc."SubCategoryKey"
    LEFT JOIN shinde_shoes."DimDate" dd         ON dd."Fulldate" = b.day;

    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RAISE NOTICE 'Stock balances rebuilt: % SKU+store pairs, % stock_fact_master rows.', v_pairs, v_rows;
    PERFORM public.fn_proc_run_end(v_run_id, jsonb_build_object('pairs', v_pairs, 'rows', v_rows));
END;
$procedure$
;


CREATE OR REPLACE PROCEDURE shinde_shoes.refresh_dimdate_offsets(IN p_as_of_date date)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_run_id bigint;   -- public.proc_run_log
BEGIN
    v_run_id := public.fn_proc_run_start('shinde_shoes.refresh_dimdate_offsets', NULL, jsonb_build_object('as_of_date', p_as_of_date));
    UPDATE "shinde_shoes"."DimDate" d
    SET
        -- Day Offset
        "DayOffset" =
            (d."Fulldate" - p_as_of_date),

        -- Month Offset
        "MonthOffset" =
            (
                (EXTRACT(YEAR FROM d."Fulldate") - EXTRACT(YEAR FROM p_as_of_date)) * 12
              + (EXTRACT(MONTH FROM d."Fulldate") - EXTRACT(MONTH FROM p_as_of_date))
            ),

        -- Quarter Offset
        "QuarterOffset" =
            (
                (EXTRACT(YEAR FROM d."Fulldate") - EXTRACT(YEAR FROM p_as_of_date)) * 4
              + (EXTRACT(QUARTER FROM d."Fulldate") - EXTRACT(QUARTER FROM p_as_of_date))
            ),

        -- Year Offset
        "YearOffset" =
            (EXTRACT(YEAR FROM d."Fulldate") - EXTRACT(YEAR FROM p_as_of_date));
    PERFORM public.fn_proc_run_end(v_run_id, NULL);
END;
$procedure$
;


CREATE OR REPLACE PROCEDURE shinde_shoes.refresh_all_mvs()
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_run_id bigint;   -- public.proc_run_log
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
    v_run_id := public.fn_proc_run_start('shinde_shoes.refresh_all_mvs', NULL, NULL);
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
    PERFORM public.fn_proc_run_end(v_run_id, jsonb_build_object('views', cardinality(v_done)));
END;
$procedure$
;


COMMIT;
