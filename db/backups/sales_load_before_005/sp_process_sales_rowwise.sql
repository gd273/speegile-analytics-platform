CREATE OR REPLACE PROCEDURE shinde_shoes.sp_process_sales_rowwise()
 LANGUAGE plpgsql
AS $procedure$
/*
═══════════════════════════════════════════════════════════════════════════
  SALES DATA ROWWISE PROCESSING PROCEDURE
  
  PURPOSE: 
    - Validate all dimension attributes from source staging table
    - Populate DimProduct with product attributes
    - Populate FactSalesMaster with bill-level information
    - Populate FactSalesDetail with product-level line items
  
  AMOUNT COLUMN MAPPING:
    ┌──────────────────────────────────────────────────────────────────┐
    │ BILLNetAmount ← Calculated from FactSalesDetail (SUM of items) │
    │ BILLNetAmountAsIs ← Original bill amount from source table      │
    └──────────────────────────────────────────────────────────────────┘
    
  VALIDATION WORKFLOW:
    1. Row is processed for each unique BillNo in source table
    2. Fn_Insert_FactSalesDetail() calculates SUM of all products in bill
    3. BILLNetAmount is populated with this calculated sum
    4. Local reconciliation check compares BILLNetAmount vs BILLNetAmountAsIs
    5. Use Data_Validation_Script() for complete cross-table validation
    
  ✅ The validation script will verify:
     - Source BillAmount = SalesDetail SUM = FactSalesMaster BILLNetAmount
     - FactSalesMaster BILLNetAmount = BILLNetAmountAsIs (for matching bills)
═══════════════════════════════════════════════════════════════════════════
*/
DECLARE
    r RECORD;

    -- ProductCodeKey Variable
    v_ProductCodeName varchar(255);
	v_ProdDescription varchar(255);
    v_ProductCodeKey INT;
	-- Category Variable 
	v_CategoryDesc varchar(255);
	v_CategoryCode varchar(255);
	v_categorykey INT;
	-- SubCategory Variable
	v_SubCategoryCode varchar(255);
	v_SubCategoryDesc varchar(255);
	v_subcategorykey INT;
	-- Brand Variable
	v_BrandName varchar(255);
	v_BrandKey int;
	-- Colour Vairable 
	v_ColorName varchar(255);
	v_ColorCode varchar(255);
	v_ColorKey int;
	-- Size Variable
	v_SizeRange varchar(255);
	v_SizeName varchar(255);
	v_SizeKey int;
	-- Supplier Variable
	v_SupplierName varchar(255);
	v_SupplierKey int;
	-- Customer Variable
	v_MobileNo BIGINT;  -- ✅ CHANGED: VARCHAR(10) → BIGINT (matches source table)
	v_Customer varchar(255);
	v_gstin varchar(100);
	v_CustomerKey int;
	-- Location Variable
	v_LocationKey int;
	v_LocationName varchar(255);
	-- SalesPerson Variable
	v_SalesPersonName varchar(255);
	v_SalesPersonKey int;
	-- Date Variable
	v_Date Varchar(50);
	v_DateKey Int;
	v_lastpurdate Varchar(50);
	v_Date_dd_mm_yy DATE;
	v_LastPurDate_dd_mm_yy DATE;
	-- Time Variable
	v_Time TIME;
	v_TimeKey int;
	-- Use In All Function
	V_SKU Varchar(50) := '101280079986';
	v_STG_SKU Varchar(50);
	v_New_BillNo BIGINT;
	-- Master Table Variable
	v_BillNo INT;  -- ✅ CHANGED: BIGINT → INT (matches source table)
	v_BillTime TIME;
	v_BillComment varchar(255);
	v_BillCounter VARCHAR(50);  -- ✅ CHANGED: INT → VARCHAR(50) (matches source table)
	v_BILLNetAmountAsIs NUMERIC(14,2);  -- ✅ CHANGED: NUMERIC(12,2) → NUMERIC(14,2) (matches source table)
	v_BillCreatedBy varchar(255);
	v_BillModifiedBy varchar(255);
	v_Og_BillNo INT;
	-- SalesDetail table Variable
	v_rows_inserted INT;
	v_func_message VARCHAR; 
	v_bill_net_amount NUMERIC(12,2);    -- ✅ ADD THIS LINE
	v_BillNoKey_D INT; -- This is For Passing into FactDetail Table
	v_BillLineNo_D INT;
	v_SkuKey INT;
	v_prev_BillNoKey INT := -1;
	-- Reconciliation Variable
	v_amount_variance NUMERIC(12,2);
	v_reconciliation_status VARCHAR(50);
	print_notice boolean;
	
