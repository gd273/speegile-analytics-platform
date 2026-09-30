-- Rollback for 008_remove_sales_from_2026_08_21.sql: puts the removed sales, their stock
-- movements and the fake product back exactly, and restores stock_fact_master.
-- Only valid while no new sales from 21-Aug-2026 have been uploaded.
-- After COMMIT: CALL shinde_shoes.refresh_all_mvs();

BEGIN;

INSERT INTO shinde_shoes."DimProduct"      SELECT * FROM shinde_shoes.backup_dimproduct_008;
INSERT INTO shinde_shoes."FactSalesMaster" SELECT * FROM shinde_shoes.backup_factsalesmaster_008;
INSERT INTO shinde_shoes."FactSalesDetail" SELECT * FROM shinde_shoes.backup_factsalesdetail_008;
INSERT INTO shinde_shoes.stock_transaction OVERRIDING SYSTEM VALUE
SELECT * FROM shinde_shoes.backup_stock_transaction_008;

DELETE FROM shinde_shoes.stock_fact_master;
INSERT INTO shinde_shoes.stock_fact_master SELECT * FROM shinde_shoes.backup_stock_fact_master_008;

DO $$
DECLARE v_max date;
BEGIN
    SELECT MAX(dd."Fulldate") INTO v_max
    FROM   shinde_shoes."FactSalesMaster" m
    JOIN   shinde_shoes."DimDate" dd ON dd."DateKey" = m."DateFrKey";
    CALL shinde_shoes.refresh_dimdate_offsets(v_max);
END $$;

COMMIT;

-- Once you are sure, drop the backup tables:
-- DROP TABLE shinde_shoes.backup_factsalesmaster_008, shinde_shoes.backup_factsalesdetail_008,
--            shinde_shoes.backup_stock_transaction_008, shinde_shoes.backup_stock_fact_master_008,
--            shinde_shoes.backup_dimproduct_008;
