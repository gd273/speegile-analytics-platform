CREATE OR REPLACE FUNCTION shinde_shoes."Fn_Validate_ProductCode"(subcategorykey integer, productcodename character varying, proddescription character varying, v_sku character varying)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
declare 
v_ProductCodeKey int;
v_sku_exists int;
print_notice boolean;
begin
print_notice := false;

	if print_notice then
		Raise Notice 'ProductCode Function Started';
	end if;
	
-- -- Check if SKU exists in staging table
--   SELECT COUNT(*) INTO v_sku_exists
--   FROM "Stagging_Tables"."sales_data"
--   WHERE "SKU" = V_SKU;
  
-- --   -- If SKU EXISTS, return 1
--   IF v_sku_exists > 0 THEN
--     RETURN 1;
--   END IF;
	if print_notice then
		Raise Notice 'ProductCode :- Check ProductCodeName';
	end if;

--  Check ProductCodeName Is Empty 
if ProductCodeName is null
or trim(ProductCodeName) = ''
or ProductCodeName = '0'
then 
	return 0;
end if;

	if print_notice then
		Raise Notice 'ProductCode :- Check ProdDescription';
	end if;

--  Check ProdDescription Is Empty 
if ProdDescription is null
or trim(ProdDescription) = ''
or ProdDescription = '0'
then 
	return 0;
end if;
	if print_notice then
		Raise Notice 'ProductCode :- Inserting ProductCode';
	end if;

-- Insert The New Brand 
insert into "shinde_shoes"."DimProductCode" ("ProductCodeName","ProdDescription","SubCategoryKey")
values (
trim(ProductCodeName), 
COALESCE(NULLIF(Trim(ProdDescription),''),'0'),
SubCategoryKey
)
-- ON CONFLICT ("SKU") DO UPDATE SET "ProductName" = EXCLUDED."ProductName";
ON CONFLICT ("ProductCodeName") DO NOTHING;

if print_notice then
	Raise Notice 'ProductCode :- Fetch The ProductCodeKey';
end if;

-- Fetch The ProductCodeKey 
select "ProductCodeKey"
into v_ProductCodeKey
from "shinde_shoes"."DimProductCode"
where "ProductCodeName" = Trim(ProductCodeName);

if print_notice then
	Raise Notice 'Processing row: %', v_ProductCodeKey;
	Raise Notice 'ProductCode Function End';
end if;
return coalesce(v_ProductCodeKey,0);
end;
$function$
;
