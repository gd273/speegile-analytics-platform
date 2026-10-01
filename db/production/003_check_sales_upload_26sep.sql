-- db/production/003_check_sales_upload_26sep.sql
-- READ-ONLY. Checks that the 26-Sep-2026 sales upload went through every step.
-- Run each query on its own (cursor inside it, F5). Change the date in each query for other days.

-- 1. The upload itself: status should be 'Pass', with a row_count.
SELECT id AS load_id, filename, status, row_count, started_at, finished_at,
       finished_at - started_at AS took, stage_times
FROM public.load_master
WHERE filename ILIKE '%26%09%2026%' OR filename ILIKE '%26-09-26%' OR filename ILIKE '%26_09_26%'
ORDER BY id DESC;

-- 2. Any error recorded for it (should return nothing).
SELECT e.load_id, e.error_message, e.created_at
FROM public.load_errors e
JOIN public.load_master m ON m.id = e.load_id
WHERE m.filename ILIKE '%26%09%2026%' OR m.filename ILIKE '%26-09-26%' OR m.filename ILIKE '%26_09_26%'
ORDER BY e.id DESC;

-- 3. Every procedure step of the upload (all SUCCESS; replace 1001 with the load_id from query 1).
SELECT run_id, parent_run_id, proc_name, status, duration_sec, details, error_message
FROM shinde_shoes.proc_run_log
WHERE load_id = 1001
ORDER BY run_id;

-- 4. Sales saved for 26-Sep, per store (bills, lines, qty, amount).
SELECT l."locationName" AS store,
       COUNT(DISTINCT m."BillNoKey") AS bills,
       COUNT(*)                      AS lines,
       SUM(d."SaleQty")              AS qty,
       SUM(d."NetAmount")            AS net_amount
FROM shinde_shoes."FactSalesMaster" m
JOIN shinde_shoes."FactSalesDetail" d  ON d."BillNoKey"   = m."BillNoKey"
JOIN shinde_shoes."DimDate"         dd ON dd."DateKey"    = m."DateFrKey"
JOIN shinde_shoes."DimLocation"     l  ON l."LocationKey" = m."LocationFrKey"
WHERE dd."Fulldate" = DATE '2026-09-26'
GROUP BY ROLLUP (l."locationName")
ORDER BY 1 NULLS LAST;

-- 5. File rows vs saved lines. "stg-1" still holds the LAST uploaded sales file; if that was
--    the 26-Sep file, file_rows should equal saved_lines.
SELECT (SELECT COUNT(*) FROM shinde_shoes."stg-1") AS file_rows,
       (SELECT MIN("BillDate") || ' .. ' || MAX("BillDate") FROM shinde_shoes."stg-1") AS file_dates,
       (SELECT COUNT(*)
        FROM shinde_shoes."FactSalesDetail" d
        JOIN shinde_shoes."FactSalesMaster" m ON m."BillNoKey" = d."BillNoKey"
        JOIN shinde_shoes."DimDate" dd ON dd."DateKey" = m."DateFrKey"
        WHERE dd."Fulldate" = DATE '2026-09-26') AS saved_lines;

-- 6. Data quality for 26-Sep (all should be 0).
SELECT COUNT(*) FILTER (WHERE p."SKU" !~ '^[0-9]{12}$')        AS bad_skus,
       COUNT(*) FILTER (WHERE m."LocationFrKey" = 0)             AS missing_store,
       COUNT(*) FILTER (WHERE d.posted_to_stock IS NOT TRUE)     AS not_posted_to_stock
FROM shinde_shoes."FactSalesDetail" d
JOIN shinde_shoes."FactSalesMaster" m  ON m."BillNoKey" = d."BillNoKey"
JOIN shinde_shoes."DimDate"         dd ON dd."DateKey"  = m."DateFrKey"
JOIN shinde_shoes."DimProduct"      p  ON p."SKUKey"    = d."SKUKey"
WHERE dd."Fulldate" = DATE '2026-09-26';

-- 7. Stock: sold qty on 26-Sep per store (should match query 4's qty per store),
--    and the stock check (should return 0).
SELECT l."locationName" AS store, SUM(t.quantity) AS sold_qty_in_stock
FROM shinde_shoes.stock_transaction t
JOIN shinde_shoes."DimLocation" l ON l."LocationKey" = t."LocationKey"
WHERE t.movement_type = 'SALE' AND t.transaction_date = DATE '2026-09-26'
GROUP BY 1 ORDER BY 1;

SELECT COUNT(*) AS stock_mismatches FROM shinde_shoes.fn_check_stock_fact_master_reconciliation();

-- 8. Dashboards: the main dashboard view contains 26-Sep, and "today" for dashboards is 26-Sep.
SELECT (SELECT MAX("Fulldate") FROM shinde_shoes.mv_sales_detail_enriched)               AS dashboard_last_date,
       (SELECT COUNT(*) FROM shinde_shoes.mv_sales_detail_enriched
        WHERE "Fulldate" = DATE '2026-09-26')                                              AS dashboard_rows_26sep,
       (SELECT "Fulldate" FROM shinde_shoes."DimDate" WHERE "DayOffset" = 0)              AS dashboard_today,
       (SELECT status || ' at ' || completed_at FROM shinde_shoes.log_refresh
        ORDER BY refresh_id DESC LIMIT 1)                                                  AS last_view_refresh;
