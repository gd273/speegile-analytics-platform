CREATE OR REPLACE FUNCTION shinde_shoes."Fn_Validate_SalesPerson"(v_salespersonname character varying, v_sku character varying)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_sku_exists          INT;
    v_SalesPersonKey      INT := 0;
    v_salesperson_trimmed VARCHAR(255);
	print_notice boolean;
BEGIN
	print_notice := false;

	if print_notice then
    	Raise Notice 'SalesPerson Validation Start';
	end if;
    
    /* 1️⃣ Check SKU exists */
    -- SELECT COUNT(*)
    -- INTO v_sku_exists
    -- FROM "Stagging_Tables"."source_table"
    -- WHERE "SKU" = V_SKU;
    
    -- IF v_sku_exists > 0 THEN
    --     RAISE NOTICE 'SKU % exists, exiting', V_SKU;
    --     RETURN 1;
    -- END IF;
    
    /* 2️⃣ Validate SalesPersonName */
    v_salesperson_trimmed := TRIM(v_SalesPersonName);
    
    IF v_salesperson_trimmed IS NULL 
       OR v_salesperson_trimmed = '' 
       OR v_salesperson_trimmed = '0' THEN
        Raise Notice 'Invalid or missing SalesPersonName → Returning SalesPersonKey = 0';
        RETURN 0;
    END IF;

	if print_notice then
    	Raise Notice 'Inserting/Updating SalesPerson: %', v_salesperson_trimmed;
	end if;
    
    /* 3️⃣ Insert or Update SalesPerson (handle duplicates with ON CONFLICT) */
    INSERT INTO "shinde_shoes"."DimSalesPerson"("SalesPersonName")
    VALUES (v_salesperson_trimmed)
    ON CONFLICT ("SalesPersonName") DO UPDATE
    SET "SalesPersonName" = EXCLUDED."SalesPersonName"
    WHERE "shinde_shoes"."DimSalesPerson"."SalesPersonName" = v_salesperson_trimmed;

	if print_notice then
    	Raise Notice 'Fetching SalesPersonKey for: %', v_salesperson_trimmed;
	end if;
    
    /* 4️⃣ Fetch SalesPersonKey */
    SELECT "SalesPersonKey"
    INTO v_SalesPersonKey
    FROM "shinde_shoes"."DimSalesPerson"
    WHERE "SalesPersonName" = v_salesperson_trimmed;

	if print_notice then
    	Raise Notice 'SalesPerson Validation End - SalesPersonKey: %', 
                 COALESCE(v_SalesPersonKey, 0);
    end if;
    RETURN COALESCE(v_SalesPersonKey, 0);
    
EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'Error in SalesPerson Validation: %', SQLERRM;
    RETURN 0;
END;
$function$
;
