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
$procedure$
;
