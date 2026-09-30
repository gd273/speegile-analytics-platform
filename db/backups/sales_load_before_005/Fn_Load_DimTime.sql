CREATE OR REPLACE FUNCTION shinde_shoes."Fn_Load_DimTime"(v_billtime time without time zone)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_TimeKey      INT := 0;
    v_Hour         INT;
    v_HourTime     TIME;
	print_notice boolean;
BEGIN
	print_notice := False;

	if print_notice then
    	Raise Notice 'DimTime Load Start - Processing Time: %', v_BillTime;
	end if;
    
    /* 1️⃣ Validate Input Time */
    IF v_BillTime IS NULL THEN
        Raise Notice 'BillTime is NULL → Returning TimeKey = 0';
        RETURN 0;
    END IF;
    
    /* 2️⃣ Extract Hour from BillTime */
    v_Hour := EXTRACT(HOUR FROM v_BillTime)::INT;
    
    /* 3️⃣ Create Hour Time (HH:00:00) */
    -- v_HourTime := LPAD(v_Hour::TEXT, 2, '0') || ':00:00'::TIME;
	   v_HourTime := (LPAD(v_Hour::TEXT, 2, '0') || ':00:00')::TIME;    
	   
	if print_notice then	   
    	Raise Notice 'Extracted Hour: %, Matching Time: %', v_Hour, v_HourTime;
	end if;
    
    /* 4️⃣ Fetch TimeKey from DimTime (Lookup Only, No Insert) */
    SELECT "TimeKey"
    INTO v_TimeKey
    FROM "shinde_shoes"."DimTime"
    WHERE "Time" = v_HourTime;
    
    IF v_TimeKey IS NULL THEN
        Raise Notice 'No matching TimeKey found for Hour: %', v_Hour;
        RETURN 0;
    END IF;

	if print_notice then
    	Raise Notice 'DimTime Lookup Complete - Returning TimeKey: %', v_TimeKey;
	end if;
    
    RETURN v_TimeKey;
    
EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'Error in DimTime Lookup for Time %: %', v_BillTime, SQLERRM;
    RETURN 0;
END;
$function$
;
