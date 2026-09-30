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
