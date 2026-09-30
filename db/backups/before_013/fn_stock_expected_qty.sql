CREATE OR REPLACE FUNCTION shinde_shoes.fn_stock_expected_qty()
 RETURNS TABLE(sku_key integer, location_key integer, expected_qty numeric)
 LANGUAGE sql
 STABLE
AS $function$
    WITH last_count AS (
        SELECT "SKUKey", "LocationKey", MAX(transaction_date) AS count_date
        FROM shinde_shoes.stock_transaction
        WHERE movement_type = 'OPENING'
        GROUP BY "SKUKey", "LocationKey"
    )
    SELECT
        t."SKUKey", t."LocationKey",
        SUM(CASE WHEN t.movement_type = 'SALE' THEN -t.quantity ELSE t.quantity END)
    FROM shinde_shoes.stock_transaction t
    LEFT JOIN last_count lc ON lc."SKUKey" = t."SKUKey" AND lc."LocationKey" = t."LocationKey"
    WHERE lc.count_date IS NULL OR t.transaction_date >= lc.count_date
    GROUP BY t."SKUKey", t."LocationKey";
$function$
;
