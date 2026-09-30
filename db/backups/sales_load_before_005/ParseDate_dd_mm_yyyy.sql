CREATE OR REPLACE FUNCTION shinde_shoes."ParseDate_dd_mm_yyyy"(p_date_text text)
 RETURNS date
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_part1 INT;
    v_part2 INT;
BEGIN
    -- NULL / empty
    IF p_date_text IS NULL OR trim(p_date_text) = '' THEN
        RETURN NULL;
    END IF;

    p_date_text := trim(p_date_text);

    -- ISO: yyyy-mm-dd
    IF p_date_text ~ '^\d{4}-\d{1,2}-\d{1,2}$' THEN
        RETURN to_date(p_date_text, 'YYYY-MM-DD');
    END IF;

    -- Slash format (d/m/yyyy OR m/d/yyyy)
    IF p_date_text ~ '^\d{1,2}/\d{1,2}/\d{4}$' THEN
        v_part1 := split_part(p_date_text, '/', 1)::INT;
        v_part2 := split_part(p_date_text, '/', 2)::INT;

        -- Unambiguous DD/MM
        IF v_part1 > 12 THEN
            RETURN to_date(p_date_text, 'DD/MM/YYYY');

        -- Unambiguous MM/DD
        ELSIF v_part2 > 12 THEN
            RETURN to_date(p_date_text, 'MM/DD/YYYY');

        -- 🔑 Ambiguous → assume DD/MM/YYYY
        ELSE
            RETURN to_date(p_date_text, 'DD/MM/YYYY');
        END IF;
    END IF;

    -- Dash format (d-m-yyyy OR m-d-yyyy)
    IF p_date_text ~ '^\d{1,2}-\d{1,2}-\d{4}$' THEN
        v_part1 := split_part(p_date_text, '-', 1)::INT;
        v_part2 := split_part(p_date_text, '-', 2)::INT;

        IF v_part1 > 12 THEN
            RETURN to_date(p_date_text, 'DD-MM-YYYY');
        ELSIF v_part2 > 12 THEN
            RETURN to_date(p_date_text, 'MM-DD-YYYY');
        ELSE
            RETURN to_date(p_date_text, 'DD-MM-YYYY'); -- default
        END IF;
    END IF;

    RAISE WARNING 'Unrecognized date format: %', p_date_text;
    RETURN NULL;

EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'Date parse failed: % | Error: %', p_date_text, SQLERRM;
    RETURN NULL;
END;
$function$
;
