CREATE OR REPLACE FUNCTION public.fn_proc_run_end(p_run_id bigint, p_details jsonb DEFAULT NULL::jsonb)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_parent bigint;
BEGIN
    UPDATE public.proc_run_log
    SET    status       = 'SUCCESS',
           finished_at  = clock_timestamp(),
           duration_sec = round(extract(epoch FROM clock_timestamp() - started_at)::numeric, 3),
           details      = CASE WHEN p_details IS NULL THEN details
                               ELSE COALESCE(details, '{}'::jsonb) || p_details END
    WHERE  run_id = p_run_id
    RETURNING parent_run_id INTO v_parent;

    PERFORM set_config('proc_run.current_run_id', COALESCE(v_parent::text, ''), true);
END;
$function$
;
