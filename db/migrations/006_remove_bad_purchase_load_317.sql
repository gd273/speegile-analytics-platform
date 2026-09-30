-- 006_remove_bad_purchase_load_317.sql
-- Removes Purchase load 317 (shindeshoes_purchase_Mis_Purchase_Summary07_09_2026_-_14_09_2026.csv,
-- bills dated 07-Sep..14-Sep-2026). Excel had turned every SKU in that CSV into "1.01E+11",
-- so all 2,250 purchased pieces were posted to one fake product (SKUKey 216905) instead of
-- the real SKUs. Re-upload the file after re-exporting it with the SKU column as text.
--
-- Every row removed is saved first in shinde_shoes.backup_*_006 tables.
-- Rollback: 006_remove_bad_purchase_load_317_rollback.sql (puts them back exactly).

BEGIN;

-- Stop if the data is not what this script expects.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM shinde_shoes."DimProduct"
                   WHERE "SKUKey" = 216905 AND "SKU" = '1.01E+11') THEN
        RAISE EXCEPTION 'SKUKey 216905 is not the fake product 1.01E+11 -- stopping.';
    END IF;
    IF EXISTS (SELECT 1 FROM shinde_shoes.stock_transaction
               WHERE "SKUKey" = 216905 AND load_id IS DISTINCT FROM 317)
       OR EXISTS (SELECT 1 FROM shinde_shoes."FactSalesDetail" WHERE "SKUKey" = 216905) THEN
        RAISE EXCEPTION 'SKUKey 216905 is used outside load 317 -- stopping.';
    END IF;
END $$;

CREATE TABLE shinde_shoes.backup_stock_fact_master_006    AS SELECT * FROM shinde_shoes.stock_fact_master    WHERE "SKUKey" = 216905;
CREATE TABLE shinde_shoes.backup_purchase_fact_master_006 AS SELECT * FROM shinde_shoes.purchase_fact_master WHERE "SKUKey" = 216905;
CREATE TABLE shinde_shoes.backup_stock_transaction_006    AS SELECT * FROM shinde_shoes.stock_transaction    WHERE load_id = 317;
CREATE TABLE shinde_shoes.backup_dimproduct_006           AS SELECT * FROM shinde_shoes."DimProduct"         WHERE "SKUKey" = 216905;
CREATE TABLE shinde_shoes.backup_stg_purchase_1_006       AS SELECT * FROM shinde_shoes.stg_purchase_1       WHERE load_id = 317;
CREATE TABLE shinde_shoes.backup_stg_purchase_2_006       AS SELECT * FROM shinde_shoes.stg_purchase_2       WHERE load_id = 317;
CREATE TABLE shinde_shoes.backup_backup_stg_purchase_2_006 AS SELECT * FROM shinde_shoes.backup_stg_purchase_2 WHERE load_id = 317;
CREATE TABLE shinde_shoes.backup_load_master_006          AS SELECT * FROM public.load_master                WHERE id = 317;

-- Fact rows first: they point at stock_transaction and DimProduct.
DELETE FROM shinde_shoes.stock_fact_master     WHERE "SKUKey" = 216905;
DELETE FROM shinde_shoes.purchase_fact_master  WHERE "SKUKey" = 216905;
DELETE FROM shinde_shoes.stock_transaction     WHERE load_id = 317;
DELETE FROM shinde_shoes."DimProduct"          WHERE "SKUKey" = 216905;
DELETE FROM shinde_shoes.stg_purchase_1        WHERE load_id = 317;
DELETE FROM shinde_shoes.stg_purchase_2        WHERE load_id = 317;
DELETE FROM shinde_shoes.backup_stg_purchase_2 WHERE load_id = 317;

-- Keep the load in the history, marked as failed with the reason.
UPDATE public.load_master SET status = 'Fail' WHERE id = 317;
INSERT INTO public.load_errors (load_id, error_message)
VALUES (317, 'Removed on 2026-09-30: the SKU column was corrupted by Excel (every SKU read as 1.01E+11). Re-upload the file with the SKU column formatted as text.');

COMMIT;

-- Check: all of these should be 0.
-- SELECT (SELECT count(*) FROM shinde_shoes.stock_transaction WHERE load_id = 317)  AS txns,
--        (SELECT count(*) FROM shinde_shoes."DimProduct" WHERE "SKU" = '1.01E+11')    AS fake_sku;
