-- 007_stock_count_snapshots.sql
-- Inventory files become STOCK COUNTS (weekly / monthly stock reports).
--
-- Before: every inventory row was ADDED to stock, dated by its purchase BillDate, so
--         uploading a newer stock report added the stock a second time.
-- After:  an inventory file SETS the stock of every SKU + store in it, as of the file's
--         stock date. Purchases and Sales dated on or after that date move it from there.
--
-- Rules
--   * Stock date = the date the stock report was taken, read from the file itself:
--     BillDate + StockDays (StockDays = days in stock up to the report date). The most
--     common value is used. If no row has both, the upload day is used.
--   * The count is the stock at the START of the stock date, so that day's purchases and
--     sales are applied on top of it.
--   * A SKU that had stock in a store but is missing from that store's new file is set to 0
--     (a stock report only lists items that are in stock).
--   * Uploading a file for a stock date that already has a count REPLACES that count
--     (same file twice = no change).
--   * stock_transaction rows with movement_type 'OPENING' now mean "stock count".
--
-- New objects
--   shinde_shoes.stock_count_history          one row per SKU + store + stock date: counted qty,
--                                             what the system expected, the difference
--   shinde_shoes.sp_rebuild_stock_fact_master recomputes stock_fact_master from stock_transaction
--   shinde_shoes.fn_stock_expected_qty        latest stock per SKU + store, from the ledger
--   shinde_shoes.v_stock_current              current stock per SKU + store (one row each)
-- Changed
--   sp_process_stock_load, sp_process_upload (rebuilds balances after every upload),
--   fn_check_stock_fact_master_reconciliation, fn_get_load_stock_impact,
--   sp_reset_fact_and_transaction_tables (also clears stock_count_history)
--
-- The existing inventory load 305 is re-posted as a count dated by its own file.
-- stock_transaction and stock_fact_master are saved first in backup_*_007 tables and the old
-- procedure bodies are in db/backups/stock_before_007/.
-- Rollback: 007_stock_count_snapshots_rollback.sql

BEGIN;

CREATE TABLE shinde_shoes.backup_stock_transaction_007 AS SELECT * FROM shinde_shoes.stock_transaction;
CREATE TABLE shinde_shoes.backup_stock_fact_master_007 AS SELECT * FROM shinde_shoes.stock_fact_master;


-- ============================================================================
-- Stock count history
-- ============================================================================
CREATE TABLE shinde_shoes.stock_count_history (
    history_id        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    "SKUKey"          integer        NOT NULL REFERENCES shinde_shoes."DimProduct"("SKUKey"),
    "SKU"             varchar(100)   NOT NULL,
    "ProductCode"     varchar(255),
    "LocationKey"     integer        NOT NULL REFERENCES shinde_shoes."DimLocation"("LocationKey"),
    stock_date        date           NOT NULL,
    counted_qty       numeric(18,3)  NOT NULL,   -- qty in the stock file (0 = not in the file)
    system_qty_before numeric(18,3)  NOT NULL,   -- stock the system expected at the start of stock_date
    qty_difference    numeric(18,3)  NOT NULL,   -- counted_qty - system_qty_before
    in_file           boolean        NOT NULL DEFAULT true,
    load_id           integer        NOT NULL,
    created_at        timestamp      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by        text,
    updated_at        timestamp      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ux_stock_count_history UNIQUE ("SKUKey", "LocationKey", stock_date)
);
CREATE INDEX ix_stock_count_history_date    ON shinde_shoes.stock_count_history (stock_date);
CREATE INDEX ix_stock_count_history_sku     ON shinde_shoes.stock_count_history ("SKU");
CREATE INDEX ix_stock_count_history_load_id ON shinde_shoes.stock_count_history (load_id);


