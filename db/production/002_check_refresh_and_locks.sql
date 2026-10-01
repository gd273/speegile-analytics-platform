-- db/production/002_check_refresh_and_locks.sql
-- READ-ONLY. For "upload stuck at 95%" and "dashboard stuck on Loading Dashboard".
-- Run each query on its own in pgAdmin: put the cursor inside it and press F5 (Execute query);
-- the result shows in "Data Output".

-- 1. Dashboard views: every row should be ispopulated = true AND concurrent_refresh = true.
--    concurrent_refresh = false -> that view's refresh locks dashboards (fix: migration 017).
--    ispopulated = false        -> dashboards on that view fail until it is refreshed once.
SELECT m.matviewname, m.ispopulated,
       EXISTS (SELECT 1 FROM pg_index x
               WHERE x.indrelid = format('shinde_shoes.%I', m.matviewname)::regclass
                 AND x.indisunique AND x.indisvalid AND x.indpred IS NULL AND x.indexprs IS NULL) AS concurrent_refresh
FROM pg_matviews m
WHERE m.schemaname = 'shinde_shoes'
ORDER BY 2, 3, 1;

-- 2. What is running right now, and who is waiting on whom.
--    A row with blocked_by filled in is stuck behind that pid.
SELECT a.pid,
       pg_blocking_pids(a.pid)            AS blocked_by,
       a.usename, a.application_name, a.state, a.wait_event_type, a.wait_event,
       now() - a.query_start              AS running_for,
       left(regexp_replace(a.query, '\s+', ' ', 'g'), 120) AS query
FROM pg_stat_activity a
WHERE a.datname = current_database()
  AND a.pid <> pg_backend_pid()
  AND a.state <> 'idle'
ORDER BY a.query_start;

-- 3. Recent dashboard refreshes (RUNNING with no completed_at = never finished).
SELECT refresh_id, started_at, completed_at, duration, status, mv_refreshed_count, mv_durations
FROM shinde_shoes.log_refresh
ORDER BY refresh_id DESC
LIMIT 10;

-- 4. Recent uploads (status 'Refreshing' = the 95% step; the data itself is already saved).
SELECT id, filename, status, row_count, started_at, finished_at, stage_times
FROM public.load_master
ORDER BY id DESC
LIMIT 10;

-- 5. Procedure timings of the latest uploads.
SELECT run_id, parent_run_id, proc_name, load_id, status, started_at, duration_sec, error_message
FROM shinde_shoes.proc_run_log
ORDER BY run_id DESC
LIMIT 20;
