-- Rollback for 002_shinde_indexes.sql (definitions captured from the local DB before the change).
-- Run without a surrounding transaction (uses CONCURRENTLY).

-- Remove the new indexes
DROP INDEX CONCURRENTLY IF EXISTS shinde_shoes.ix_fsm_location_date;
DROP INDEX CONCURRENTLY IF EXISTS shinde_shoes.ix_fsd_skukey;
DROP INDEX CONCURRENTLY IF EXISTS shinde_shoes.ix_mvsde_location_fulldate;
DROP INDEX CONCURRENTLY IF EXISTS shinde_shoes.ix_mvsde_fulldate;

-- Recreate the dropped plain indexes
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_dimdate_fulldate ON shinde_shoes."DimDate" USING btree ("Fulldate");
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_dimlocation_name ON shinde_shoes."DimLocation" USING btree ("locationName");
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_fact_ogbill_date_loc ON shinde_shoes."FactSalesMaster" USING btree ("Og_BillNo", "DateFrKey", "LocationFrKey");
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_fact_billno ON shinde_shoes."FactSalesMaster" USING btree ("BillNo");
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_fsm_billno ON shinde_shoes."FactSalesMaster" USING btree ("BillNo");

-- Recreate the dropped duplicate UNIQUE constraints
ALTER TABLE shinde_shoes."DimColour" ADD CONSTRAINT uq_dimcolour_name UNIQUE ("ColourName");
ALTER TABLE shinde_shoes."DimCustomer" ADD CONSTRAINT uq_dimcustomer_mobileno UNIQUE ("MobileNo");
ALTER TABLE shinde_shoes."DimLocation" ADD CONSTRAINT uq_dimlocation_name UNIQUE ("locationName");
ALTER TABLE shinde_shoes."DimProductCode" ADD CONSTRAINT uq_dimproductcode_code UNIQUE ("ProductCodeName");
ALTER TABLE shinde_shoes."DimSalesPerson" ADD CONSTRAINT uq_dimsalesperson_name UNIQUE ("SalesPersonName");
ALTER TABLE shinde_shoes."DimSize" ADD CONSTRAINT uq_dimsize_name UNIQUE ("SizeName");
