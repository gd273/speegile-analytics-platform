-- 008_remove_sales_from_2026_08_21.sql
-- Removes every sale dated 21-Aug-2026 or later (all stores) so the sales files can be
-- uploaded again from that date. The 21-Aug..31-Aug file had its SKU column turned into
-- "1.0128E+11" by Excel, which put 2,036 sale lines on one fake product.
--
-- Removed: FactSalesMaster bills + their FactSalesDetail lines from 21-Aug-2026, their
-- 'SALE' rows in stock_transaction, and the fake product 1.0128E+11 (SKUKey 208844).
-- stock_fact_master is rebuilt and the DimDate offsets are set to the new latest date.
-- Dimension rows (customers, products, ...) created by these bills are kept.
--
-- Everything removed is saved first in shinde_shoes.backup_*_008 tables.
-- Rollback: 008_remove_sales_from_2026_08_21_rollback.sql
--
-- After COMMIT, refresh the dashboards' views (cannot run inside this transaction):
--   CALL shinde_shoes.refresh_all_mvs();

BEGIN;

CREATE TABLE shinde_shoes.backup_factsalesmaster_008 AS
SELECT m.*
FROM   shinde_shoes."FactSalesMaster" m
JOIN   shinde_shoes."DimDate" dd ON dd."DateKey" = m."DateFrKey"
WHERE  dd."Fulldate" >= DATE '2026-08-21';

CREATE TABLE shinde_shoes.backup_factsalesdetail_008 AS
SELECT d.*
FROM   shinde_shoes."FactSalesDetail" d
WHERE  d."BillNoKey" IN (SELECT "BillNoKey" FROM shinde_shoes.backup_factsalesmaster_008);

CREATE TABLE shinde_shoes.backup_stock_transaction_008 AS
SELECT * FROM shinde_shoes.stock_transaction
WHERE  movement_type = 'SALE' AND transaction_date >= DATE '2026-08-21';

CREATE TABLE shinde_shoes.backup_stock_fact_master_008 AS
SELECT * FROM shinde_shoes.stock_fact_master;

CREATE TABLE shinde_shoes.backup_dimproduct_008 AS
SELECT * FROM shinde_shoes."DimProduct" WHERE "SKU" = '1.0128E+11';

-- Stock: drop the sales movements, then rebuild the balances
UPDATE shinde_shoes.stock_fact_master
SET    last_transaction_id = NULL
WHERE  last_transaction_id IN (SELECT transaction_id FROM shinde_shoes.backup_stock_transaction_008);

DELETE FROM shinde_shoes.stock_transaction
WHERE  transaction_id IN (SELECT transaction_id FROM shinde_shoes.backup_stock_transaction_008);

-- Sales
DELETE FROM shinde_shoes."FactSalesDetail"
WHERE  "BillNoKey" IN (SELECT "BillNoKey" FROM shinde_shoes.backup_factsalesmaster_008);

DELETE FROM shinde_shoes."FactSalesMaster"
WHERE  "BillNoKey" IN (SELECT "BillNoKey" FROM shinde_shoes.backup_factsalesmaster_008);

-- The fake product; stop if anything still uses it
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM shinde_shoes."FactSalesDetail" d
               JOIN shinde_shoes."DimProduct" p USING ("SKUKey")
               WHERE p."SKU" = '1.0128E+11')
       OR EXISTS (SELECT 1 FROM shinde_shoes.stock_transaction t
                  JOIN shinde_shoes."DimProduct" p USING ("SKUKey")
                  WHERE p."SKU" = '1.0128E+11') THEN
        RAISE EXCEPTION 'Product 1.0128E+11 is still used by other rows -- stopping.';
    END IF;
END $$;

DELETE FROM shinde_shoes."DimProduct" WHERE "SKU" = '1.0128E+11';

CALL shinde_shoes.sp_rebuild_stock_fact_master(NULL);

-- "Today" for the dashboards' date offsets = the latest sale date left
DO $$
DECLARE v_max date;
BEGIN
    SELECT MAX(dd."Fulldate") INTO v_max
    FROM   shinde_shoes."FactSalesMaster" m
    JOIN   shinde_shoes."DimDate" dd ON dd."DateKey" = m."DateFrKey";
    CALL shinde_shoes.refresh_dimdate_offsets(v_max);
    RAISE NOTICE 'DimDate offsets set to %', v_max;
END $$;

COMMIT;

-- Checks
-- SELECT MAX(dd."Fulldate") FROM shinde_shoes."FactSalesMaster" m
-- JOIN shinde_shoes."DimDate" dd ON dd."DateKey" = m."DateFrKey";                  -- 2026-08-20
-- SELECT count(*) FROM shinde_shoes.stock_transaction WHERE movement_type = 'SALE'; -- 0
-- SELECT count(*) FROM shinde_shoes.fn_check_stock_fact_master_reconciliation();    -- 0
