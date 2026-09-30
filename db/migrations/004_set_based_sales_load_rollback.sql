-- Rollback for 004_set_based_sales_load.sql
-- Point the backend back at the old procedure first:
--   tenants_handler.py -> CALL sp_batch_insert_dummy_to_stagging_to_dim(200000, 1, 0)
-- The old procedures were never changed by 004, so nothing else needs restoring.

DROP PROCEDURE IF EXISTS shinde_shoes.sp_load_sales_set();
