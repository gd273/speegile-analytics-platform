CREATE OR REPLACE FUNCTION shinde_shoes."Fn_Insert_FactSalesDetail"(v_billnokey_d integer, v_billlineno_d integer, v_skukey integer, v_totalqty integer, v_mrp numeric, v_salerate numeric, v_billdiscount numeric, v_totaldiscountamount numeric, v_taxableamount numeric, v_taxrate numeric, v_taxamount numeric, v_netamount numeric, v_displaystockdays integer, v_lastpurdate_dd_mm_yy date, v_row_no integer, v_billno integer, v_og_billno integer)
 RETURNS TABLE(rows_inserted integer, message character varying, bill_net_amount numeric)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_inserted_count INT := 0;
    v_billnokey INT;
    v_message_text VARCHAR := '';
    v_total_net_amount NUMERIC(12,2) := 0;
	print_notice boolean;
BEGIN

	print_notice := FALSE;

    -- Get the BillNoKey from FactSalesMaster
    -- SELECT "BillNoKey" INTO v_billnokey
    -- FROM "Sales_Data"."FactSalesMaster"
    -- WHERE "BillNo" = p_BillNo
    -- LIMIT 1;
	if print_notice then
    	Raise Notice 'Current BillNoKey & Actual BillNo:- %,%',v_billnokey_d,v_billno;
	end if;
    -- Check if BillNoKey exists
    IF v_billnokey_d IS NULL THEN
        v_message_text := 'ERROR: BillNo ' || v_billnokey_d || ' not found in FactSalesMaster';
        RETURN QUERY SELECT 0::INT AS rows_inserted, v_message_text::VARCHAR AS message, 0::NUMERIC AS bill_net_amount;
        RETURN;
    END IF;

	IF EXISTS (
	    SELECT 1
	    FROM "shinde_shoes"."FactSalesDetail"
	    WHERE "row_no" = v_row_no
	) THEN
	    v_message_text := 'INFO: BillNo ' || v_billnokey_d || 'Row_No.' || v_row_no || ' already exists in FactSalesDetail. Skipping insert.';
	    
	    RETURN QUERY 
	    SELECT 0::INT AS rows_inserted, 
	           v_message_text::VARCHAR AS message, 
	           0::NUMERIC AS bill_net_amount;
	    
	    RETURN;
	END IF;

	-- 🔴 IMPORTANT: Remove existing detail rows ONLY for this bill
	-- DELETE FROM "Sales_Data"."FactSalesDetail"
	-- WHERE "BillNoKey" = v_billnokey;
    
    -- Insert into FactSalesDetail with sequential BillLineNo per BillNo
			    INSERT INTO "shinde_shoes"."FactSalesDetail" (
			    "BillNoKey",
			    "BillLineNo",
			    "SKUKey",
			    "SaleQty",
			    "SKUMRP",
			    "SKUSELLPRICE",
			    "BillDiscount",
			    "TotalDiscountAmount",
			    "TaxableAmount",
			    "TaxRate",
			    "TaxAmount",
			    "NetAmount",
			    "DisplayStockDays",
			    "LastPurDate",
			    "BSaleStatus",
			    "row_no",
				"Og_BillNo"
			)
			VALUES (
			    v_BillNoKey_D,
			    v_BillLineNo_D,                         -- sequential line number
			    v_SkuKey,
			    COALESCE(v_TotalQty, 0),
			    COALESCE(v_MRP, 0),
			    COALESCE(v_SaleRate, 0),
			    COALESCE(v_BillDiscount, 0),
			    COALESCE(v_TotalDiscountAmount, 0),
			    COALESCE(v_TaxableAmount, 0),
			    COALESCE(v_TaxRate, 0),
			    COALESCE(v_TaxAmount, 0),
			    COALESCE(
			        v_NetAmount,
			        COALESCE(v_SaleRate, 0) * COALESCE(v_TotalQty, 0)
			    ),
			    COALESCE(v_DisplayStockDays, 0),
			    v_LastPurDate_dd_mm_yy,
			    TRUE,
			    v_row_no,
				COALESCE(v_Og_BillNo, 0)
			);

	
	-- FROM "Stagging_Tables"."source_table" s
    -- JOIN "Sales_Data"."DimProduct" dp
    --     ON dp."SKU" = s."SKU"  -- ✅ BIGINT casting for both columns
    -- WHERE s."BillNo" = p_BillNo;
    
    GET DIAGNOSTICS v_inserted_count = ROW_COUNT;
    
    -- Calculate the total NetAmount from FactSalesDetail for this bill
    SELECT COALESCE(SUM("NetAmount"), 0)
    INTO v_total_net_amount
    FROM "shinde_shoes"."FactSalesDetail"
    WHERE "BillNoKey" = v_BillNoKey_D;
    
    v_message_text := 'FactSalesDetail inserted successfully for BillNo: ' || v_BillNo || 
                     ' - Rows inserted: ' || v_BillLineNo_D || ' - Total Amount: ' || v_total_net_amount;
    if print_notice then
	    RAISE NOTICE 'FactSalesDetail - BillNo=% | RowsInserted=% | TotalAmount=%',
	        v_BillNo, v_BillLineNo_D, v_total_net_amount;
	end if;
    
    RETURN QUERY SELECT 
        v_BillLineNo_D::INT AS rows_inserted,
        v_message_text::VARCHAR AS message,
        v_total_net_amount::NUMERIC AS bill_net_amount;
    
EXCEPTION WHEN OTHERS THEN
    v_message_text := 'ERROR in Fn_Insert_FactSalesDetail: ' || SQLERRM;
    RAISE NOTICE 'ERROR: %', v_message_text;
    RETURN QUERY SELECT 0::INT AS rows_inserted, v_message_text::VARCHAR AS message, 0::NUMERIC AS bill_net_amount;
END;
$function$
;
