-- db/production/001_public_update.sql
-- PRODUCTION: the public-schema part of the update, after shinde_shoes was restored from the
-- local database. Safe to run more than once. Run with "Execute query" (F5) in pgAdmin.
--
-- 1. public.load_master gets the 3 columns the new upload code writes (same as migration 001):
--      finished_at, stage_times, row_count
--    Only adds columns; existing rows are kept (stage_times = '{}' for them). The old code
--    keeps working with these columns, so this is safe before or after the backend deploy.
--
-- 2. The upload id counter (load_master_id_seq) moves past the load ids used by the restored
--    shinde_shoes data (local ids 346-355), so new production uploads can never reuse one.
--    It only ever moves forward.
--
-- Rollback: nothing to undo for normal use. To drop the columns again:
--   ALTER TABLE public.load_master DROP COLUMN finished_at, DROP COLUMN stage_times, DROP COLUMN row_count;

BEGIN;

ALTER TABLE public.load_master
    ADD COLUMN IF NOT EXISTS finished_at timestamp,
    ADD COLUMN IF NOT EXISTS stage_times jsonb NOT NULL DEFAULT '{}'::jsonb,
    ADD COLUMN IF NOT EXISTS row_count   integer;

COMMENT ON COLUMN public.load_master.finished_at IS 'When the upload reached Pass or Fail';
COMMENT ON COLUMN public.load_master.stage_times IS 'Start time of each upload status, keyed by status name';
COMMENT ON COLUMN public.load_master.row_count   IS 'Data rows read from the uploaded file';

-- Next upload id = at least 1001, and above every id already used anywhere.
SELECT setval('public.load_master_id_seq',
              GREATEST(
                  1000,
                  (SELECT COALESCE(MAX(id), 0) FROM public.load_master),
                  (SELECT COALESCE(MAX(load_id), 0) FROM shinde_shoes.stg_stock_1),
                  (SELECT COALESCE(MAX(load_id), 0) FROM shinde_shoes.stock_transaction),
                  (SELECT COALESCE(MAX(load_id), 0) FROM shinde_shoes.purchase_bill_register),
                  (SELECT COALESCE(MAX(load_id), 0) FROM shinde_shoes.proc_run_log),
                  (SELECT last_value FROM public.load_master_id_seq)
              ));

COMMIT;

-- Check (shows one row; all three columns should say true, next_upload_id >= 1001)
SELECT
    EXISTS (SELECT 1 FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = 'load_master' AND column_name = 'stage_times') AS has_stage_times,
    EXISTS (SELECT 1 FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = 'load_master' AND column_name = 'finished_at') AS has_finished_at,
    EXISTS (SELECT 1 FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = 'load_master' AND column_name = 'row_count')   AS has_row_count,
    (SELECT last_value + 1 FROM public.load_master_id_seq)                                               AS next_upload_id;
