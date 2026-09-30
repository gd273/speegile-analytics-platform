-- Rollback for 007_stock_count_snapshots.sql: restores the old additive inventory logic,
-- the old procedure bodies (copied from db/backups/stock_before_007/) and the
-- stock_transaction / stock_fact_master rows exactly as they were before 007.

BEGIN;

-- Data: back to the saved copies. purchase_fact_master points at purchase transactions,
-- which 007 never deleted, so their ids are still there.
DELETE FROM shinde_shoes.stock_fact_master;
DELETE FROM shinde_shoes.stock_transaction t
WHERE NOT EXISTS (SELECT 1 FROM shinde_shoes.backup_stock_transaction_007 b
                  WHERE b.transaction_id = t.transaction_id);
INSERT INTO shinde_shoes.stock_transaction OVERRIDING SYSTEM VALUE
SELECT b.* FROM shinde_shoes.backup_stock_transaction_007 b
WHERE NOT EXISTS (SELECT 1 FROM shinde_shoes.stock_transaction t
                  WHERE t.transaction_id = b.transaction_id);
INSERT INTO shinde_shoes.stock_fact_master SELECT * FROM shinde_shoes.backup_stock_fact_master_007;

DROP VIEW      shinde_shoes.v_stock_current;
DROP TABLE     shinde_shoes.stock_count_history;

-- Old procedure bodies

CREATE OR REPLACE PROCEDURE shinde_shoes.sp_process_stock_load(IN p_load_id integer)
 LANGUAGE plpgsql
AS $procedure$

DECLARE
    v_total_rows         integer := 0;
    v_existing_sku_rows  integer := 0;
    v_new_sku_rows       integer := 0;
    v_new_skus_created   integer := 0;
    v_unresolvable_rows  integer := 0;
    v_posted_rows        integer := 0;

