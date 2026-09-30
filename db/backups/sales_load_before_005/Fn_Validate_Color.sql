CREATE OR REPLACE FUNCTION shinde_shoes."Fn_Validate_Color"(colorname character varying, colorcode character varying, v_sku character varying)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
declare
	v_sku_exits int;
	v_colorkey int;

begin

-- -- -- Check If Sku Exits In Stagging Table
-- 	select count(*) into v_sku_exits
-- 	from "Stagging_Tables"."source_table"
-- 	where "SKU" = v_SKU;

-- -- -- if sku is exits , retrun 1
-- 	if v_sku_exits > 0 then
-- 		return 1;
-- 	end if;

-- Validate ClourName
	if ColorName is null
	or trim(ColorName) = ''
	or ColorName = '0'
	then
		return 0;
-- Validate ClourCode
	elsif ColorCode is null
	or trim(ColorCode) = ''
	or ColorCode = '0'
	then
		return 0;
	end if;

-- Insert into DimColour
	insert into "shinde_shoes"."DimColour"("ColourName","ColourCode")
	values (trim(ColorName),trim(ColorCode))
	ON CONFLICT ("ColourName") DO UPDATE SET "ColourName" = EXCLUDED."ColourName";
-- Fetch The ColourKey
	select "ColourKey" INTO v_colorkey
	from "shinde_shoes"."DimColour"
	where "ColourName" = ColorName;
	
return coalesce(v_colorkey,0);

end;
$function$
;
