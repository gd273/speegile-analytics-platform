-- Rollback for 012_reset_stock_and_purchase.sql: puts all cleared rows back and restores the
-- previous sp_reset_fact_and_transaction_tables. Only valid while nothing new was uploaded
-- (it empties the tables first).

BEGIN;

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

INSERT INTO shinde_shoes.stock_transaction OVERRIDING SYSTEM VALUE SELECT * FROM shinde_shoes_backup_012.stock_transaction;
INSERT INTO shinde_shoes.stock_fact_master OVERRIDING SYSTEM VALUE SELECT * FROM shinde_shoes_backup_012.stock_fact_master;
INSERT INTO shinde_shoes.purchase_fact_master OVERRIDING SYSTEM VALUE SELECT * FROM shinde_shoes_backup_012.purchase_fact_master;
INSERT INTO shinde_shoes.stock_count_history OVERRIDING SYSTEM VALUE SELECT * FROM shinde_shoes_backup_012.stock_count_history;
INSERT INTO shinde_shoes.purchase_bill_register OVERRIDING SYSTEM VALUE SELECT * FROM shinde_shoes_backup_012.purchase_bill_register;
INSERT INTO shinde_shoes.stg_stock_1 OVERRIDING SYSTEM VALUE SELECT * FROM shinde_shoes_backup_012.stg_stock_1;
INSERT INTO shinde_shoes.stg_stock_2 OVERRIDING SYSTEM VALUE SELECT * FROM shinde_shoes_backup_012.stg_stock_2;
INSERT INTO shinde_shoes.backup_stg_stock_2 OVERRIDING SYSTEM VALUE SELECT * FROM shinde_shoes_backup_012.backup_stg_stock_2;
INSERT INTO shinde_shoes.stg_purchase_1 OVERRIDING SYSTEM VALUE SELECT * FROM shinde_shoes_backup_012.stg_purchase_1;
INSERT INTO shinde_shoes.stg_purchase_2 OVERRIDING SYSTEM VALUE SELECT * FROM shinde_shoes_backup_012.stg_purchase_2;
INSERT INTO shinde_shoes.backup_stg_purchase_2 OVERRIDING SYSTEM VALUE SELECT * FROM shinde_shoes_backup_012.backup_stg_purchase_2;
INSERT INTO shinde_shoes.validation_error OVERRIDING SYSTEM VALUE SELECT * FROM shinde_shoes_backup_012.validation_error;

CREATE OR REPLACE PROCEDURE shinde_shoes.sp_reset_fact_and_transaction_tables(IN p_confirm text)
 LANGUAGE plpgsql
AS $procedure$
BEGIN
    IF p_confirm IS DISTINCT FROM 'RESET' THEN
        RAISE EXCEPTION
            'Refusing to run: this TRUNCATEs stock_transaction, stock_fact_master, purchase_fact_master and stock_count_history -- every current stock position, purchase total and stock count will be lost. To proceed, call with the exact confirmation text: CALL shinde_shoes.sp_reset_fact_and_transaction_tables(''RESET'');';
    END IF;
    -- Tables with foreign keys to stock_transaction must be truncated in the
    -- same statement. RESTART IDENTITY resets the transaction_id sequence.
    TRUNCATE TABLE
        shinde_shoes.stock_transaction,
        shinde_shoes.stock_fact_master,
        shinde_shoes.purchase_fact_master,
        shinde_shoes.stock_count_history
    RESTART IDENTITY;
    RAISE NOTICE
        'stock_transaction, stock_fact_master, purchase_fact_master and stock_count_history are now empty (transaction_id sequence reset). stg_stock_2/stg_purchase_2/backup tables and every Dim table (including DimProduct) were left untouched -- re-run sp_process_stock_load(<load_id>) / sp_process_purchase_load(<load_id>), then CALL sp_rebuild_stock_fact_master().';
END;
$procedure$
;


COMMIT;

-- Once you are sure, drop the backup:
-- DROP SCHEMA shinde_shoes_backup_012 CASCADE;
