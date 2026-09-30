CREATE OR REPLACE FUNCTION shinde_shoes."Fn_Validate_Category"(categoryname character varying, categorycode character varying, v_sku character varying)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE 
  v_CategoryKey int;
  v_sku_exists BIGINT;
BEGIN
  -- -- -- Check if SKU exists in staging table
  -- SELECT COUNT(*) INTO v_sku_exists
  -- FROM "Stagging_Tables"."sales_data"
  -- WHERE "SKU" = V_SKU;
  
  -- -- -- If SKU EXISTS, return 1
  -- IF v_sku_exists > 0 THEN
  --   RETURN 1;
  -- END IF;
  
  -- SKU DOESN'T EXIST, check if CategoryName is valid
  IF CategoryName IS NULL
    OR TRIM(CategoryName) = ''
    OR CategoryName = '0'
  THEN 
    RETURN 0;
  END IF;
  
  -- Check if CategoryCode is valid
  IF CategoryCode IS NULL
    OR TRIM(CategoryCode) = ''
    OR CategoryCode = '0'
  THEN 
    RETURN 0;
  END IF;
  
  -- Both CategoryName and CategoryCode are valid, insert them
  INSERT INTO "shinde_shoes"."DimCategory" 
    ("CategoryName", "CategoryCode")
  VALUES 
    (TRIM(CategoryName), COALESCE(NULLIF(TRIM(CategoryCode), ''), '0'))
  ON CONFLICT ("CategoryName") DO NOTHING;
  
  -- Fetch the CategoryKey
  SELECT "CategoryKey"
  INTO v_CategoryKey
  FROM "shinde_shoes"."DimCategory"
  WHERE "CategoryName" = TRIM(CategoryName);
  
  -- Return the CategoryKey or 0 if not found
  RETURN COALESCE(v_CategoryKey, 0);
END;
$function$
;