BEGIN

    SELECT COUNT(*)
    INTO v_total_rows
    FROM shinde_shoes.stg_stock_2
    WHERE load_id = p_load_id;

    IF v_total_rows = 0 THEN
        RAISE EXCEPTION
            'No validated stock records found for load_id % in stg_stock_2',
            p_load_id;
    END IF;

    WITH

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
            COALESCE(i."SellPrice", 0) AS "SaleRate"

        FROM shinde_shoes.stg_stock_2 i

        CROSS JOIN LATERAL (
            SELECT NULLIF(
                shinde_shoes."Fn_Validate_Location"(TRIM(i."BranchName"), i."SKU", NULL::integer), 0
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
                    TRIM(i."CategoryDesc"), TRIM(i."Category"), i."SKU"
                ), 0
            ) AS "CategoryKey"
        ) category_lookup

        CROSS JOIN LATERAL (
            SELECT NULLIF(
                shinde_shoes."Fn_Validate_SubCategory"(
                    category_lookup."CategoryKey", TRIM(i."Subcategory"), TRIM(i."SubcategoryDesc"), i."SKU"
                ), 0
            ) AS "SubCategoryKey"
        ) subcategory_lookup

        CROSS JOIN LATERAL (
            SELECT NULLIF(
                shinde_shoes."Fn_Validate_ProductCode"(
                    subcategory_lookup."SubCategoryKey", TRIM(i."Product"), TRIM(i."ProductDesc"), i."SKU"
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
                    TRIM(i."SizeDesc"), TRIM(i."Size"), i."SKU"
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

    new_sku_candidates AS (
        SELECT DISTINCT ON (a."SKU")
            a."SKU", a."BrandKey", a."ProductCodeKey", a."ColorKey",
            a."SizeKey", a."SupplierKey", a."ProductDesc", a."CategoryDesc",
            a."MRP", a."SaleRate"
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

    new_products AS (
        INSERT INTO shinde_shoes."DimProduct"
        (
            "BrandKey", "ProductCodeKey", "ColorKey", "SizeKey", "SupplierKey",
            "SKU", "ProductDesc", "CategoryDesc", "MRP", "SaleRate"
        )
        SELECT
            "BrandKey", "ProductCodeKey", "ColorKey", "SizeKey", "SupplierKey",
            "SKU", "ProductDesc", "CategoryDesc", "MRP", "SaleRate"
        FROM new_sku_candidates
        ON CONFLICT ("SKU") DO NOTHING
        RETURNING "SKUKey", "SKU"
    ),

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

    inserted AS (
        INSERT INTO shinde_shoes.stock_transaction
        (
            "SKUKey", "LocationKey", transaction_date, movement_type,
            quantity, load_id, row_no, source_file_type, created_by
        )
        SELECT
            r."SKUKey", r."LocationKey", r."BillDate", 'OPENING',
            r."Qty", r.load_id, r.row_no, 'inventory', r.created_by
        FROM resolved r
        WHERE r."LocationKey" IS NOT NULL
        ON CONFLICT (load_id, row_no, source_file_type)
            WHERE load_id IS NOT NULL AND row_no IS NOT NULL
            DO NOTHING
        RETURNING transaction_id, "SKUKey", "LocationKey", row_no, quantity, transaction_date
		),

    -- one group per SKU+Location+DATE actually present in this load --
    -- a multi-day file now produces one row per date, not one row total.
    date_totals AS (
        SELECT "SKUKey", "LocationKey", transaction_date AS batch_date,
               SUM(quantity) AS day_qty,
               MAX(row_no)   AS latest_row_no_for_day
        FROM inserted
        GROUP BY "SKUKey", "LocationKey", transaction_date
    ),

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

    -- the ONE existing stock_fact_master row, per SKU+Location, from
    -- strictly before this batch's earliest date -- the true starting
    -- point to carry current_qty forward from.
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

    -- cumulative running stock across the dates THIS batch contains,
    -- via a window function -- no loop needed even for a multi-day file.
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

    fact_upsert AS (
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
            day_qty, 0, 0,
            batch_date, day_latest_transaction_id,
            'load_' || p_load_id, 'load_' || p_load_id
        FROM with_running
        ON CONFLICT ("SKUKey", "LocationKey", last_date) DO UPDATE SET
            current_qty          = EXCLUDED.current_qty,
            as_of_inventory      = shinde_shoes.stock_fact_master.as_of_inventory + EXCLUDED.as_of_inventory,
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

    SELECT
        (SELECT COUNT(*) FROM attrs a
           WHERE EXISTS (SELECT 1 FROM shinde_shoes."DimProduct" dp WHERE dp."SKU" = a."SKU")),
        (SELECT COUNT(*) FROM attrs a
           WHERE EXISTS (SELECT 1 FROM new_products np WHERE np."SKU" = a."SKU")),
        (SELECT COUNT(*) FROM new_products),
        (SELECT COUNT(*) FROM attrs a
           WHERE NOT EXISTS (SELECT 1 FROM shinde_shoes."DimProduct" dp WHERE dp."SKU" = a."SKU")
             AND NOT EXISTS (SELECT 1 FROM new_products np WHERE np."SKU" = a."SKU")),
        (SELECT COUNT(*) FROM fact_upsert)
    INTO v_existing_sku_rows, v_new_sku_rows, v_new_skus_created, v_unresolvable_rows, v_posted_rows;

    RAISE NOTICE
        'Stock processing completed. Load ID: %, Total rows: %, Already in DimProduct: %, New-SKU rows (auto-created): % (% distinct new SKUs), Unresolvable (new SKU, missing required attribute -- skipped): %, stock_fact_master rows posted/updated: %',
        p_load_id, v_total_rows, v_existing_sku_rows, v_new_sku_rows, v_new_skus_created, v_unresolvable_rows, v_posted_rows;

END;
$procedure$
;

CREATE OR REPLACE PROCEDURE shinde_shoes.sp_process_upload(IN p_load_id integer, IN p_file_type text)
 LANGUAGE plpgsql
AS $procedure$
BEGIN

    IF p_file_type IS NULL THEN
        RAISE EXCEPTION
            'p_file_type is required -- pass one of ''inventory'', ''purchase'', ''sales''.';
    END IF;

    CASE lower(p_file_type)

        WHEN 'inventory' THEN
            IF p_load_id IS NULL THEN
                RAISE EXCEPTION
                    'p_load_id is required for file_type = ''inventory''.';
            END IF;
            RAISE NOTICE 'sp_process_upload: running INVENTORY chain for load_id %', p_load_id;
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

    RAISE NOTICE
        'sp_process_upload: % chain completed. Check current stock manually, e.g.: SELECT * FROM shinde_shoes.fn_check_stock_fact_master_reconciliation();',
        upper(p_file_type);

END;
$procedure$
;

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
        sfm.current_qty                              AS stored_current_qty,
        COALESCE(t.computed_qty, 0)                  AS computed_from_ledger,
        sfm.current_qty - COALESCE(t.computed_qty, 0) AS mismatch
    FROM latest_sfm sfm
    JOIN shinde_shoes."DimProduct" dp ON dp."SKUKey" = sfm."SKUKey"
    LEFT JOIN (
        SELECT "SKUKey", "LocationKey",
               SUM(CASE WHEN movement_type = 'SALE' THEN -quantity ELSE quantity END) AS computed_qty
        FROM shinde_shoes.stock_transaction
        GROUP BY "SKUKey", "LocationKey"
    ) t ON t."SKUKey" = sfm."SKUKey" AND t."LocationKey" = sfm."LocationKey"
    WHERE sfm.current_qty <> COALESCE(t.computed_qty, 0);
$function$
;

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
        SUM(st.quantity)                     AS qty_posted_by_this_load,
        sfm.current_qty                      AS current_qty_now,
        full_ledger.computed_qty             AS computed_qty_from_full_ledger,
        CASE
            WHEN sfm.current_qty = full_ledger.computed_qty THEN 'OK'
            ELSE 'MISMATCH'
        END                                   AS reconciliation_status
    FROM shinde_shoes.stock_transaction st
    JOIN shinde_shoes."DimProduct" dp
        ON dp."SKUKey" = st."SKUKey"
    LEFT JOIN latest_sfm sfm
        ON sfm."SKUKey" = st."SKUKey" AND sfm."LocationKey" = st."LocationKey"
    LEFT JOIN LATERAL (
        SELECT SUM(CASE WHEN movement_type = 'SALE' THEN -quantity ELSE quantity END) AS computed_qty
        FROM shinde_shoes.stock_transaction all_st
        WHERE all_st."SKUKey" = st."SKUKey" AND all_st."LocationKey" = st."LocationKey"
    ) full_ledger ON true
    WHERE st.load_id = p_load_id
    GROUP BY dp."SKU", st."LocationKey", st.movement_type,
             sfm.current_qty, full_ledger.computed_qty
    ORDER BY dp."SKU", st."LocationKey";
$function$
;

CREATE OR REPLACE PROCEDURE shinde_shoes.sp_reset_fact_and_transaction_tables(IN p_confirm text)
 LANGUAGE plpgsql
AS $procedure$
BEGIN

    IF p_confirm IS DISTINCT FROM 'RESET' THEN
        RAISE EXCEPTION
            'Refusing to run: this TRUNCATEs stock_transaction, stock_fact_master, and purchase_fact_master -- every current stock position and purchase total will be lost. To proceed, call with the exact confirmation text: CALL shinde_shoes.sp_reset_fact_and_transaction_tables(''RESET'');';
    END IF;

    -- All three listed together in one TRUNCATE -- required by Postgres
    -- whenever a table being truncated (stock_transaction) has foreign-key
    -- references pointing at it from other tables (stock_fact_master.
    -- last_transaction_id, purchase_fact_master.last_transaction_id) --
    -- every referencing table has to be truncated in the SAME statement.
    -- RESTART IDENTITY also resets stock_transaction's transaction_id
    -- sequence back to 1, so the next load's transaction_ids start clean.
    TRUNCATE TABLE
        shinde_shoes.stock_transaction,
        shinde_shoes.stock_fact_master,
        shinde_shoes.purchase_fact_master
    RESTART IDENTITY;

    RAISE NOTICE
        'stock_transaction, stock_fact_master, and purchase_fact_master are now empty (transaction_id sequence reset). stg_stock_2/stg_purchase_2/backup tables and every Dim table (including DimProduct) were left untouched -- re-run sp_process_stock_load(<load_id>) / sp_process_purchase_load(<load_id>) for the load_ids you want to re-check.';

END;
$procedure$
;

DROP FUNCTION  shinde_shoes.fn_stock_expected_qty();
DROP PROCEDURE shinde_shoes.sp_rebuild_stock_fact_master(bigint);

COMMIT;

-- Once you are sure the change is right, drop the backup tables:
-- DROP TABLE shinde_shoes.backup_stock_transaction_007, shinde_shoes.backup_stock_fact_master_007;
