CREATE OR REPLACE PROCEDURE shinde_shoes.sp_validate_stock_load(IN p_load_id integer)
 LANGUAGE plpgsql
AS $procedure$

DECLARE
    v_total_rows   integer := 0;
    v_invalid_rows integer := 0;
    v_valid_rows   integer := 0;

BEGIN

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
        ),


        -- ========================================================
        -- BILL DATE
        -- NULL / empty is allowed
        -- ========================================================

        (
            'INVALID_BILL_DATE',
            'BillDate',
            i."BillDate",
            'BillDate must be a valid DD-MM-YYYY date.',
            NULLIF(TRIM(i."BillDate"), '') IS NOT NULL
            AND shinde_shoes.parse_date_dd_mm_yyyy(i."BillDate") IS NULL
        ),


        -- ========================================================
        -- EXPIRY
        -- NULL / empty is allowed
        -- ========================================================

        (
            'INVALID_EXPIRY_DATE',
            'Expiry',
            i."Expiry",
            'Expiry must be a valid DD-MM-YYYY date.',
            NULLIF(TRIM(i."Expiry"), '') IS NOT NULL
            AND shinde_shoes.parse_date_dd_mm_yyyy(i."Expiry") IS NULL
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
            ELSE shinde_shoes.parse_date_dd_mm_yyyy(i."Expiry")
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
            ELSE shinde_shoes.parse_date_dd_mm_yyyy(i."BillDate")
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
            ELSE shinde_shoes.parse_date_dd_mm_yyyy(i."Expiry")
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
            ELSE shinde_shoes.parse_date_dd_mm_yyyy(i."BillDate")
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

END;
$procedure$
;