BEGIN

	print_notice := FALSE;   -- Set FALSE in production to reduce noise
	-- Raise Notice 'Procedure started';
    FOR r IN 
		SELECT * FROM "shinde_shoes"."stg-2"
		ORDER BY "BillNo", "row_no"
    LOOP
        BEGIN
		   -- Raise Notice 'Processing Location, Bill# % %', r."LocationName", r."BillNo";
		
            -- VALIDATE DIMENSIONS
			v_CategoryDesc := r."CategoryDesc";
			v_CategoryCode := r."CategoryCode";
			v_SubCategoryCode := r."SubCategoryCode";
			v_SubCategoryDesc := r."SubCategoryDesc";
			v_ProductCodeName := r."ProductCode";
			v_ProdDescription := r."ProductDesc";
			v_BrandName := r."Brand";
			v_ColorName := r."ColorDesc";
			v_ColorCode := r."ColorCode";
			v_STG_SKU := r."SKU";
			v_SizeRange := r."SizeRange";
			v_SizeName := r."Size";
			v_SupplierName := r."Supplier";
			v_MobileNo := r."MobileNo";  -- ✅ Now BIGINT (no casting needed)
			v_Customer := r."Customer";
			v_gstin := r."GSTIN";
			v_LocationName := r."LocationName";
			v_SalesPersonName := r."SalesMan1Name";
			v_Date := r."BillDate";  
			v_Time := r."Time";  -- ✅ Already TIME (no casting needed)
			v_BillNo := r."BillNo";  -- ✅ Already INTEGER (no casting needed)
			v_BillTime := r."Time";  -- ✅ Already TIME (no casting needed)
			v_BillComment := r."BillComment";
			v_BillCounter := r."Counter";  -- ✅ Keep as VARCHAR(50) from source
			v_BILLNetAmountAsIs := COALESCE(r."BillAmount", 0);  -- ✅ Already NUMERIC(14,2) (no casting needed)
			v_BillCreatedBy := r."CreatedUser";
			v_BillModifiedBy := r."ModifiedUser";
			v_LastPurDate := r."LastPurDate";
			v_Og_BillNo := r."Og_BillNO";

			-- Raise Notice '🔍 Debug - BillNo: %, Og_BillNo: %, NewBillNo: %', 
    	-- v_BillNo, v_Og_BillNo, v_New_BillNo;
		
				v_Date_dd_mm_yy	:= "shinde_shoes"."parse_date_dd_mm_yyyy"(v_Date);
				v_LastPurDate_dd_mm_yy := "shinde_shoes"."parse_date_dd_mm_yyyy"(v_LastPurDate);
			-- -- Raise Notice 'Assignments completed successfully';
			
			v_BrandKey := "shinde_shoes"."Fn_Validate_Brand"(v_BrandName, V_SKU);
			
            v_categorykey := "shinde_shoes"."Fn_Validate_Category"(v_CategoryDesc, v_CategoryCode, V_SKU);
			
			v_subcategorykey := "shinde_shoes"."Fn_Validate_SubCategory"(v_categorykey, v_SubCategoryCode, v_SubCategoryDesc, V_SKU);
			
			v_ProductCodeKey := "shinde_shoes"."Fn_Validate_ProductCode"(v_subcategorykey, v_ProductCodeName, v_ProdDescription, V_SKU);
			
			v_ColorKey := "shinde_shoes"."Fn_Validate_Color"(v_ColorName, v_ColorCode, V_SKU);
			
			v_SizeKey := "shinde_shoes"."Fn_Validate_Size"(v_SizeRange, v_SizeName, V_SKU);
			
			v_SupplierKey := "shinde_shoes"."Fn_Validate_Supplier"(v_SupplierName, V_SKU);

