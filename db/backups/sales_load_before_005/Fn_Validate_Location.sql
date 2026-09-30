CREATE OR REPLACE FUNCTION shinde_shoes."Fn_Validate_Location"(v_locationname character varying, v_sku character varying, v_billno integer)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_sku_exists      INT;
    v_LocationKey     INT := 0;
    v_location_trimmed VARCHAR(255);
	print_notice boolean;
BEGIN
	print_notice := false;

	if print_notice then
	    Raise Notice 'Location Validation Name: %', 'dd' || v_locationname || 'ee';
		Raise Notice 'Location Validation Start';
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
    
    /* 2️⃣ Validate LocationName */
    v_location_trimmed := TRIM(v_LocationName);
    
    IF v_location_trimmed IS NULL 
       OR v_location_trimmed = '' 
       OR v_location_trimmed = '0' THEN
        RAISE NOTICE 'Invalid or missing LocationName → Returning LocationKey = 0';
        RETURN 0;
    END IF;

	if print_notice then
    	Raise Notice 'Inserting/Updating Location: %', v_location_trimmed;
	end if;
    
    /* 3️⃣ Insert or Update Location (handle duplicates) */
    INSERT INTO "shinde_shoes"."DimLocation"("locationName")
    VALUES (v_location_trimmed)
	ON CONFLICT ("locationName") DO NOTHING;
-- WHERE "Sales_Data"."DimLocation"."locationName" = v_location_trimmed;

	if print_notice then
    	Raise Notice 'Fetching LocationKey for: %', v_location_trimmed;
	end if;
    
    /* 4️⃣ Fetch LocationKey */
    SELECT "LocationKey"
    INTO v_LocationKey
    FROM "shinde_shoes"."DimLocation"
    WHERE "locationName" = v_location_trimmed;

	if print_notice then
	   RAISE NOTICE
	    'Location Validation End | BillNo: % | LocationName: % | LocationKey: %',
	    COALESCE(v_BillNo, 0),
	    COALESCE(v_locationname, 'NA'),
	    COALESCE(v_LocationKey, 0);
	end if;

    
    RETURN COALESCE(v_LocationKey, 0);
    
EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'Error in Location Validation: %', SQLERRM;
    RETURN 0;
END;
$function$
;
