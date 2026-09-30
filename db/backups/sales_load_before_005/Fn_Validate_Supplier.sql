CREATE OR REPLACE FUNCTION shinde_shoes."Fn_Validate_Supplier"(suppliername character varying, v_sku character varying)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
declare
	v_sku_exits int;
	v_Supplierkey int;
	print_notice boolean;
begin
	print_notice := false;
-- Check If Sku existing In Stagging Table
-- 	select count(*) into v_sku_exits
-- 	from "Stagging_Tables"."source_table"
-- 	where "SKU" = V_SKU;

-- -- if sku is existing , retrun 1
-- 	if v_sku_exits > 0 then
-- 		return 1;
-- 	end if;

-- 	Validate SizeName
	if SupplierName is null
	or trim(SupplierName) = ''
	or SupplierName = '0'
	then
		return 0;
	end if;
		
-- Insert into DimSize
	insert into "shinde_shoes"."DimSupplier"("SupplierName")
	values (trim(SupplierName))
	ON CONFLICT ("SupplierName") DO UPDATE SET "SupplierName" = EXCLUDED."SupplierName";

	if print_notice then
		Raise Notice 'Supplier Inserted successfully';
	end if;
	
-- Fetch The SizeKey
	select "SupplierKey" INTO v_Supplierkey
	from "shinde_shoes"."DimSupplier"
	where "SupplierName" = SupplierName;
	
return coalesce(v_Supplierkey,0);
end;
$function$
;