------------------------------------------------------------------------
-- 						Populate The DimProduct
------------------------------------------------------------------------

			INSERT INTO "shinde_shoes"."DimProduct"
					(
					  "BrandKey",
					  "ProductCodeKey",
					  "ColorKey",
					  "SizeKey",
					  "SupplierKey",
					  "SKU",
					  "ProductDesc",
					  "CategoryDesc",
					  "MRP",
					  "SaleRate",
					  "PurchaseDate"
					)
					VALUES 
					(
					  v_BrandKey,
					  v_ProductCodeKey,
					  v_ColorKey,
					  v_SizeKey,
					  v_SupplierKey,
					  v_STG_SKU,
					  r."ProductDesc",
					  r."CategoryDesc",
					  r."MRP",
					  r."SaleRate",
					  v_LastPurDate_dd_mm_yy
					)
					ON CONFLICT ("SKU") DO NOTHING;

			select "SKUKey" into v_SkuKey
			from "shinde_shoes"."DimProduct"
			where "SKU" = v_STG_SKU;
			
			if print_notice then
				Raise Notice 'DimProduct insert completed %', v_STG_SKU;
			end if;

			
			v_CustomerKey := "shinde_shoes"."Fn_Validate_Customer"(v_MobileNo, v_Customer, v_gstin,V_SKU);  

			v_LocationKey := "shinde_shoes"."Fn_Validate_Location"(v_LocationName, V_SKU, v_BillNo);
			
			v_SalesPersonKey := "shinde_shoes"."Fn_Validate_SalesPerson"(v_SalesPersonName, V_SKU);
			
			v_DateKey := "shinde_shoes"."Fn_Load_DimDate"(v_Date_dd_mm_yy);
			
			v_TimeKey := "shinde_shoes"."Fn_Load_DimTime"(v_Time);

			-- v_New_BillNo = (v_LocationKey::TEXT || v_BillNo::TEXT)::BIGINT;
			
			v_New_BillNo = v_BillNo;
			if print_notice then
				 Raise Notice 'New BillNo Recived from stg-1  :- %',v_New_BillNo;
				 Raise Notice 'All validations completed - DateKey: %, TimeKey: %, CustomerKey: %', v_DateKey, v_TimeKey, v_CustomerKey;
			end if;	 

------------------------------------------------------------------------
-- 						Populate The FactSalesMaster
------------------------------------------------------------------------
			if print_notice then
				Raise Notice 'Insert Start Into FactSalesMaster';
			end if;
			
			INSERT INTO "shinde_shoes"."FactSalesMaster"
			(
			    "DateFrKey",
			    "TimeFrKey",
			    "CustomerFrKey",
			    "SalesPersonFrKey",
			    "LocationFrKey",
			    "BillNo",
			    "BILLNetAmount",
			    "BillTime",
			    "BillComment",
			    "BillCounter",
			    "BillCreatedBy",
			    "BillModifiedBy",
			    "BILLNetAmountAsIs",
				"NewBillNo",
				"Og_BillNo"
			)
			VALUES 
			(
				v_DateKey,
			    v_TimeKey,
			    COALESCE(v_CustomerKey, 0),
			    COALESCE(v_SalesPersonKey, 0),
			    COALESCE(v_LocationKey, 0),
			    COALESCE(v_BillNo, 0),
			    COALESCE(v_bill_net_amount, 0),    -- ✅ Calculated from FactSalesDetail (sum of all products)
			    COALESCE(v_BillTime, '00:00:00'::TIME),
			    COALESCE(v_BillComment, '0'),
				COALESCE(ROUND(NULLIF(v_BillCounter, '')::NUMERIC)::INT, 0), -- Handle The Float (3.0) Type Value
				-- COALESCE(NULLIF(v_BillCounter, '')::INT, 0),
			    COALESCE(v_BillCreatedBy, '0'),
			    COALESCE(v_BillModifiedBy, '0'),
			    COALESCE(v_BILLNetAmountAsIs, 0),    -- ✅ Original amount from source staging table
				COALESCE(v_New_BillNo, 0),
				COALESCE(v_Og_BillNo, 0)
			)
			ON CONFLICT ("BillNo") DO NOTHING  -- ✅ FIX: Handle duplicate BillNo
			RETURNING "BillNoKey" INTO v_BillNoKey_D;  

			IF v_BillNoKey_D IS NULL THEN
			    SELECT "BillNoKey" INTO v_BillNoKey_D
			    FROM "shinde_shoes"."FactSalesMaster"
			    WHERE "BillNo" = v_BillNo
			    LIMIT 1;

				if print_notice then
			    	Raise NOTICE 'Reusing BillNoKey=% for BillNo=% (multi-line bill)', v_BillNoKey_D, v_BillNo;
				end if;
				
			END IF;
			
			-- Hard safety check
			IF v_BillNoKey_D IS NULL THEN
			    -- Raise WARNING '⚠ Cannot determine BillNoKey for BillNo=% Og_BillNo=% — skipping.',
			        -- v_BillNo, v_Og_BillNo;
			    CONTINUE;
			END IF;
			-- GET DIAGNOSTICS v_rows_inserted = ROW_COUNT;
			-- 	IF v_rows_inserted = 0 THEN
			-- 	    -- Raise WARNING '⚠ ON CONFLICT fired for BillNo=% Og_BillNo=% — skipping detail insert.',
			-- 	        v_BillNo, v_Og_BillNo;
			-- 	    CONTINUE;
			-- 	END IF;
				
			-- SET
			--     "DateFrKey" = EXCLUDED."DateFrKey",
			--     "TimeFrKey" = EXCLUDED."TimeFrKey",
			--     "CustomerFrKey" = EXCLUDED."CustomerFrKey",
			--     "SalesPersonFrKey" = EXCLUDED."SalesPersonFrKey",
			--     "LocationFrKey" = EXCLUDED."LocationFrKey",
			--     "BILLNetAmount" = EXCLUDED."BILLNetAmount",
			--     "BillTime" = EXCLUDED."BillTime",
			--     "BillComment" = EXCLUDED."BillComment",
			--     "BillCounter" = EXCLUDED."BillCounter",
			--     "BillCreatedBy" = EXCLUDED."BillCreatedBy",
			--     "BillModifiedBy" = EXCLUDED."BillModifiedBy",
			--     "BILLNetAmountAsIs" = EXCLUDED."BILLNetAmountAsIs";
			if print_notice then
				Raise Notice 'Insert End Into FactSalesMaster - Row processed successfully LocationKey, Bill#,NewBill# % % %', v_LocationKey, v_BillNo, v_New_BillNo;
			end if;	

