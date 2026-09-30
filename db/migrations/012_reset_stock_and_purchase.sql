-- 012_reset_stock_and_purchase.sql
-- Empties all stock and purchase data of shinde_shoes so every stock and purchase file can be
-- uploaded again from scratch (sales from 21-Aug-2026 are re-uploaded too, see 008).
--
-- Cleared: stock movements, stock balances, stock count history, purchase totals, the
-- purchase bill register (else the 01-06 Sep purchases would be rejected as duplicates),
-- the stock / purchase staging tables and validation_error.
-- Kept:    all sales (FactSalesMaster / FactSalesDetail, up to 20-Aug-2026), products and
--          every other Dim table, load_master history.
-- The kept sales are all posted_to_stock = true, so they will not be subtracted again.
--
-- sp_reset_fact_and_transaction_tables now also clears purchase_bill_register.
--
-- Everything cleared is copied first into schema shinde_shoes_backup_012.
-- Rollback: 012_reset_stock_and_purchase_rollback.sql (only before new files are uploaded).

BEGIN;

CREATE SCHEMA shinde_shoes_backup_012;
CREATE TABLE shinde_shoes_backup_012.stock_transaction        AS SELECT * FROM shinde_shoes.stock_transaction;
CREATE TABLE shinde_shoes_backup_012.stock_fact_master        AS SELECT * FROM shinde_shoes.stock_fact_master;
CREATE TABLE shinde_shoes_backup_012.purchase_fact_master     AS SELECT * FROM shinde_shoes.purchase_fact_master;
CREATE TABLE shinde_shoes_backup_012.stock_count_history      AS SELECT * FROM shinde_shoes.stock_count_history;
CREATE TABLE shinde_shoes_backup_012.purchase_bill_register   AS SELECT * FROM shinde_shoes.purchase_bill_register;
CREATE TABLE shinde_shoes_backup_012.stg_stock_1              AS SELECT * FROM shinde_shoes.stg_stock_1;
CREATE TABLE shinde_shoes_backup_012.stg_stock_2              AS SELECT * FROM shinde_shoes.stg_stock_2;
CREATE TABLE shinde_shoes_backup_012.backup_stg_stock_2       AS SELECT * FROM shinde_shoes.backup_stg_stock_2;
CREATE TABLE shinde_shoes_backup_012.stg_purchase_1           AS SELECT * FROM shinde_shoes.stg_purchase_1;
CREATE TABLE shinde_shoes_backup_012.stg_purchase_2           AS SELECT * FROM shinde_shoes.stg_purchase_2;
CREATE TABLE shinde_shoes_backup_012.backup_stg_purchase_2    AS SELECT * FROM shinde_shoes.backup_stg_purchase_2;
CREATE TABLE shinde_shoes_backup_012.validation_error         AS SELECT * FROM shinde_shoes.validation_error;

-- No RESTART IDENTITY: ids keep counting up, so the rollback can put the old rows back.
TRUNCATE TABLE
    shinde_shoes.stock_transaction,
    shinde_shoes.stock_fact_master,
    shinde_shoes.purchase_fact_master,
    shinde_shoes.stock_count_history,
    shinde_shoes.purchase_bill_register,
    shinde_shoes.stg_stock_1,
    shinde_shoes.stg_stock_2,
    shinde_shoes.backup_stg_stock_2,
    shinde_shoes.stg_purchase_1,
    shinde_shoes.stg_purchase_2,
    shinde_shoes.backup_stg_purchase_2,
    shinde_shoes.validation_error;

CREATE OR REPLACE PROCEDURE shinde_shoes.sp_reset_fact_and_transaction_tables(IN p_confirm text)
 LANGUAGE plpgsql
AS $procedure$
BEGIN
    IF p_confirm IS DISTINCT FROM 'RESET' THEN
        RAISE EXCEPTION
            'Refusing to run: this TRUNCATEs stock_transaction, stock_fact_master, purchase_fact_master, stock_count_history and purchase_bill_register -- every current stock position, purchase total, stock count and purchase bill record will be lost. To proceed, call with the exact confirmation text: CALL shinde_shoes.sp_reset_fact_and_transaction_tables(''RESET'');';
    END IF;
    -- Tables with foreign keys to stock_transaction must be truncated in the
    -- same statement. RESTART IDENTITY resets the transaction_id sequence.
    TRUNCATE TABLE
        shinde_shoes.stock_transaction,
        shinde_shoes.stock_fact_master,
        shinde_shoes.purchase_fact_master,
        shinde_shoes.stock_count_history,
        shinde_shoes.purchase_bill_register
    RESTART IDENTITY;
    RAISE NOTICE
        'stock_transaction, stock_fact_master, purchase_fact_master, stock_count_history and purchase_bill_register are now empty (transaction_id sequence reset). stg_stock_2/stg_purchase_2/backup tables and every Dim table (including DimProduct) were left untouched -- re-run sp_process_stock_load(<load_id>) / sp_process_purchase_load(<load_id>), then CALL sp_rebuild_stock_fact_master().';
END;
$procedure$;

COMMIT;
