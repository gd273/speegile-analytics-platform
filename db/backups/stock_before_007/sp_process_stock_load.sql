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
