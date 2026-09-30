-- Rollback for 006_remove_bad_purchase_load_317.sql: puts load 317's rows back exactly.
-- Run it before 007 is applied (or after rolling 007 back).

BEGIN;

INSERT INTO shinde_shoes."DimProduct"         SELECT * FROM shinde_shoes.backup_dimproduct_006;
INSERT INTO shinde_shoes.stock_transaction OVERRIDING SYSTEM VALUE
                                              SELECT * FROM shinde_shoes.backup_stock_transaction_006;
INSERT INTO shinde_shoes.stock_fact_master    SELECT * FROM shinde_shoes.backup_stock_fact_master_006;
INSERT INTO shinde_shoes.purchase_fact_master SELECT * FROM shinde_shoes.backup_purchase_fact_master_006;
INSERT INTO shinde_shoes.stg_purchase_1       SELECT * FROM shinde_shoes.backup_stg_purchase_1_006;
INSERT INTO shinde_shoes.stg_purchase_2       SELECT * FROM shinde_shoes.backup_stg_purchase_2_006;
INSERT INTO shinde_shoes.backup_stg_purchase_2 OVERRIDING SYSTEM VALUE
                                              SELECT * FROM shinde_shoes.backup_backup_stg_purchase_2_006;

UPDATE public.load_master m SET status = b.status
FROM   shinde_shoes.backup_load_master_006 b WHERE m.id = b.id;
DELETE FROM public.load_errors
WHERE  load_id = 317 AND error_message LIKE 'Removed on 2026-09-30:%';

COMMIT;

-- Once you are sure, drop the backup tables:
-- DROP TABLE shinde_shoes.backup_stock_fact_master_006, shinde_shoes.backup_purchase_fact_master_006,
--            shinde_shoes.backup_stock_transaction_006, shinde_shoes.backup_dimproduct_006,
--            shinde_shoes.backup_stg_purchase_1_006, shinde_shoes.backup_stg_purchase_2_006,
--            shinde_shoes.backup_backup_stg_purchase_2_006, shinde_shoes.backup_load_master_006;
