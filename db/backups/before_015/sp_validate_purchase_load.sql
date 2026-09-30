CREATE OR REPLACE PROCEDURE shinde_shoes.sp_validate_purchase_load(IN p_load_id integer)
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

END;
$procedure$
;
