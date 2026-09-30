CREATE OR REPLACE FUNCTION shinde_shoes.fn_check_stock_fact_master_reconciliation()
 RETURNS TABLE("SKUKey" integer, "SKU" character varying, "LocationKey" integer, stored_current_qty numeric, computed_from_ledger numeric, mismatch numeric)
 LANGUAGE sql
 STABLE
AS $function$
    WITH latest_sfm AS (
        SELECT DISTINCT ON ("SKUKey", "LocationKey")
            "SKUKey", "LocationKey", current_qty
        FROM shinde_shoes.stock_fact_master
        ORDER BY "SKUKey", "LocationKey", last_date DESC
    )
    SELECT
        sfm."SKUKey",
        dp."SKU",
        sfm."LocationKey",
        sfm.current_qty                              AS stored_current_qty,
        COALESCE(t.computed_qty, 0)                  AS computed_from_ledger,
        sfm.current_qty - COALESCE(t.computed_qty, 0) AS mismatch
    FROM latest_sfm sfm
    JOIN shinde_shoes."DimProduct" dp ON dp."SKUKey" = sfm."SKUKey"
    LEFT JOIN (
        SELECT "SKUKey", "LocationKey",
               SUM(CASE WHEN movement_type = 'SALE' THEN -quantity ELSE quantity END) AS computed_qty
        FROM shinde_shoes.stock_transaction
        GROUP BY "SKUKey", "LocationKey"
    ) t ON t."SKUKey" = sfm."SKUKey" AND t."LocationKey" = sfm."LocationKey"
    WHERE sfm.current_qty <> COALESCE(t.computed_qty, 0);
$function$
;
