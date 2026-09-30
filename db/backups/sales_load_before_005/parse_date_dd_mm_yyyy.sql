CREATE OR REPLACE FUNCTION shinde_shoes.parse_date_dd_mm_yyyy(p_date_text text)
 RETURNS date
 LANGUAGE plpgsql
AS $function$
BEGIN
    IF p_date_text IS NULL OR trim(p_date_text) = '' THEN
        RETURN NULL;
    END IF;

    -- Normalize separators
    p_date_text := replace(trim(p_date_text), '/', '-');

    -- Assume DD-MM-YYYY
    RETURN to_date(p_date_text, 'DD-MM-YYYY');

EXCEPTION WHEN others THEN
	RAISE WARNING 'Unrecognized date format: %', p_date_text;
    RETURN NULL;
END;
$function$
;
