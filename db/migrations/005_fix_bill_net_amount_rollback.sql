-- Rollback for 005_fix_bill_net_amount.sql: restores the saved BILLNetAmount values exactly.

BEGIN;

UPDATE shinde_shoes."FactSalesMaster" m
SET    "BILLNetAmount" = b."BILLNetAmount"
FROM   shinde_shoes.backup_bill_net_amount_005 b
WHERE  m."BillNoKey" = b."BillNoKey"
  AND  m."BILLNetAmount" IS DISTINCT FROM b."BILLNetAmount";

COMMIT;

-- Once you are sure the fix is right, drop the backup table:
-- DROP TABLE shinde_shoes.backup_bill_net_amount_005;