-- ============================================================================
-- Rebuild stock_fact_master from stock_transaction
--   p_from_transaction_id NULL -> every SKU + store
--   otherwise                  -> only SKU + stores with a transaction id >= it
-- One row per SKU + store + day with a movement. current_qty = stock at the end of that day:
-- the latest count on or before the day, plus purchases, minus sales since that count.
-- ============================================================================
CREATE OR REPLACE PROCEDURE shinde_shoes.sp_rebuild_stock_fact_master(IN p_from_transaction_id bigint DEFAULT NULL)
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
        FROM shinde_shoes.stock_transaction t
        JOIN _rebuild_pairs p ON p."SKUKey" = t."SKUKey" AND p."LocationKey" = t."LocationKey"
        GROUP BY t."SKUKey", t."LocationKey", t.transaction_date
    ),
    -- each count starts a new segment; the running total restarts there
    segmented AS (
        SELECT d.*,
               COUNT(*) FILTER (WHERE d.has_count) OVER (
                   PARTITION BY d."SKUKey", d."LocationKey" ORDER BY d.day
               ) AS segment_no
        FROM daily d
    ),
    balanced AS (
        SELECT s.*,
               SUM(s.counted + s.purchased - s.sold) OVER (
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
$procedure$;


-- ============================================================================
-- Inventory load = stock count
-- ============================================================================
CREATE OR REPLACE PROCEDURE shinde_shoes.sp_process_stock_load(IN p_load_id integer)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_total_rows       integer := 0;
    v_stock_date       date;
    v_new_skus_created integer := 0;
    v_unresolvable     integer := 0;
    v_counted          integer := 0;
    v_zeroed           integer := 0;
    v_replaced         integer := 0;
BEGIN
    SELECT COUNT(*) INTO v_total_rows
    FROM shinde_shoes.stg_stock_2
    WHERE load_id = p_load_id;

    IF v_total_rows = 0 THEN
        RAISE EXCEPTION 'No validated stock records found for load_id % in stg_stock_2', p_load_id;
    END IF;

    -- ------------------------------------------------------------------
    -- 1. Stock date of this file
    -- ------------------------------------------------------------------
    SELECT mode() WITHIN GROUP (ORDER BY "BillDate" + "StockDays")
    INTO v_stock_date
    FROM shinde_shoes.stg_stock_2
    WHERE load_id = p_load_id
      AND "BillDate" IS NOT NULL
      AND "StockDays" IS NOT NULL;

    v_stock_date := COALESCE(v_stock_date, CURRENT_DATE);

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
        MAX(a.created_by) AS created_by,
        true              AS in_file
    FROM _stock_attrs a
    JOIN shinde_shoes."DimProduct" dp ON dp."SKU" = a."SKU"
    WHERE a."LocationKey" IS NOT NULL
    GROUP BY dp."SKUKey", a."LocationKey";

    SELECT COUNT(*) INTO v_counted FROM _stock_count;

    IF v_counted = 0 THEN
        RAISE EXCEPTION 'Stock file for load_id % has no rows with a known store and SKU.', p_load_id;
    END IF;

    -- ------------------------------------------------------------------
    -- 4. A new count for the same stock date replaces the old one
    -- ------------------------------------------------------------------
    DROP TABLE IF EXISTS _replaced_counts;
    CREATE TEMP TABLE _replaced_counts ON COMMIT DROP AS
    SELECT t.transaction_id, t."SKUKey", t."LocationKey"
    FROM shinde_shoes.stock_transaction t
    WHERE t.movement_type = 'OPENING'
      AND t.transaction_date = v_stock_date
      AND t."LocationKey" IN (SELECT DISTINCT "LocationKey" FROM _stock_count);

    SELECT COUNT(DISTINCT ("SKUKey", "LocationKey")) INTO v_replaced FROM _replaced_counts;

    UPDATE shinde_shoes.stock_fact_master
    SET    last_transaction_id = NULL
    WHERE  last_transaction_id IN (SELECT transaction_id FROM _replaced_counts);

    DELETE FROM shinde_shoes.stock_transaction
    WHERE transaction_id IN (SELECT transaction_id FROM _replaced_counts);

    -- ------------------------------------------------------------------
    -- 5. Stock the system expected at the start of the stock date
    --    = latest earlier count + purchases - sales since that count
    -- ------------------------------------------------------------------
    DROP TABLE IF EXISTS _stock_before;
    CREATE TEMP TABLE _stock_before ON COMMIT DROP AS
    WITH last_count AS (
        SELECT "SKUKey", "LocationKey", MAX(transaction_date) AS count_date
        FROM shinde_shoes.stock_transaction
        WHERE movement_type = 'OPENING'
          AND transaction_date < v_stock_date
          AND "LocationKey" IN (SELECT DISTINCT "LocationKey" FROM _stock_count)
        GROUP BY "SKUKey", "LocationKey"
    )
    SELECT
        t."SKUKey", t."LocationKey",
        SUM(CASE WHEN t.movement_type = 'SALE' THEN -t.quantity ELSE t.quantity END) AS qty_before
    FROM shinde_shoes.stock_transaction t
    LEFT JOIN last_count lc ON lc."SKUKey" = t."SKUKey" AND lc."LocationKey" = t."LocationKey"
    WHERE t."LocationKey" IN (SELECT DISTINCT "LocationKey" FROM _stock_count)
      AND t.transaction_date < v_stock_date
      AND (lc.count_date IS NULL OR t.transaction_date >= lc.count_date)
    GROUP BY t."SKUKey", t."LocationKey";

    -- ------------------------------------------------------------------
    -- 6. Missing from the file but in stock (or counted before on this
    --    date) -> count of 0
    -- ------------------------------------------------------------------
    INSERT INTO _stock_count ("SKUKey", "LocationKey", counted_qty, row_no, created_by, in_file)
    SELECT m."SKUKey", m."LocationKey", 0, NULL, NULL, false
    FROM (
        SELECT "SKUKey", "LocationKey" FROM _stock_before WHERE qty_before <> 0
        UNION
        SELECT "SKUKey", "LocationKey" FROM _replaced_counts
    ) m
    WHERE NOT EXISTS (
        SELECT 1 FROM _stock_count c
        WHERE c."SKUKey" = m."SKUKey" AND c."LocationKey" = m."LocationKey"
    );

    GET DIAGNOSTICS v_zeroed = ROW_COUNT;

    -- ------------------------------------------------------------------
    -- 7. Post the counts and record the history
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
        counted_qty, system_qty_before, qty_difference, in_file, load_id, created_by
    )
    SELECT
        c."SKUKey", dp."SKU", pc."ProductCodeName", c."LocationKey", v_stock_date,
        c.counted_qty,
        COALESCE(b.qty_before, 0),
        c.counted_qty - COALESCE(b.qty_before, 0),
        c.in_file, p_load_id, c.created_by
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
        in_file           = EXCLUDED.in_file,
        load_id           = EXCLUDED.load_id,
        created_by        = EXCLUDED.created_by,
        updated_at        = CURRENT_TIMESTAMP;

    RAISE NOTICE
        'Stock count posted. Load ID: %, stock date: %, file rows: %, SKU+store counted: %, set to 0 (not in file): %, replaced earlier count for same date: %, new SKUs created: %, rows skipped (unknown store or SKU): %',
        p_load_id, v_stock_date, v_total_rows, v_counted, v_zeroed, v_replaced, v_new_skus_created, v_unresolvable;
END;
$procedure$;


-- ============================================================================
-- Dispatcher: after any upload, rebuild the balances it touched
-- ============================================================================
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
            CALL shinde_shoes.sp_validate_stock_load(p_load_id);
            CALL shinde_shoes.sp_process_stock_load(p_load_id);

        WHEN 'purchase' THEN
            IF p_load_id IS NULL THEN
                RAISE EXCEPTION
                    'p_load_id is required for file_type = ''purchase''.';
            END IF;
            RAISE NOTICE 'sp_process_upload: running PURCHASE chain for load_id %', p_load_id;
            CALL shinde_shoes.sp_validate_purchase_load(p_load_id);
            CALL shinde_shoes.sp_process_purchase_load(p_load_id);

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
    CALL shinde_shoes.sp_rebuild_stock_fact_master(v_from_transaction_id);

    RAISE NOTICE
        'sp_process_upload: % chain completed. Check: SELECT * FROM shinde_shoes.fn_check_stock_fact_master_reconciliation();',
        upper(p_file_type);

END;
$procedure$;


-- ============================================================================
-- Expected stock from the ledger (count semantics) + checks that use it
-- ============================================================================
CREATE OR REPLACE FUNCTION shinde_shoes.fn_stock_expected_qty()
 RETURNS TABLE(sku_key integer, location_key integer, expected_qty numeric)
 LANGUAGE sql
 STABLE
AS $function$
    WITH last_count AS (
        SELECT "SKUKey", "LocationKey", MAX(transaction_date) AS count_date
        FROM shinde_shoes.stock_transaction
        WHERE movement_type = 'OPENING'
        GROUP BY "SKUKey", "LocationKey"
    )
    SELECT
        t."SKUKey", t."LocationKey",
        SUM(CASE WHEN t.movement_type = 'SALE' THEN -t.quantity ELSE t.quantity END)
    FROM shinde_shoes.stock_transaction t
    LEFT JOIN last_count lc ON lc."SKUKey" = t."SKUKey" AND lc."LocationKey" = t."LocationKey"
    WHERE lc.count_date IS NULL OR t.transaction_date >= lc.count_date
    GROUP BY t."SKUKey", t."LocationKey";
$function$;

CREATE OR REPLACE FUNCTION shinde_shoes.fn_check_stock_fact_master_reconciliation()
 RETURNS TABLE("SKUKey" integer, "SKU" character varying, "LocationKey" integer, stored_current_qty numeric, computed_from_ledger numeric, mismatch numeric)
 LANGUAGE sql
 STABLE
AS $function$
    WITH latest_sfm AS (
        SELECT DISTINCT ON ("SKUKey", "LocationKey")
            "SKUKey", "LocationKey", current_qty
        FROM shinde_shoes.stock_fact_master
        ORDER BY "SKUKey", "LocationKey", last_date DESC
    )
    SELECT
        sfm."SKUKey",
        dp."SKU",
        sfm."LocationKey",
        sfm.current_qty                                AS stored_current_qty,
        COALESCE(e.expected_qty, 0)                    AS computed_from_ledger,
        sfm.current_qty - COALESCE(e.expected_qty, 0)  AS mismatch
    FROM latest_sfm sfm
    JOIN shinde_shoes."DimProduct" dp ON dp."SKUKey" = sfm."SKUKey"
    LEFT JOIN shinde_shoes.fn_stock_expected_qty() e
        ON e.sku_key = sfm."SKUKey" AND e.location_key = sfm."LocationKey"
    WHERE sfm.current_qty <> COALESCE(e.expected_qty, 0);
$function$;

CREATE OR REPLACE FUNCTION shinde_shoes.fn_get_load_stock_impact(p_load_id integer)
 RETURNS TABLE("SKU" character varying, "LocationKey" integer, movement_type character varying, qty_posted_by_this_load numeric, current_qty_now numeric, computed_qty_from_full_ledger numeric, reconciliation_status text)
 LANGUAGE sql
 STABLE
AS $function$
    WITH latest_sfm AS (
        SELECT DISTINCT ON ("SKUKey", "LocationKey")
            "SKUKey", "LocationKey", current_qty
        FROM shinde_shoes.stock_fact_master
        ORDER BY "SKUKey", "LocationKey", last_date DESC
    )
    SELECT
        dp."SKU",
        st."LocationKey",
        st.movement_type,
        SUM(st.quantity)   AS qty_posted_by_this_load,
        sfm.current_qty    AS current_qty_now,
        e.expected_qty     AS computed_qty_from_full_ledger,
        CASE
            WHEN sfm.current_qty = e.expected_qty THEN 'OK'
            ELSE 'MISMATCH'
        END                AS reconciliation_status
    FROM shinde_shoes.stock_transaction st
    JOIN shinde_shoes."DimProduct" dp
        ON dp."SKUKey" = st."SKUKey"
    LEFT JOIN latest_sfm sfm
        ON sfm."SKUKey" = st."SKUKey" AND sfm."LocationKey" = st."LocationKey"
    LEFT JOIN shinde_shoes.fn_stock_expected_qty() e
        ON e.sku_key = st."SKUKey" AND e.location_key = st."LocationKey"
    WHERE st.load_id = p_load_id
    GROUP BY dp."SKU", st."LocationKey", st.movement_type,
             sfm.current_qty, e.expected_qty
    ORDER BY dp."SKU", st."LocationKey";
$function$;


-- ============================================================================
-- Current stock: one row per SKU + store
-- ============================================================================
CREATE OR REPLACE VIEW shinde_shoes.v_stock_current AS
SELECT DISTINCT ON (f."SKUKey", f."LocationKey")
    dp."SKU",
    pc."ProductCodeName" AS "ProductCode",
    l."locationName"     AS "Location",
    f.current_qty,
    f.last_date          AS last_movement_date,
    f."SKUKey",
    f."LocationKey"
FROM shinde_shoes.stock_fact_master f
JOIN shinde_shoes."DimProduct" dp          ON dp."SKUKey" = f."SKUKey"
JOIN shinde_shoes."DimLocation" l          ON l."LocationKey" = f."LocationKey"
LEFT JOIN shinde_shoes."DimProductCode" pc ON pc."ProductCodeKey" = dp."ProductCodeKey"
ORDER BY f."SKUKey", f."LocationKey", f.last_date DESC;


-- ============================================================================
-- Reset also clears the count history
-- ============================================================================
CREATE OR REPLACE PROCEDURE shinde_shoes.sp_reset_fact_and_transaction_tables(IN p_confirm text)
 LANGUAGE plpgsql
AS $procedure$
BEGIN
    IF p_confirm IS DISTINCT FROM 'RESET' THEN
        RAISE EXCEPTION
            'Refusing to run: this TRUNCATEs stock_transaction, stock_fact_master, purchase_fact_master and stock_count_history -- every current stock position, purchase total and stock count will be lost. To proceed, call with the exact confirmation text: CALL shinde_shoes.sp_reset_fact_and_transaction_tables(''RESET'');';
    END IF;
    -- Tables with foreign keys to stock_transaction must be truncated in the
    -- same statement. RESTART IDENTITY resets the transaction_id sequence.
    TRUNCATE TABLE
        shinde_shoes.stock_transaction,
        shinde_shoes.stock_fact_master,
        shinde_shoes.purchase_fact_master,
        shinde_shoes.stock_count_history
    RESTART IDENTITY;
    RAISE NOTICE
        'stock_transaction, stock_fact_master, purchase_fact_master and stock_count_history are now empty (transaction_id sequence reset). stg_stock_2/stg_purchase_2/backup tables and every Dim table (including DimProduct) were left untouched -- re-run sp_process_stock_load(<load_id>) / sp_process_purchase_load(<load_id>), then CALL sp_rebuild_stock_fact_master().';
END;
$procedure$;


-- ============================================================================
-- Re-post the existing inventory load 305 as a stock count
-- ============================================================================
UPDATE shinde_shoes.stock_fact_master
SET    last_transaction_id = NULL
WHERE  last_transaction_id IN (SELECT transaction_id FROM shinde_shoes.stock_transaction
                               WHERE load_id = 305 AND source_file_type = 'inventory');

DELETE FROM shinde_shoes.stock_transaction
WHERE  load_id = 305 AND source_file_type = 'inventory';

CALL shinde_shoes.sp_process_stock_load(305);
CALL shinde_shoes.sp_rebuild_stock_fact_master(NULL);

COMMIT;

-- Checks
-- SELECT count(*) FROM shinde_shoes.fn_check_stock_fact_master_reconciliation();   -- expect 0
-- SELECT stock_date, count(*), sum(counted_qty) FROM shinde_shoes.stock_count_history GROUP BY 1;
-- SELECT * FROM shinde_shoes.v_stock_current WHERE "SKU" = '101280373306';
