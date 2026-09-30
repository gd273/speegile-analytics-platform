-- 001_load_master_timing.sql
-- Adds upload timing to public.load_master so upload speed can be measured.
--   finished_at : when the upload reached Pass or Fail
--   stage_times : when each status began, e.g. {"Reading": "...", "Processing": "...", "Pass": "..."}
--   row_count   : number of data rows read from the uploaded file
-- Safe to run more than once. Adding nullable/constant-default columns does not rewrite the table.
-- Rollback: 001_load_master_timing_rollback.sql

BEGIN;

ALTER TABLE public.load_master
    ADD COLUMN IF NOT EXISTS finished_at timestamp,
    ADD COLUMN IF NOT EXISTS stage_times jsonb NOT NULL DEFAULT '{}'::jsonb,
    ADD COLUMN IF NOT EXISTS row_count   integer;

COMMENT ON COLUMN public.load_master.finished_at IS 'When the upload reached Pass or Fail';
COMMENT ON COLUMN public.load_master.stage_times IS 'Start time of each upload status, keyed by status name';
COMMENT ON COLUMN public.load_master.row_count   IS 'Data rows read from the uploaded file';

COMMIT;

-- Check upload durations after a few uploads:
-- SELECT id, filename, status, row_count,
--        finished_at - started_at                                           AS total,
--        (stage_times->>'Processing')::timestamp - (stage_times->>'Reading')::timestamp    AS reading_and_prep,
--        (stage_times->>'Saving')::timestamp     - (stage_times->>'Processing')::timestamp AS processing,
--        COALESCE((stage_times->>'Pass')::timestamp, finished_at)
--          - (stage_times->>'Saving')::timestamp                           AS saving_and_refresh
-- FROM public.load_master
-- ORDER BY id DESC
-- LIMIT 20;
