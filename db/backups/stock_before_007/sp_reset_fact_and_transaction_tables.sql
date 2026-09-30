CREATE OR REPLACE PROCEDURE shinde_shoes.sp_reset_fact_and_transaction_tables(IN p_confirm text)
 LANGUAGE plpgsql
AS $procedure$
BEGIN

    IF p_confirm IS DISTINCT FROM 'RESET' THEN
        RAISE EXCEPTION
            'Refusing to run: this TRUNCATEs stock_transaction, stock_fact_master, and purchase_fact_master -- every current stock position and purchase total will be lost. To proceed, call with the exact confirmation text: CALL shinde_shoes.sp_reset_fact_and_transaction_tables(''RESET'');';
    END IF;

    -- All three listed together in one TRUNCATE -- required by Postgres
    -- whenever a table being truncated (stock_transaction) has foreign-key
    -- references pointing at it from other tables (stock_fact_master.
    -- last_transaction_id, purchase_fact_master.last_transaction_id) --
    -- every referencing table has to be truncated in the SAME statement.
    -- RESTART IDENTITY also resets stock_transaction's transaction_id
    -- sequence back to 1, so the next load's transaction_ids start clean.
    TRUNCATE TABLE
        shinde_shoes.stock_transaction,
        shinde_shoes.stock_fact_master,
        shinde_shoes.purchase_fact_master
    RESTART IDENTITY;

    RAISE NOTICE
        'stock_transaction, stock_fact_master, and purchase_fact_master are now empty (transaction_id sequence reset). stg_stock_2/stg_purchase_2/backup tables and every Dim table (including DimProduct) were left untouched -- re-run sp_process_stock_load(<load_id>) / sp_process_purchase_load(<load_id>) for the load_ids you want to re-check.';

END;
$procedure$
;
