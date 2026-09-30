CREATE OR REPLACE FUNCTION shinde_shoes."Fn_Load_DimDate"(v_billdate date)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_DateKey INT := 0;
	print_notice boolean;
	
BEGIN

	print_notice := False;

	if print_notice then
    	Raise Notice 'DimDate Lookup Start - Processing Date: %', v_BillDate;
	end if;
    
    /* 1️⃣ Validate Input Date */
    IF v_BillDate IS NULL THEN
        Raise Notice 'BillDate is NULL → Returning DateKey = 0';
        RETURN 0;
    END IF;
    
    /* 2️⃣ Check if date exists */
    SELECT "DateKey"
    INTO v_DateKey
    FROM "shinde_shoes"."DimDate"
    WHERE "Fulldate" = v_BillDate;
    
    IF v_DateKey IS NOT NULL THEN
		if print_notice then	
        	Raise Notice 'Date % found with DateKey: %', v_BillDate, v_DateKey;
		end if;
        RETURN v_DateKey;
    ELSE
        Raise Notice '⚠️ NEW DATE DETECTED: % is not present in DimDate table!', v_BillDate;
        RETURN 0;
    END IF;
    
EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'Error in DimDate Lookup for Date %: %', v_BillDate, SQLERRM;
    RETURN 0;
END;
$function$
;
