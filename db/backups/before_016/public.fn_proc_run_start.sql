CREATE OR REPLACE FUNCTION public.fn_proc_run_start(p_proc_name text, p_load_id integer DEFAULT NULL::integer, p_details jsonb DEFAULT NULL::jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_run_id bigint;
BEGIN
    INSERT INTO public.proc_run_log (parent_run_id, schema_name, proc_name, load_id, details)
    VALUES (
        NULLIF(current_setting('proc_run.current_run_id', true), '')::bigint,
        CASE WHEN position('.' IN p_proc_name) > 0 THEN split_part(p_proc_name, '.', 1) ELSE 'public' END,
        CASE WHEN position('.' IN p_proc_name) > 0 THEN split_part(p_proc_name, '.', 2) ELSE p_proc_name END,
        COALESCE(p_load_id, NULLIF(current_setting('proc_run.load_id', true), '')::integer),
        p_details
    )
    RETURNING run_id INTO v_run_id;

    PERFORM set_config('proc_run.current_run_id', v_run_id::text, true);
    RETURN v_run_id;
END;
$function$
;
