-- 002_shinde_indexes.sql
-- Adds missing indexes and removes exact duplicate indexes in shinde_shoes.
--
-- Run WITHOUT a surrounding transaction: CREATE/DROP INDEX CONCURRENTLY cannot run
-- inside BEGIN/COMMIT. In psql run it as-is (autocommit is the default).
-- CONCURRENTLY builds/drops without blocking reads or writes on the table.
-- Safe to run more than once (IF [NOT] EXISTS everywhere).
-- Rollback: 002_shinde_indexes_rollback.sql

-- ── 1. New indexes ──────────────────────────────────────────────────────────

-- Sales date check before each upload filters FactSalesMaster by store, then takes the max date.
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_fsm_location_date
    ON shinde_shoes."FactSalesMaster" ("LocationFrKey", "DateFrKey");

-- FactSalesDetail."SKUKey" is a foreign key with no index (lookups by product scan the whole table).
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_fsd_skukey
    ON shinde_shoes."FactSalesDetail" ("SKUKey");

-- Dashboards filter the enriched sales view by store and date range.
-- Indexes on a materialized view are kept and rebuilt by REFRESH.
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_mvsde_location_fulldate
    ON shinde_shoes.mv_sales_detail_enriched ("locationName", "Fulldate");

CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_mvsde_fulldate
    ON shinde_shoes.mv_sales_detail_enriched ("Fulldate");

-- ── 2. Drop exact duplicates (each has an identical index that stays) ─────────
-- Checked: no foreign key, procedure, function or view refers to these names.

-- Plain indexes that duplicate another index on the same columns.
DROP INDEX CONCURRENTLY IF EXISTS shinde_shoes.idx_dimdate_fulldate;      -- kept: uq_dimdate_fulldate
DROP INDEX CONCURRENTLY IF EXISTS shinde_shoes.idx_dimlocation_name;      -- kept: "DimLocation_locationName_key"
DROP INDEX CONCURRENTLY IF EXISTS shinde_shoes.idx_fact_ogbill_date_loc;  -- kept: idx_fsm_og_billno_date_loc
DROP INDEX CONCURRENTLY IF EXISTS shinde_shoes.idx_fact_billno;           -- kept: "FactSalesMaster_BillNo_key"
DROP INDEX CONCURRENTLY IF EXISTS shinde_shoes.idx_fsm_billno;            -- kept: "FactSalesMaster_BillNo_key"

-- Second UNIQUE constraint on the same column (the original "<table>_<col>_key" stays).
-- These take a brief lock on small dimension tables.
ALTER TABLE shinde_shoes."DimColour"      DROP CONSTRAINT IF EXISTS uq_dimcolour_name;
ALTER TABLE shinde_shoes."DimCustomer"    DROP CONSTRAINT IF EXISTS uq_dimcustomer_mobileno;
ALTER TABLE shinde_shoes."DimLocation"    DROP CONSTRAINT IF EXISTS uq_dimlocation_name;
ALTER TABLE shinde_shoes."DimProductCode" DROP CONSTRAINT IF EXISTS uq_dimproductcode_code;
ALTER TABLE shinde_shoes."DimSalesPerson" DROP CONSTRAINT IF EXISTS uq_dimsalesperson_name;
ALTER TABLE shinde_shoes."DimSize"        DROP CONSTRAINT IF EXISTS uq_dimsize_name;

-- ── 3. Refresh planner statistics ─────────────────────────────────────────────
ANALYZE shinde_shoes."FactSalesMaster";
ANALYZE shinde_shoes."FactSalesDetail";
ANALYZE shinde_shoes.mv_sales_detail_enriched;
