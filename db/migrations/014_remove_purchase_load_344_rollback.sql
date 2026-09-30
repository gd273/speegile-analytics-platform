-- Rollback for 014_remove_purchase_load_344.sql: puts load 344 back exactly.
-- Only valid before load 344's bills are uploaded again.

BEGIN;

INSERT INTO shinde_shoes.stock_transaction      OVERRIDING SYSTEM VALUE SELECT * FROM shinde_shoes.backup_stock_transaction_014;
INSERT INTO shinde_shoes.purchase_fact_master   OVERRIDING SYSTEM VALUE SELECT * FROM shinde_shoes.backup_purchase_fact_master_014;
INSERT INTO shinde_shoes.purchase_bill_register OVERRIDING SYSTEM VALUE SELECT * FROM shinde_shoes.backup_purchase_bill_register_014;
INSERT INTO shinde_shoes.stg_purchase_1         OVERRIDING SYSTEM VALUE SELECT * FROM shinde_shoes.backup_stg_purchase_1_014;
INSERT INTO shinde_shoes.stg_purchase_2         OVERRIDING SYSTEM VALUE SELECT * FROM shinde_shoes.backup_stg_purchase_2_014;
INSERT INTO shinde_shoes.backup_stg_purchase_2  OVERRIDING SYSTEM VALUE SELECT * FROM shinde_shoes.backup_backup_stg_purchase_2_014;
INSERT INTO shinde_shoes.validation_error       OVERRIDING SYSTEM VALUE SELECT * FROM shinde_shoes.backup_validation_error_014;

CALL shinde_shoes.sp_rebuild_stock_fact_master(NULL);

UPDATE public.load_master m SET status = b.status
FROM   shinde_shoes.backup_load_master_014 b WHERE m.id = b.id;
DELETE FROM public.load_errors
WHERE  load_id = 344 AND error_message LIKE 'Removed on 2026-09-30%';

COMMIT;

-- Once you are sure, drop the backup tables:
-- DROP TABLE shinde_shoes.backup_purchase_fact_master_014, shinde_shoes.backup_stock_transaction_014,
--            shinde_shoes.backup_purchase_bill_register_014, shinde_shoes.backup_stg_purchase_1_014,
--            shinde_shoes.backup_stg_purchase_2_014, shinde_shoes.backup_backup_stg_purchase_2_014,
--            shinde_shoes.backup_validation_error_014, shinde_shoes.backup_load_master_014;
