-- 014_remove_purchase_load_344.sql
-- Removes purchase load 344 (shindeshoes_purchase_Mis_Purchase_Summary01_09_2026_-_06-09-2026_v1.csv,
-- 19 bills / 777 rows, 01-06 Sep 2026) so the purchase files can be uploaded again.
-- Products it added to DimProduct are kept (a re-upload reuses them).
--
-- Everything removed is saved first in shinde_shoes.backup_*_014 tables.
-- Rollback: 014_remove_purchase_load_344_rollback.sql (only before load 344's bills are uploaded again).

BEGIN;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM shinde_shoes.purchase_fact_master
               WHERE created_by = 'load_344' AND last_updated_by IS DISTINCT FROM 'load_344') THEN
        RAISE EXCEPTION 'purchase_fact_master rows of load 344 were updated by another load -- stopping.';
    END IF;
END $$;

CREATE TABLE shinde_shoes.backup_purchase_fact_master_014   AS SELECT * FROM shinde_shoes.purchase_fact_master   WHERE created_by = 'load_344';
CREATE TABLE shinde_shoes.backup_stock_transaction_014      AS SELECT * FROM shinde_shoes.stock_transaction      WHERE load_id = 344;
CREATE TABLE shinde_shoes.backup_purchase_bill_register_014 AS SELECT * FROM shinde_shoes.purchase_bill_register WHERE load_id = 344;
CREATE TABLE shinde_shoes.backup_stg_purchase_1_014         AS SELECT * FROM shinde_shoes.stg_purchase_1         WHERE load_id = 344;
CREATE TABLE shinde_shoes.backup_stg_purchase_2_014         AS SELECT * FROM shinde_shoes.stg_purchase_2         WHERE load_id = 344;
CREATE TABLE shinde_shoes.backup_backup_stg_purchase_2_014  AS SELECT * FROM shinde_shoes.backup_stg_purchase_2  WHERE load_id = 344;
CREATE TABLE shinde_shoes.backup_validation_error_014       AS SELECT * FROM shinde_shoes.validation_error       WHERE load_id = 344;
CREATE TABLE shinde_shoes.backup_load_master_014            AS SELECT * FROM public.load_master                  WHERE id = 344;

-- Rows pointing at stock_transaction first
DELETE FROM shinde_shoes.purchase_fact_master WHERE created_by = 'load_344';
UPDATE shinde_shoes.stock_fact_master
SET    last_transaction_id = NULL
WHERE  last_transaction_id IN (SELECT transaction_id FROM shinde_shoes.backup_stock_transaction_014);
DELETE FROM shinde_shoes.stock_transaction      WHERE load_id = 344;
DELETE FROM shinde_shoes.purchase_bill_register WHERE load_id = 344;
DELETE FROM shinde_shoes.stg_purchase_1         WHERE load_id = 344;
DELETE FROM shinde_shoes.stg_purchase_2         WHERE load_id = 344;
DELETE FROM shinde_shoes.backup_stg_purchase_2  WHERE load_id = 344;
DELETE FROM shinde_shoes.validation_error       WHERE load_id = 344;

CALL shinde_shoes.sp_rebuild_stock_fact_master(NULL);

-- Keep the load in the history, marked as removed
UPDATE public.load_master SET status = 'Fail' WHERE id = 344;
INSERT INTO public.load_errors (load_id, error_message)
VALUES (344, 'Removed on 2026-09-30 so the purchase files can be uploaded again.');

COMMIT;
