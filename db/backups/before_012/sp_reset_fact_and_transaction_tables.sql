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
