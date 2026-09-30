CREATE OR REPLACE PROCEDURE shinde_shoes."Data_Intialization_Script"()
 LANGUAGE plpgsql
AS $procedure$
BEGIN
    RAISE NOTICE '==============================';
    RAISE NOTICE 'WAREHOUSE RESET STARTED';
    RAISE NOTICE '==============================';

    ----------------------------------------------------------------
    -- 1️⃣ TRUNCATE TABLES (FACT → DIMENSION)
    ----------------------------------------------------------------
    TRUNCATE TABLE
        "shinde_shoes"."FactSalesDetail",
        "shinde_shoes"."FactSalesMaster"
    RESTART IDENTITY CASCADE;

    TRUNCATE TABLE
        "shinde_shoes"."DimProduct",
        "shinde_shoes"."DimProductCode",
        "shinde_shoes"."DimSubCategory",
        "shinde_shoes"."DimCategory",
        "shinde_shoes"."DimBrand",
        "shinde_shoes"."DimColour",
        "shinde_shoes"."DimSize",
        "shinde_shoes"."DimCustomer",
        "shinde_shoes"."DimSalesPerson",
        -- "shinde_shoes"."DimDate",
        -- "shinde_shoes"."DimTime",
        -- "shinde_shoes"."DimLocation",
        "shinde_shoes"."DimSupplier"
    RESTART IDENTITY CASCADE;

    RAISE NOTICE 'All tables truncated successfully';

    ----------------------------------------------------------------
    -- 2️⃣ INSERT DEFAULT (KEY = 0) VALUES
    ----------------------------------------------------------------

    -- CATEGORY
    INSERT INTO "shinde_shoes"."DimCategory"
        ("CategoryKey", "CategoryName", "CategoryCode")
    VALUES (0, 'UNKNOWN_Category','UNKNOWN_Category'),(1,'Service','Category_Service');

    -- SUB CATEGORY
    INSERT INTO "shinde_shoes"."DimSubCategory"
        ("SubCategoryKey", "SubCategoryName","SubCategoryCode", "CategoryKey")
    VALUES (0, 'UNKNOWN_SubCategory','UNKNOWN_SubCategory', 0),(1, 'Service','SubCategory_Service',1);

    -- PRODUCT CODE
    INSERT INTO "shinde_shoes"."DimProductCode"
        ("ProductCodeKey", "ProductCodeName","ProdDescription","SubCategoryKey")
    VALUES (0, 'UNKNOWN_ProductCode','UNKNOWN_Product', 0),(1,'Service','Product_Service',1);

    -- BRAND
    INSERT INTO "shinde_shoes"."DimBrand"
        ("BrandKey", "BrandName")
    VALUES (0, 'UNKNOWNBrand'),(1, 'Brand_Service');

    -- COLOR
    INSERT INTO "shinde_shoes"."DimColour"
        ("ColourKey", "ColourName", "ColourCode")
    VALUES (0, 'UNKNOWN_Colour', 'UNKNOWN_Colour');

    -- SIZE
    INSERT INTO "shinde_shoes"."DimSize"
        ("SizeKey", "SizeRange","SizeName")
    VALUES (0, 'UNKNOWN_Size','UNKNOWN_Size');

    -- CUSTOMER
    INSERT INTO "shinde_shoes"."DimCustomer"
        ("CustomerKey", "MobileNo", "Customer", "GSTIN")
    VALUES (0, '0', 'UNKNOWN_Customer', '0');

    -- SALESPERSON
    INSERT INTO "shinde_shoes"."DimSalesPerson"
        ("SalesPersonKey", "SalesPersonName")
    VALUES (0, 'UNKNOWN_SalesPerson');

    -- DATE
  --   INSERT INTO "shinde_shoes"."DimDate"
  --       ("DateKey", "Fulldate","CalendarYear","CalendarQuarter","CalendarQuarterName",
		-- "CalendarMonth","CalendarMonthName","CalendarDay","CalendarDayName",
		-- "isWeekend","WeekNumber","DayOffset","MonthOffset","QuarterOffset","YearOffset")
  --   VALUES (0, DATE '1001-01-01',1001,1,'UnknownQuarter',1,'UnknownMonth',0,'UnknownDay','FALSE',0,0,0,0,0);

    -- TIME
  --   INSERT INTO "shinde_shoes"."DimTime"
  --   ("TimeKey", "Time")
		-- SELECT 
		--     ROW_NUMBER() OVER (ORDER BY hours) - 1 AS "TimeKey",
		--     (LPAD(hours::TEXT, 2, '0') || ':00:00')::TIME AS "Time"
		-- FROM (
		--     SELECT GENERATE_SERIES(0, 23) AS hours
		-- ) t
		-- ON CONFLICT ("TimeKey") DO NOTHING;

    -- LOCATION
    -- INSERT INTO "shinde_shoes"."DimLocation"
    --     ("LocationKey", "locationName")
    -- VALUES (0, 'UNKNOWN_Location'),
		  --  (1, 'Shinde Legacy'),
	   --     (2,'MAHARASTRA NAGAR'),
		  --  (3,'GORAI BRANCH'),
		  --  (4,'SHINDE SHOES (WOMENS)'),
		  --  (5,'LT ROAD BRANCH');

    -- SUPPLIER
    INSERT INTO "shinde_shoes"."DimSupplier"
        ("SupplierKey", "SupplierName")
    VALUES (0, 'UNKNOWN_Supplier');

    RAISE NOTICE 'Default rows inserted successfully';

    ----------------------------------------------------------------
    -- 3️⃣ RESET ALL SEQUENCES TO START FROM 1
    ----------------------------------------------------------------
    PERFORM setval('"shinde_shoes"."DimCategory_categorykey_seq"', 2, false);
    PERFORM setval('"shinde_shoes"."DimSubCategory_SubCategoryKey_seq"', 2, false);
    PERFORM setval('"shinde_shoes"."DimProductCode_product_code_key_seq"', 2, false);
    PERFORM setval('"shinde_shoes"."DimProduct_SKUKey_seq"', 1, false);
    PERFORM setval('"shinde_shoes"."DimBrand_brandkey_seq"', 2, false);
    PERFORM setval('"shinde_shoes"."DimColour_colourkey_seq"', 1, false);
    PERFORM setval('"shinde_shoes"."DimSize_SizeKey_seq"', 1, false);
    PERFORM setval('"shinde_shoes"."DimCustomer_CustomerKey_seq"', 1, false);
    PERFORM setval('"shinde_shoes"."DimSalesPerson_SalesPersonKey_seq"', 1, false);
    -- PERFORM setval('"shinde_shoes"."DimDate_DateKey_seq"', 1, false);
    -- PERFORM setval('"shinde_shoes"."DimTime_TimeKey_seq"', 1, false);
    -- PERFORM setval('"shinde_shoes"."DimLocation_LocationKey_seq"', 2, false);
    PERFORM setval('"shinde_shoes"."DimSupplier_SupplierKey_seq"', 1, false);

    RAISE NOTICE 'Sequences reset successfully';

    RAISE NOTICE '==============================';
    RAISE NOTICE 'WAREHOUSE RESET COMPLETED';
    RAISE NOTICE '==============================';

END;
$procedure$
;
