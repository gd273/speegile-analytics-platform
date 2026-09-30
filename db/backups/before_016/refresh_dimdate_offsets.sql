CREATE OR REPLACE PROCEDURE shinde_shoes.refresh_dimdate_offsets(IN p_as_of_date date)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_run_id bigint;   -- public.proc_run_log
BEGIN
    v_run_id := public.fn_proc_run_start('shinde_shoes.refresh_dimdate_offsets', NULL, jsonb_build_object('as_of_date', p_as_of_date));
    UPDATE "shinde_shoes"."DimDate" d
    SET
        -- Day Offset
        "DayOffset" =
            (d."Fulldate" - p_as_of_date),

        -- Month Offset
        "MonthOffset" =
            (
                (EXTRACT(YEAR FROM d."Fulldate") - EXTRACT(YEAR FROM p_as_of_date)) * 12
              + (EXTRACT(MONTH FROM d."Fulldate") - EXTRACT(MONTH FROM p_as_of_date))
            ),

        -- Quarter Offset
        "QuarterOffset" =
            (
                (EXTRACT(YEAR FROM d."Fulldate") - EXTRACT(YEAR FROM p_as_of_date)) * 4
              + (EXTRACT(QUARTER FROM d."Fulldate") - EXTRACT(QUARTER FROM p_as_of_date))
            ),

        -- Year Offset
        "YearOffset" =
            (EXTRACT(YEAR FROM d."Fulldate") - EXTRACT(YEAR FROM p_as_of_date));
    PERFORM public.fn_proc_run_end(v_run_id, NULL);
END;
$procedure$
;
