-- 017_mv_monthly_product_sales_trend unique index
-- shinde_shoes.mv_monthly_product_sales_trend had lost the unique index from 003 (the view was
-- recreated after 003). Without it, refresh_all_mvs() cannot refresh this view CONCURRENTLY and
-- falls back to a plain REFRESH, which takes an ACCESS EXCLUSIVE lock:
--   * the refresh waits until every running dashboard query on the view finishes, and
--   * every dashboard query that arrives meanwhile waits behind the refresh.
-- That shows as an upload stuck at 95% ("Refreshing") and dashboards stuck on "Loading Dashboard".
--
-- CREATE INDEX CONCURRENTLY cannot run inside a transaction block: run this file as-is
-- (psql -f, or pgAdmin "Execute query"), not wrapped in BEGIN/COMMIT. Safe to run more than once.
-- Rollback: DROP INDEX CONCURRENTLY IF EXISTS shinde_shoes.ux_mv_monthly_product_sales_trend;

CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS ux_mv_monthly_product_sales_trend
    ON shinde_shoes.mv_monthly_product_sales_trend
       (month_start_date, location_name, brand_name, subcategory_name, category_name, product_code, prod_description);

-- Check: every view should say concurrent_refresh = true
-- SELECT m.matviewname, m.ispopulated,
--        EXISTS (SELECT 1 FROM pg_index x
--                WHERE x.indrelid = format('shinde_shoes.%I', m.matviewname)::regclass
--                  AND x.indisunique AND x.indisvalid AND x.indpred IS NULL AND x.indexprs IS NULL) AS concurrent_refresh
-- FROM pg_matviews m WHERE m.schemaname = 'shinde_shoes' ORDER BY 1;
