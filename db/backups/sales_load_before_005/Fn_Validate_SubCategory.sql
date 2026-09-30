CREATE OR REPLACE FUNCTION shinde_shoes."Fn_Validate_SubCategory"(categorykey integer, subcategorycode character varying, subcategorydesc character varying, v_sku character varying)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
declare 
v_SubCategoryKey int;
v_sku_exists int;
begin

-- -- -- Check if SKU exists in staging table
--   SELECT COUNT(*) INTO v_sku_exists
--   FROM "Stagging_Tables"."sales_data"
--   WHERE "SKU" = V_SKU;
  
-- --   -- If SKU EXISTS, return 1
--   IF v_sku_exists > 0 THEN
--     RETURN 1;
--   END IF;
  
--  Check SubCategoryName Is Empty 
if SubCategoryDesc is null
or trim(SubCategoryDesc) = ''
or SubCategoryDesc = '0'
then 
	return 0;
end if;

--  Check SubCategoryCode Is Empty 
if SubCategoryCode is null
or trim(SubCategoryCode) = ''
or SubCategoryCode = '0'
then 
	return 0;
end if;

-- Insert The New Brand 
insert into "shinde_shoes"."DimSubCategory" ("SubCategoryName","SubCategoryCode","CategoryKey")
values (
trim(SubCategoryDesc), 
COALESCE(NULLIF(Trim(SubCategoryCode),''),'0'),
CategoryKey
)
on conflict ("SubCategoryName") do nothing;

-- Fetch The SubCategoryKey 
select "SubCategoryKey"
into v_SubCategoryKey
from "shinde_shoes"."DimSubCategory"
where "SubCategoryName" = Trim(SubCategoryDesc);

return coalesce(v_SubCategoryKey,0);
end;
$function$
;
