-- Rollback for 010_sku_check_and_purchase_duplicates.sql: restores sp_process_upload and
-- sp_load_sales_set (from db/backups/before_010/) and removes the SKU check, the purchase
-- duplicate check and the purchase bill register.

BEGIN;

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
$procedure$
;


CREATE OR REPLACE PROCEDURE shinde_shoes.sp_load_sales_set()
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_max_rowno  integer;
    v_bad        text;
    v_grp        record;
    v_new_billno integer;
BEGIN
    SELECT COALESCE(MAX(row_no), 0) INTO v_max_rowno FROM shinde_shoes."FactSalesDetail";

    -- ── 1. Parse every staging row once ────────────────────────────────────
    DROP TABLE IF EXISTS pg_temp._sales_rows;
    CREATE TEMP TABLE _sales_rows ON COMMIT DROP AS
    SELECT s.*,
           shinde_shoes."ParseDate_dd_mm_yyyy"(s."BillDate")    AS map_date,       -- used for bill numbering
           shinde_shoes.parse_date_dd_mm_yyyy(s."BillDate")     AS bill_date,      -- used for DateFrKey
           shinde_shoes.parse_date_dd_mm_yyyy(s."LastPurDate")  AS last_pur_date
    FROM   shinde_shoes."stg-1" s;

    -- Bad rows stop the load (row numbers are the data rows of the uploaded file).
    SELECT string_agg(row_no::text, ', ' ORDER BY row_no) INTO v_bad
    FROM   (SELECT row_no FROM _sales_rows WHERE map_date IS NULL OR bill_date IS NULL ORDER BY row_no LIMIT 20) b;
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION 'Sales file has an invalid BillDate in row(s): %', v_bad;
    END IF;

    SELECT string_agg(row_no::text, ', ' ORDER BY row_no) INTO v_bad
    FROM   (SELECT row_no FROM _sales_rows WHERE "BillNo" IS NULL ORDER BY row_no LIMIT 20) b;
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION 'Sales file has an empty BillNo in row(s): %', v_bad;
    END IF;

    SELECT string_agg(row_no::text, ', ' ORDER BY row_no) INTO v_bad
    FROM   (SELECT row_no FROM _sales_rows WHERE "SKU" IS NULL OR trim("SKU") = '' ORDER BY row_no LIMIT 20) b;
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION 'Sales file has an empty SKU in row(s): %', v_bad;
    END IF;

    SELECT string_agg(row_no::text, ', ' ORDER BY row_no) INTO v_bad
    FROM   (SELECT row_no FROM _sales_rows
            WHERE  NULLIF("Counter", '') IS NOT NULL AND "Counter" !~ '^\s*-?\d+(\.\d+)?\s*$'
            ORDER BY row_no LIMIT 20) b;
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION 'Sales file has a non-numeric Counter in row(s): %', v_bad;
    END IF;

    -- ── 2. Bill numbers (same rules as sp_batch_insert_dummy_to_stagging_to_dim) ──
    ALTER TABLE _sales_rows
        ADD COLUMN map_date_key integer,
        ADD COLUMN map_loc_key  integer,
        ADD COLUMN new_billno   integer;

    UPDATE _sales_rows r
    SET    map_date_key = COALESCE((SELECT dd."DateKey" FROM shinde_shoes."DimDate" dd
                                    WHERE dd."Fulldate" = r.map_date LIMIT 1), 0),
           map_loc_key  = COALESCE((SELECT dl."LocationKey" FROM shinde_shoes."DimLocation" dl
                                    WHERE dl."locationName" = r."LocationName" LIMIT 1), 0);

    -- A bill already loaded for the same original bill no + date + store keeps its number.
    UPDATE _sales_rows r
    SET    new_billno = (SELECT MIN(m."BillNo") FROM shinde_shoes."FactSalesMaster" m
                         WHERE  m."Og_BillNo"     = r."BillNo"
                           AND  m."DateFrKey"     = r.map_date_key
                           AND  m."LocationFrKey" = r.map_loc_key);

    -- New bills: one number per (original bill no, store), in file order, never reusing a
    -- number already in FactSalesMaster or already given out in this load.
    DROP TABLE IF EXISTS pg_temp._used_billnos;
    CREATE TEMP TABLE _used_billnos (billno integer PRIMARY KEY) ON COMMIT DROP;
    INSERT INTO _used_billnos SELECT DISTINCT new_billno FROM _sales_rows WHERE new_billno IS NOT NULL;

    DROP TABLE IF EXISTS pg_temp._bill_groups;
    CREATE TEMP TABLE _bill_groups (og_billno integer, map_loc_key integer, new_billno integer) ON COMMIT DROP;

    -- Groups are numbered in the order their first row appears in the file (the old
    -- row-by-row order), which decides who gets the "+1" when numbers clash.
    FOR v_grp IN
        SELECT "BillNo", map_loc_key,
               (array_agg("LocationName" ORDER BY row_no))[1] AS "LocationName",
               MIN(row_no) AS first_row
        FROM   _sales_rows
        WHERE  new_billno IS NULL
        GROUP  BY "BillNo", map_loc_key
        ORDER  BY first_row
    LOOP
        v_new_billno := v_grp."BillNo" + CASE
            WHEN v_grp."LocationName" = 'LT ROAD BRANCH'        THEN 990000
            WHEN v_grp."LocationName" = 'GORAI BRANCH'          THEN 790000
            WHEN v_grp."LocationName" = 'SHINDE SHOES (WOMENS)' THEN 590000
            WHEN v_grp."LocationName" = 'MAHARASTRA NAGAR'      THEN 390000
            ELSE 5000
        END;
        -- Smallest free number >= the candidate (same result as the old "+1 until free" loop).
        -- If the candidate is taken, jump straight past the run of taken numbers that starts
        -- at it, instead of testing one number at a time.
        IF EXISTS (SELECT 1 FROM shinde_shoes."FactSalesMaster" WHERE "BillNo" = v_new_billno)
           OR EXISTS (SELECT 1 FROM _used_billnos WHERE billno = v_new_billno)
        THEN
            SELECT t.n + 1 INTO v_new_billno
            FROM  (SELECT u.n, lead(u.n) OVER (ORDER BY u.n) AS next_n
                   FROM  (SELECT "BillNo" AS n FROM shinde_shoes."FactSalesMaster" WHERE "BillNo" >= v_new_billno
                          UNION ALL
                          SELECT billno FROM _used_billnos WHERE billno >= v_new_billno) u
                  ) t
            WHERE  t.next_n IS NULL OR t.next_n > t.n + 1
            ORDER  BY t.n
            LIMIT  1;
        END IF;
        INSERT INTO _used_billnos VALUES (v_new_billno);
        INSERT INTO _bill_groups  VALUES (v_grp."BillNo", v_grp.map_loc_key, v_new_billno);
    END LOOP;

    UPDATE _sales_rows r
    SET    new_billno = g.new_billno
    FROM   _bill_groups g
    WHERE  r.new_billno IS NULL
      AND  r."BillNo"    = g.og_billno
      AND  r.map_loc_key = g.map_loc_key;

    -- The old path groups by bill no + store only (not date); keep that, but process
    -- rows in the old order: new bill no, then file row.
    ALTER TABLE _sales_rows ADD COLUMN proc_order bigint;
    UPDATE _sales_rows r SET proc_order = o.n
    FROM  (SELECT row_no, row_number() OVER (ORDER BY new_billno, row_no) AS n FROM _sales_rows) o
    WHERE  o.row_no = r.row_no;

    -- Staging copy, as before (stg-2 is read by the reconciliation scripts).
    TRUNCATE shinde_shoes."stg-2";
    INSERT INTO shinde_shoes."stg-2" (
        "Og_BillNO", "BillNo", "BillDate", "Brand", "CategoryDesc", "ProductDesc", "ColorCode",
        "Size", "SKU", "TotalQty", "MRP", "SaleRate", "NetAmount", "MobileNo", "SalesMan1Name",
        "Supplier", "Time", "LocationName", "CreatedUser", "CategoryCode", "SubCategoryCode",
        "SubCategoryDesc", "ProductCode", "ColorDesc", "SizeRange", "BillDiscount",
        "TotalDiscountAmount", "TaxableAmount", "HSNCode", "HSNDesc", "TaxDesc", "TaxRate",
        "TaxAmount", "BillAmount", "Customer", "GSTIN", "BillComment", "Counter", "ModifiedUser",
        "DisplayStockDays", "LastPurDate", "row_no")
    SELECT "BillNo", new_billno, "BillDate", "Brand", "CategoryDesc", "ProductDesc", "ColorCode",
           "Size", "SKU", "TotalQty", "MRP", "SaleRate", "NetAmount", "MobileNo", "SalesMan1Name",
           "Supplier", "Time", "LocationName", "CreatedUser", "CategoryCode", "SubCategoryCode",
           "SubCategoryDesc", "ProductCode", "ColorDesc", "SizeRange", "BillDiscount",
           "TotalDiscountAmount", "TaxableAmount", "HSNCode", "HSNDesc", "TaxDesc", "TaxRate",
           "TaxAmount", "BillAmount", "Customer", "GSTIN", "BillComment", "Counter", "ModifiedUser",
           "DisplayStockDays", "LastPurDate", row_no + v_max_rowno
    FROM   _sales_rows
    ORDER  BY row_no;

    -- ── 3. Product dimensions (first value seen wins, like ON CONFLICT DO NOTHING) ──
    INSERT INTO shinde_shoes."DimBrand" ("BrandName")
    SELECT DISTINCT trim("Brand") FROM _sales_rows
    WHERE  "Brand" IS NOT NULL AND trim("Brand") <> '' AND "Brand" <> '0'
    ON CONFLICT ("BrandName") DO NOTHING;

    INSERT INTO shinde_shoes."DimCategory" ("CategoryName", "CategoryCode")
    SELECT DISTINCT ON (trim("CategoryDesc")) trim("CategoryDesc"), COALESCE(NULLIF(trim("CategoryCode"), ''), '0')
    FROM   _sales_rows
    WHERE  "CategoryDesc" IS NOT NULL AND trim("CategoryDesc") <> '' AND "CategoryDesc" <> '0'
      AND  "CategoryCode" IS NOT NULL AND trim("CategoryCode") <> '' AND "CategoryCode" <> '0'
    ORDER  BY trim("CategoryDesc"), proc_order
    ON CONFLICT ("CategoryName") DO NOTHING;

    ALTER TABLE _sales_rows
        ADD COLUMN brand_key integer, ADD COLUMN category_key integer, ADD COLUMN subcategory_key integer,
        ADD COLUMN productcode_key integer, ADD COLUMN colour_key integer, ADD COLUMN size_key integer,
        ADD COLUMN supplier_key integer, ADD COLUMN sku_key integer, ADD COLUMN customer_key integer,
        ADD COLUMN location_key integer, ADD COLUMN salesperson_key integer, ADD COLUMN date_key integer,
        ADD COLUMN time_key integer;

    UPDATE _sales_rows r SET
        brand_key = CASE WHEN r."Brand" IS NULL OR trim(r."Brand") = '' OR r."Brand" = '0' THEN 0
                         ELSE COALESCE((SELECT b."BrandKey" FROM shinde_shoes."DimBrand" b
                                        WHERE b."BrandName" = trim(r."Brand")), 0) END,
        category_key = CASE WHEN r."CategoryDesc" IS NULL OR trim(r."CategoryDesc") = '' OR r."CategoryDesc" = '0'
                              OR r."CategoryCode" IS NULL OR trim(r."CategoryCode") = '' OR r."CategoryCode" = '0' THEN 0
                         ELSE COALESCE((SELECT c."CategoryKey" FROM shinde_shoes."DimCategory" c
                                        WHERE c."CategoryName" = trim(r."CategoryDesc")), 0) END;

    INSERT INTO shinde_shoes."DimSubCategory" ("SubCategoryName", "SubCategoryCode", "CategoryKey")
    SELECT DISTINCT ON (trim("SubCategoryDesc")) trim("SubCategoryDesc"), COALESCE(NULLIF(trim("SubCategoryCode"), ''), '0'), category_key
    FROM   _sales_rows
    WHERE  "SubCategoryDesc" IS NOT NULL AND trim("SubCategoryDesc") <> '' AND "SubCategoryDesc" <> '0'
      AND  "SubCategoryCode" IS NOT NULL AND trim("SubCategoryCode") <> '' AND "SubCategoryCode" <> '0'
    ORDER  BY trim("SubCategoryDesc"), proc_order
    ON CONFLICT ("SubCategoryName") DO NOTHING;

    UPDATE _sales_rows r SET
        subcategory_key = CASE WHEN r."SubCategoryDesc" IS NULL OR trim(r."SubCategoryDesc") = '' OR r."SubCategoryDesc" = '0'
                                 OR r."SubCategoryCode" IS NULL OR trim(r."SubCategoryCode") = '' OR r."SubCategoryCode" = '0' THEN 0
                            ELSE COALESCE((SELECT s."SubCategoryKey" FROM shinde_shoes."DimSubCategory" s
                                           WHERE s."SubCategoryName" = trim(r."SubCategoryDesc")), 0) END;

    INSERT INTO shinde_shoes."DimProductCode" ("ProductCodeName", "ProdDescription", "SubCategoryKey")
    SELECT DISTINCT ON (trim("ProductCode")) trim("ProductCode"), COALESCE(NULLIF(trim("ProductDesc"), ''), '0'), subcategory_key
    FROM   _sales_rows
    WHERE  "ProductCode" IS NOT NULL AND trim("ProductCode") <> '' AND "ProductCode" <> '0'
      AND  "ProductDesc" IS NOT NULL AND trim("ProductDesc") <> '' AND "ProductDesc" <> '0'
    ORDER  BY trim("ProductCode"), proc_order
    ON CONFLICT DO NOTHING;

    INSERT INTO shinde_shoes."DimColour" ("ColourName", "ColourCode")
    SELECT DISTINCT ON (trim("ColorDesc")) trim("ColorDesc"), trim("ColorCode")
    FROM   _sales_rows
    WHERE  "ColorDesc" IS NOT NULL AND trim("ColorDesc") <> '' AND "ColorDesc" <> '0'
      AND  "ColorCode" IS NOT NULL AND trim("ColorCode") <> '' AND "ColorCode" <> '0'
    ORDER  BY trim("ColorDesc"), proc_order
    ON CONFLICT ("ColourName") DO NOTHING;

    -- Old call passed (SizeRange, Size) into (sizename, sizerange): kept as-is.
    INSERT INTO shinde_shoes."DimSize" ("SizeName", "SizeRange")
    SELECT DISTINCT ON (trim("SizeRange")) trim("SizeRange"), trim("Size")
    FROM   _sales_rows
    WHERE  "SizeRange" IS NOT NULL AND trim("SizeRange") <> '' AND "SizeRange" <> '0'
      AND  "Size" IS NOT NULL AND trim("Size") <> '' AND "Size" <> '0'
    ORDER  BY trim("SizeRange"), proc_order
    ON CONFLICT ("SizeName") DO NOTHING;

    INSERT INTO shinde_shoes."DimSupplier" ("SupplierName")
    SELECT DISTINCT trim("Supplier") FROM _sales_rows
    WHERE  "Supplier" IS NOT NULL AND trim("Supplier") <> '' AND "Supplier" <> '0'
    ON CONFLICT ("SupplierName") DO NOTHING;

    UPDATE _sales_rows r SET
        productcode_key = CASE WHEN r."ProductCode" IS NULL OR trim(r."ProductCode") = '' OR r."ProductCode" = '0'
                                 OR r."ProductDesc" IS NULL OR trim(r."ProductDesc") = '' OR r."ProductDesc" = '0' THEN 0
                            ELSE COALESCE((SELECT p."ProductCodeKey" FROM shinde_shoes."DimProductCode" p
                                           WHERE p."ProductCodeName" = trim(r."ProductCode")), 0) END,
        -- Colour / Size / Supplier: looked up by the untrimmed value, as before.
        colour_key = CASE WHEN r."ColorDesc" IS NULL OR trim(r."ColorDesc") = '' OR r."ColorDesc" = '0'
                            OR r."ColorCode" IS NULL OR trim(r."ColorCode") = '' OR r."ColorCode" = '0' THEN 0
                       ELSE COALESCE((SELECT c."ColourKey" FROM shinde_shoes."DimColour" c
                                      WHERE c."ColourName" = r."ColorDesc"), 0) END,
        size_key = CASE WHEN r."SizeRange" IS NULL OR trim(r."SizeRange") = '' OR r."SizeRange" = '0'
                          OR r."Size" IS NULL OR trim(r."Size") = '' OR r."Size" = '0' THEN 0
                     ELSE COALESCE((SELECT z."SizeKey" FROM shinde_shoes."DimSize" z
                                    WHERE z."SizeName" = r."SizeRange"), 0) END,
        supplier_key = CASE WHEN r."Supplier" IS NULL OR trim(r."Supplier") = '' OR r."Supplier" = '0' THEN 0
                         ELSE COALESCE((SELECT s."SupplierKey" FROM shinde_shoes."DimSupplier" s
                                        WHERE s."SupplierName" = r."Supplier"), 0) END;

    INSERT INTO shinde_shoes."DimProduct"
        ("BrandKey", "ProductCodeKey", "ColorKey", "SizeKey", "SupplierKey",
         "SKU", "ProductDesc", "CategoryDesc", "MRP", "SaleRate", "PurchaseDate")
    SELECT DISTINCT ON ("SKU")
           brand_key, productcode_key, colour_key, size_key, supplier_key,
           "SKU", "ProductDesc", "CategoryDesc", "MRP", "SaleRate", last_pur_date
    FROM   _sales_rows
    ORDER  BY "SKU", proc_order
    ON CONFLICT ("SKU") DO NOTHING;

    -- ── 4. Customer / store / salesperson (customer: last value seen wins) ──
    INSERT INTO shinde_shoes."DimCustomer" ("MobileNo", "Customer", "GSTIN")
    SELECT DISTINCT ON ("MobileNo")
           "MobileNo",
           COALESCE(NULLIF(trim("Customer"), ''), "MobileNo"::varchar),
           COALESCE(NULLIF(trim("GSTIN"), ''), '0')
    FROM   _sales_rows
    WHERE  "MobileNo" IS NOT NULL AND "MobileNo" <> 0
    ORDER  BY "MobileNo", proc_order DESC
    ON CONFLICT ("MobileNo") DO UPDATE
    SET    "Customer" = EXCLUDED."Customer",
           "GSTIN"    = EXCLUDED."GSTIN";

    INSERT INTO shinde_shoes."DimLocation" ("locationName")
    SELECT DISTINCT trim("LocationName") FROM _sales_rows
    WHERE  trim("LocationName") IS NOT NULL AND trim("LocationName") <> '' AND trim("LocationName") <> '0'
    ON CONFLICT ("locationName") DO NOTHING;

    INSERT INTO shinde_shoes."DimSalesPerson" ("SalesPersonName")
    SELECT DISTINCT trim("SalesMan1Name") FROM _sales_rows
    WHERE  trim("SalesMan1Name") IS NOT NULL AND trim("SalesMan1Name") <> '' AND trim("SalesMan1Name") <> '0'
    ON CONFLICT ("SalesPersonName") DO NOTHING;

    UPDATE _sales_rows r SET
        sku_key         = (SELECT p."SKUKey" FROM shinde_shoes."DimProduct" p WHERE p."SKU" = r."SKU"),
        customer_key    = CASE WHEN r."MobileNo" IS NULL OR r."MobileNo" = 0 THEN 0
                               ELSE COALESCE((SELECT c."CustomerKey" FROM shinde_shoes."DimCustomer" c
                                              WHERE c."MobileNo" = r."MobileNo"), 0) END,
        location_key    = CASE WHEN trim(r."LocationName") IS NULL OR trim(r."LocationName") IN ('', '0') THEN 0
                               ELSE COALESCE((SELECT l."LocationKey" FROM shinde_shoes."DimLocation" l
                                              WHERE l."locationName" = trim(r."LocationName")), 0) END,
        salesperson_key = CASE WHEN trim(r."SalesMan1Name") IS NULL OR trim(r."SalesMan1Name") IN ('', '0') THEN 0
                               ELSE COALESCE((SELECT s."SalesPersonKey" FROM shinde_shoes."DimSalesPerson" s
                                              WHERE s."SalesPersonName" = trim(r."SalesMan1Name")), 0) END,
        date_key        = COALESCE((SELECT d."DateKey" FROM shinde_shoes."DimDate" d
                                    WHERE d."Fulldate" = r.bill_date), 0),
        time_key        = CASE WHEN r."Time" IS NULL THEN 0
                               ELSE COALESCE((SELECT t."TimeKey" FROM shinde_shoes."DimTime" t
                                              WHERE t."Time" = make_time(extract(hour FROM r."Time")::int, 0, 0)), 0) END;

    -- ── 5. Bills: one row per new bill, taken from its first line ──────────
    INSERT INTO shinde_shoes."FactSalesMaster"
        ("DateFrKey", "TimeFrKey", "CustomerFrKey", "SalesPersonFrKey", "LocationFrKey",
         "BillNo", "BILLNetAmount", "BillTime", "BillComment", "BillCounter",
         "BillCreatedBy", "BillModifiedBy", "BILLNetAmountAsIs", "NewBillNo", "Og_BillNo")
    SELECT DISTINCT ON (new_billno)
           date_key, time_key, COALESCE(customer_key, 0), COALESCE(salesperson_key, 0), COALESCE(location_key, 0),
           new_billno,
           0,                                   -- set to the sum of the lines in step 7
           COALESCE("Time", '00:00:00'::time),
           COALESCE("BillComment", '0'),
           COALESCE(ROUND(NULLIF("Counter", '')::numeric)::int, 0),
           COALESCE("CreatedUser", '0'),
           COALESCE("ModifiedUser", '0'),
           COALESCE("BillAmount", 0),
           new_billno,
           COALESCE("BillNo", 0)
    FROM   _sales_rows
    ORDER  BY new_billno, proc_order
    ON CONFLICT ("BillNo") DO NOTHING;

    -- ── 6. Bill lines ──────────────────────────────────────────────────────
    -- Line numbers restart at 1 per bill, in file order. A bill that was already loaded
    -- would clash with its existing lines: stop with a clear message instead of skipping.
    SELECT string_agg(DISTINCT r."BillNo"::text, ', ') INTO v_bad
    FROM   _sales_rows r
    JOIN   shinde_shoes."FactSalesMaster" m ON m."BillNo" = r.new_billno
    WHERE  EXISTS (SELECT 1 FROM shinde_shoes."FactSalesDetail" d WHERE d."BillNoKey" = m."BillNoKey");
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION 'These bills were already loaded for the same date and store: %', v_bad;
    END IF;

    INSERT INTO shinde_shoes."FactSalesDetail"
        ("BillNoKey", "BillLineNo", "SKUKey", "SaleQty", "SKUMRP", "SKUSELLPRICE",
         "BillDiscount", "TotalDiscountAmount", "TaxableAmount", "TaxRate", "TaxAmount",
         "NetAmount", "DisplayStockDays", "LastPurDate", "BSaleStatus", "row_no", "Og_BillNo")
    SELECT m."BillNoKey",
           row_number() OVER (PARTITION BY r.new_billno ORDER BY r.row_no)::int,
           r.sku_key,
           COALESCE(r."TotalQty", 0),
           COALESCE(r."MRP", 0),
           COALESCE(r."SaleRate", 0),
           COALESCE(r."BillDiscount", 0),
           COALESCE(r."TotalDiscountAmount", 0),
           COALESCE(r."TaxableAmount", 0),
           COALESCE(r."TaxRate", 0),
           COALESCE(r."TaxAmount", 0),
           COALESCE(r."NetAmount", COALESCE(r."SaleRate", 0) * COALESCE(r."TotalQty", 0)),
           COALESCE(r."DisplayStockDays", 0),
           r.last_pur_date,
           TRUE,
           r.row_no + v_max_rowno,
           COALESCE(r."BillNo", 0)
    FROM   _sales_rows r
    JOIN   shinde_shoes."FactSalesMaster" m ON m."BillNo" = r.new_billno;

    -- ── 7. Bill amount = sum of its lines (fixes the old running-total bug) ──
    UPDATE shinde_shoes."FactSalesMaster" m
    SET    "BILLNetAmount" = d.total
    FROM  (SELECT "BillNoKey", SUM("NetAmount") AS total
           FROM   shinde_shoes."FactSalesDetail"
           WHERE  "BillNoKey" IN (SELECT m2."BillNoKey" FROM shinde_shoes."FactSalesMaster" m2
                                  WHERE m2."BillNo" IN (SELECT DISTINCT new_billno FROM _sales_rows))
           GROUP  BY "BillNoKey") d
    WHERE  m."BillNoKey" = d."BillNoKey"
      AND  m."BILLNetAmount" IS DISTINCT FROM d.total;
END;
$procedure$
;


DROP PROCEDURE shinde_shoes.sp_check_purchase_duplicates(integer);
DROP PROCEDURE shinde_shoes.sp_check_sku_format(text, integer);
DROP TABLE     shinde_shoes.purchase_bill_register;

COMMIT;
