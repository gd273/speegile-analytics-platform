-- Rollback for 001_load_master_timing.sql
-- Deploy the backend version without upload timing first, or it will fail writing these columns.

BEGIN;

ALTER TABLE public.load_master
    DROP COLUMN IF EXISTS finished_at,
    DROP COLUMN IF EXISTS stage_times,
    DROP COLUMN IF EXISTS row_count;

COMMIT;
