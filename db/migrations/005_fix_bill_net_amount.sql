-- 005_fix_bill_net_amount.sql
-- Corrects FactSalesMaster."BILLNetAmount" for bills loaded by the old row-by-row procedure,
-- which stored the PREVIOUS bill's running total. After this, BILLNetAmount = sum of the
-- bill's lines in FactSalesDetail (what sp_load_sales_set() writes for new loads).
-- Affects vw_CY_PY_Monthly_Sales_store, the only object that reads BILLNetAmount.
-- Bills with no lines are left unchanged.
--
-- The current values are saved first in shinde_shoes.backup_bill_net_amount_005.
-- Rollback: 005_fix_bill_net_amount_rollback.sql (restores them exactly).

BEGIN;

CREATE TABLE IF NOT EXISTS shinde_shoes.backup_bill_net_amount_005 AS
SELECT "BillNoKey", "BILLNetAmount", now() AS saved_at
FROM   shinde_shoes."FactSalesMaster";

UPDATE shinde_shoes."FactSalesMaster" m
SET    "BILLNetAmount" = d.total
FROM  (SELECT "BillNoKey", SUM("NetAmount") AS total
       FROM   shinde_shoes."FactSalesDetail"
       GROUP  BY "BillNoKey") d
WHERE  m."BillNoKey" = d."BillNoKey"
  AND  m."BILLNetAmount" IS DISTINCT FROM d.total;

COMMIT;

-- Check: every bill with lines should now match.
-- SELECT count(*) AS bills, count(*) FILTER (WHERE m."BILLNetAmount" = d.total) AS correct
-- FROM shinde_shoes."FactSalesMaster" m
-- JOIN (SELECT "BillNoKey", SUM("NetAmount") total FROM shinde_shoes."FactSalesDetail" GROUP BY 1) d USING ("BillNoKey");
