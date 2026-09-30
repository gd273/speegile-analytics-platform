CREATE OR REPLACE FUNCTION shinde_shoes."Fn_Validate_Size"(sizename character varying, sizerange character varying, v_sku character varying)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
declare
	v_sku_exits int;
	v_Sizekey int;
begin

-- Check If Sku existing In Stagging Table
-- 	select count(*) into v_sku_exits
-- 	from "Stagging_Tables"."source_table"
-- 	where "SKU" = V_SKU;

-- -- if sku is existing , retrun 1
-- 	if v_sku_exits > 0 then
-- 		return 1;
-- 	end if;

-- 	Validate SizeName
	if SizeName is null
	or trim(SizeName) = ''
	or SizeName = '0'
	then
		return 0;
-- Validate SizeRange
	elsif SizeRange is Null
	or trim(SizeRange) = ''
	or SizeRange = '0'
	then 
		return 0;
	end if;
		
-- Insert into DimSize
	insert into "shinde_shoes"."DimSize"("SizeName","SizeRange")
	values (trim(SizeName),trim(SizeRange))
	ON CONFLICT ("SizeName") DO UPDATE SET "SizeName" = EXCLUDED."SizeName";
	--Raise Notice 'Size Inserted successfully';
	
-- Fetch The SizeKey
	select "SizeKey" INTO v_Sizekey
	from "shinde_shoes"."DimSize"
	where "SizeName" = SizeName;
	
return coalesce(v_Sizekey,0);
end;
$function$
;
