-- 013_stock_date_from_file_name.sql
-- Two changes to how stock is calculated:
--
-- 1. Stock date from the file name
--    Stock files must be named  shindeshoes_inventory_DD_MM_YYYY.xlsx  (or .csv), e.g.
--    shindeshoes_inventory_14_09_2026.xlsx. The name must START with "shindeshoes_inventory"
--    (that is how the upload recognises a stock file). DD_MM_YYYY = the day the stock was
--    counted; the file is that day's CLOSING stock. An invalid date or a date after the
--    upload day fails the upload. No date in the name -> the upload date (as before).
--
-- 2. Each store's stock starts at its first stock file
--    New view v_stock_effective_transaction = the movements that count for stock:
--    every stock count, plus purchases/sales dated AFTER the store's first stock count.
--    Earlier purchases and sales stay in the database (reports are unchanged) but do not
--    change stock. A store with no stock file yet has no stock.
--    A stock count is the closing stock of its day, so purchases/sales on the count day
--    itself are inside it; only later days move the stock.
--
-- Changed: sp_rebuild_stock_fact_master, sp_process_stock_load, fn_stock_expected_qty,
-- sp_process_upload (a stock file rebuilds all balances). Old bodies: db/backups/before_013/.
-- The stock tables are empty after 012, so nothing needs re-posting.
-- Rollback: 013_stock_date_from_file_name_rollback.sql

BEGIN;

CREATE OR REPLACE VIEW shinde_shoes.v_stock_effective_transaction AS
WITH store_start AS (
    SELECT "LocationKey", MIN(transaction_date) AS first_count_date
    FROM shinde_shoes.stock_transaction
    WHERE movement_type = 'OPENING'
    GROUP BY "LocationKey"
)
SELECT t.*
FROM shinde_shoes.stock_transaction t
JOIN store_start s ON s."LocationKey" = t."LocationKey"
WHERE t.movement_type = 'OPENING'
   OR t.transaction_date > s.first_count_date;

CREATE OR REPLACE PROCEDURE shinde_shoes.sp_rebuild_stock_fact_master(IN p_from_transaction_id bigint DEFAULT NULL::bigint)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_pairs integer := 0;
    v_rows  integer := 0;
BEGIN
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
END;
$procedure$
;


CREATE OR REPLACE PROCEDURE shinde_shoes.sp_process_stock_load(IN p_load_id integer)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
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
END;
$procedure$
;


CREATE OR REPLACE FUNCTION shinde_shoes.fn_stock_expected_qty()
 RETURNS TABLE(sku_key integer, location_key integer, expected_qty numeric)
 LANGUAGE sql
 STABLE
AS $function$
    WITH last_count AS (
        SELECT "SKUKey", "LocationKey", MAX(transaction_date) AS count_date
        FROM shinde_shoes.v_stock_effective_transaction
        WHERE movement_type = 'OPENING'
        GROUP BY "SKUKey", "LocationKey"
    )
    SELECT
        t."SKUKey", t."LocationKey",
        SUM(CASE WHEN t.movement_type = 'SALE' THEN -t.quantity ELSE t.quantity END)
    FROM shinde_shoes.v_stock_effective_transaction t
    LEFT JOIN last_count lc ON lc."SKUKey" = t."SKUKey" AND lc."LocationKey" = t."LocationKey"
    WHERE lc.count_date IS NULL
       OR t.transaction_date > lc.count_date
       OR (t.movement_type = 'OPENING' AND t.transaction_date = lc.count_date)
    GROUP BY t."SKUKey", t."LocationKey";
$function$
;


CREATE OR REPLACE PROCEDURE shinde_shoes.sp_process_upload(IN p_load_id integer, IN p_file_type text)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_from_transaction_id bigint;
BEGIN

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

END;
$procedure$
;


-- Recalculate with the new rules (no-op while the stock tables are empty)
CALL shinde_shoes.sp_rebuild_stock_fact_master(NULL);

COMMIT;
