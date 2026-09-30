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
