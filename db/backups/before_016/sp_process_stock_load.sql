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
