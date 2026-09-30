CREATE OR REPLACE FUNCTION shinde_shoes."Fn_Validate_Brand"(brandname character varying, v_sku character varying)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
declare
v_brandkey integer;
v_sku_exits integer;
begin

	-- -- -- Check If Sku Exits In Stagging Table
	-- select count(*) into v_sku_exits 
	-- From "Stagging_Tables"."source_table"
	-- where "SKU" = v_sku;

	-- -- -- if sku is exits , retrun 1
	-- if v_sku_exits > 0 then
	-- 	return 1;
	-- end if;

	-- check Brand is Empty
	if brandname is null
	or trim(brandname) = ''
	or brandname = '0'
	then 
		return 0;
	end if;

	-- Insert The New BrandName
	Insert Into "shinde_shoes"."DimBrand" ("BrandName") values(
		trim(brandname)
	)
	ON CONFLICT ("BrandName") DO UPDATE SET "BrandName" = EXCLUDED."BrandName";

	-- Fetch The BrandKey
	select "BrandKey" into v_brandkey
	From "shinde_shoes"."DimBrand"
	where "BrandName" = trim(brandname);

	return coalesce(v_brandkey,0);
	end;
	
$function$
;
