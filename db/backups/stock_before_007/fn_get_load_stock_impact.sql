CREATE OR REPLACE FUNCTION shinde_shoes.fn_get_load_stock_impact(p_load_id integer)
 RETURNS TABLE("SKU" character varying, "LocationKey" integer, movement_type character varying, qty_posted_by_this_load numeric, current_qty_now numeric, computed_qty_from_full_ledger numeric, reconciliation_status text)
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
        dp."SKU",
        st."LocationKey",
        st.movement_type,
        SUM(st.quantity)                     AS qty_posted_by_this_load,
        sfm.current_qty                      AS current_qty_now,
        full_ledger.computed_qty             AS computed_qty_from_full_ledger,
        CASE
            WHEN sfm.current_qty = full_ledger.computed_qty THEN 'OK'
            ELSE 'MISMATCH'
        END                                   AS reconciliation_status
    FROM shinde_shoes.stock_transaction st
    JOIN shinde_shoes."DimProduct" dp
        ON dp."SKUKey" = st."SKUKey"
    LEFT JOIN latest_sfm sfm
        ON sfm."SKUKey" = st."SKUKey" AND sfm."LocationKey" = st."LocationKey"
    LEFT JOIN LATERAL (
        SELECT SUM(CASE WHEN movement_type = 'SALE' THEN -quantity ELSE quantity END) AS computed_qty
        FROM shinde_shoes.stock_transaction all_st
        WHERE all_st."SKUKey" = st."SKUKey" AND all_st."LocationKey" = st."LocationKey"
    ) full_ledger ON true
    WHERE st.load_id = p_load_id
    GROUP BY dp."SKU", st."LocationKey", st.movement_type,
             sfm.current_qty, full_ledger.computed_qty
    ORDER BY dp."SKU", st."LocationKey";
$function$
;