--- Take The BillNoKey From The Master Table 

-- select "BillNoKey" Into v_BillNoKey_D
-- from "shinde_shoes"."FactSalesMaster"
-- Where "NewBillNo" = v_New_BillNo;

-- Raise Notice 'New BillNo Generate : v_BillNoKey_D v_New_BillNo % %',v_BillNoKey_D, v_New_BillNo;

-- Take The BillLineNo 
-- select count(*) into v_BillLineNo_D
-- from "shinde_shoes"."FactSalesDetail"
-- where "BillNoKey" = v_BillNoKey_D;

-- v_BillLineNo_D = v_BillLineNo_D+1;

IF v_BillNoKey_D <> v_prev_BillNoKey THEN
    v_BillLineNo_D  := 1;
    v_prev_BillNoKey := v_BillNoKey_D;
ELSE
    v_BillLineNo_D := v_BillLineNo_D + 1;
END IF;

------------------------------------------------------------------------
--                            FactSalesDetail
------------------------------------------------------------------------
	if print_notice then
		Raise Notice 'Start FactSalesDetail';
	end if;

-- Capture the function return values BEFORE inserting into FactSalesMaster
		SELECT rows_inserted, message, bill_net_amount
		INTO v_rows_inserted, v_func_message, v_bill_net_amount
		FROM "shinde_shoes"."Fn_Insert_FactSalesDetail"(
			v_BillNoKey_D,
			v_BillLineNo_D,
			v_SkuKey,
			r."TotalQty",
			r."MRP",
			r."SaleRate",
			r."BillDiscount",
			r."TotalDiscountAmount",
			r."TaxableAmount",
			r."TaxRate",
			r."TaxAmount",
			r."NetAmount",
			r."DisplayStockDays",
			v_LastPurDate_dd_mm_yy,
			r."row_no",
			r."BillNo",
			COALESCE(v_Og_BillNo, 0)	
			);
		
		-- Log the results
		if print_notice then
			Raise Notice 'FactSalesDetail Status: %', v_func_message;
			Raise Notice 'Rows inserted: %', v_rows_inserted;
			Raise Notice 'Bill Net Amount from SalesDetail: %', v_bill_net_amount;
			Raise Notice 'Bill Amount from Source (AsIs): %', v_BILLNetAmountAsIs;
		end if;
		
		-- ✅ LOCAL RECONCILIATION CHECK: Compare both amounts for this bill
		v_amount_variance := ABS(v_bill_net_amount - v_BILLNetAmountAsIs);
		
		IF v_amount_variance = 0 THEN
		    v_reconciliation_status := 'MATCHED';
		    -- Raise NOTICE '✓ Bill Reconciliation PASSED | BillNo: % | SalesDetail: % | Source: % | Status: VERIFIED', 
		        -- v_BillNo, v_bill_net_amount, v_BILLNetAmountAsIs;
		ELSE
		    v_reconciliation_status := 'MISMATCH';
		    -- Raise WARNING '⚠ Bill Reconciliation MISMATCH | BillNo: % | SalesDetail: % | Source: % | Variance: %', 
		        -- v_BillNo, v_bill_net_amount, v_BILLNetAmountAsIs, v_amount_variance;
		END IF;

        EXCEPTION WHEN OTHERS THEN
            DECLARE v_context text;
            BEGIN
                GET STACKED DIAGNOSTICS v_context = PG_EXCEPTION_CONTEXT;
             	 Raise Notice 'Error occurred: %', SQLERRM;
                 Raise NOTICE 'CONTEXT → %', v_context;
            END;
        END;
    END LOOP;

	if print_notice then
    	Raise Notice 'Procedure completed successfully';
	end if;
    
END;
$procedure$
;
