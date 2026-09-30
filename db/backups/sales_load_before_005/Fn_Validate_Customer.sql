CREATE OR REPLACE FUNCTION shinde_shoes."Fn_Validate_Customer"(v_mobileno bigint, v_customer character varying, v_gstin character varying, p_sku character varying)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_customerkey     INT := 0;
    v_sku_exists      INT;
    v_final_customer  VARCHAR(255);
    v_final_gstin     VARCHAR(100);
	print_notice boolean;
BEGIN
	print_notice := false;

	if print_notice then
    	Raise Notice 'Customer Validation Start - MobileNo: %', v_MobileNo;
	end if;
    
    /* 1️⃣ Check SKU exists */
    -- SELECT COUNT(*)
    -- INTO v_sku_exists
    -- FROM "Stagging_Tables"."source_table"
    -- WHERE "SKU" = p_SKU;
    
    -- IF v_sku_exists > 0 THEN
    --     RAISE NOTICE 'SKU % exists, exiting', p_SKU;
    --     RETURN 1;
    -- END IF;
    
    /* 2️⃣ Validate MobileNo - If missing, return CustomerKey = 0 */
    IF v_MobileNo IS NULL OR v_MobileNo = 0 THEN
		if print_notice then
        	Raise Notice 'No Mobile Number available → Returning CustomerKey = 0';
		end if;
        RETURN 0;
    END IF;
    
    /* 3️⃣ If Customer name is blank, use MobileNo as Customer name */
    v_final_customer := COALESCE(
        NULLIF(TRIM(v_Customer), ''), 
        v_MobileNo::VARCHAR  -- ✅ Convert BIGINT to VARCHAR for display
    );
    
    /* 4️⃣ GSTIN default handling */
    v_final_gstin := COALESCE(
        NULLIF(TRIM(v_gstin), ''), 
        '0'
    );

	if print_notice then
	    Raise Notice 'Prepared Data - MobileNo: %, Customer: %, GSTIN: %', 
	                 v_MobileNo, v_final_customer, v_final_gstin;
	 end if;
	 
    /* 5️⃣ Insert or Update Customer with ON CONFLICT handling */
    INSERT INTO "shinde_shoes"."DimCustomer"
        ("MobileNo", "Customer", "GSTIN")
    VALUES
        (v_MobileNo, v_final_customer, v_final_gstin)  -- ✅ BIGINT mobile number
    ON CONFLICT ("MobileNo") DO UPDATE
    SET "Customer" = EXCLUDED."Customer",
        "GSTIN" = EXCLUDED."GSTIN";

	if print_notice then
    	Raise Notice 'Fetching CustomerKey for MobileNo: %', v_MobileNo;
	end if;
    
    /* 6️⃣ Fetch CustomerKey for the inserted/existing mobile number */
    SELECT dc."CustomerKey"
    INTO v_customerkey
    FROM "shinde_shoes"."DimCustomer" dc
    WHERE dc."MobileNo" = v_MobileNo;

	if print_notice then
	    Raise Notice 'Customer Validation End - CustomerKey: %', 
	                 COALESCE(v_customerkey, 0);
    end if;
	
    /* Return CustomerKey (0 if not found) */
    RETURN COALESCE(v_customerkey, 0);
    
EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'Error in Customer Validation for MobileNo %: %', v_MobileNo, SQLERRM;
    RETURN 0;
END;
$function$
;
