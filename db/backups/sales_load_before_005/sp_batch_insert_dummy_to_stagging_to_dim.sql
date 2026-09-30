CREATE OR REPLACE PROCEDURE shinde_shoes.sp_batch_insert_dummy_to_stagging_to_dim(IN p_batch_size integer DEFAULT 200000, IN p_max_batches integer DEFAULT NULL::integer, IN p_start_offset integer DEFAULT 0)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_offset                  INT := p_start_offset;
    v_rows_inserted           INT := 0;
    v_total_rows              INT;
    v_start_time              TIMESTAMP;
    v_end_time                TIMESTAMP;
    v_batch_count             INT := 0;
    print_notice              BOOLEAN;
    truncate_target_tables    BOOLEAN;

    -- Variables for duplicate checking logic
    rec                       RECORD;
    v_existing_billno         INTEGER;
    v_new_billno              INTEGER;
    v_offset_location         INTEGER;
    v_rec_date                DATE;
    v_date_key                INTEGER;
    v_location_key            INTEGER;
    v_batch_rows_processed    INT := 0;
    v_max_rowno_from_detail   INT := 0;

    -- ┌─────────────────────────────────────────────────┐
    -- │ FIX 3: Map to track BillNo assigned per         │
    -- │        Og_BillNo+Location within current batch. │
    -- │        Key = 'BillNo_LocationKey'               │
    -- │        Value = assigned v_new_billno            │
    -- └─────────────────────────────────────────────────┘
    v_bill_map                JSONB := '{}'::JSONB;
    v_bill_map_key            TEXT;

BEGIN
    print_notice           := FALSE;   -- Set FALSE in production to reduce noise
    truncate_target_tables := FALSE;  -- Set TRUE only for full reset

    -- Truncate target tables if requested
    IF truncate_target_tables THEN
        RAISE NOTICE 'Truncating target tables...';
        CALL "shinde_shoes"."Data_Intialization_Script"();
    END IF;

    -- Get max row_no from FactSalesDetail for offset
    v_max_rowno_from_detail := NULL;
    SELECT COALESCE(MAX("row_no"), 0)
    INTO v_max_rowno_from_detail
    FROM "shinde_shoes"."FactSalesDetail";

	if print_notice then
    	RAISE NOTICE 'Max row_no from FactSalesDetail: %', v_max_rowno_from_detail;
	end if;

    -- Truncate stg-2 before starting
    TRUNCATE "shinde_shoes"."stg-2";

	if print_notice then
    	RAISE NOTICE 'stg-2 truncated. New row_no will start from: %', v_max_rowno_from_detail + 1;
	end if;

    -- NOTE: DimDate and DimLocation are NOT touched here.
    -- DimDate    → already has all future dates pre-populated by you.
    -- DimLocation → already has all fixed branch locations pre-populated by you.
    -- If a date or location lookup fails below, a WARNING is raised
    -- and key=0 (UNKNOWN) is used so the row is never silently dropped.

    -- ┌─────────────────────────────────────────────────┐
    -- │ FIX 1 (Bug #3): COUNT from stg-1 not stg-2.   │
    -- │  Previously stg-2 was counted AFTER truncate   │
    -- │  so it always showed 0.                        │
    -- └─────────────────────────────────────────────────┘
    SELECT COUNT(*) INTO v_total_rows
    FROM "shinde_shoes"."stg-1";

	if print_notice then
	    RAISE NOTICE '========================================';
	    RAISE NOTICE 'BATCH PROCESSING WITH FACT TABLE DUPLICATE CHECKING';
	    RAISE NOTICE '========================================';
	    RAISE NOTICE 'Total rows available: %', v_total_rows;
	    RAISE NOTICE 'Batch size: %', p_batch_size;
	    RAISE NOTICE 'Starting offset: % (will start from row %)', p_start_offset, p_start_offset + 1;
	end if;
	
    IF p_max_batches IS NULL THEN
        RAISE NOTICE 'Max batches: ALL (will process all rows)';
    ELSE
        RAISE NOTICE 'Max batches: % (will process up to % rows)', p_max_batches, p_max_batches * p_batch_size;
    END IF;

	if print_notice then
    	RAISE NOTICE '========================================';
	end if;
	
    -- ============================================================
    -- MAIN BATCH LOOP
    -- ============================================================
    LOOP
        -- Check max batch limit
        IF p_max_batches IS NOT NULL AND v_batch_count >= p_max_batches THEN
            RAISE NOTICE 'Reached maximum batch limit (%). Stopping...', p_max_batches;
            EXIT;
        END IF;

        v_start_time           := clock_timestamp();
        v_batch_rows_processed := 0;

        -- ┌─────────────────────────────────────────────────┐
        -- │ FIX 3: Reset the bill map at the start of      │
        -- │        every batch. This map remembers which    │
        -- │        BillNo was assigned to each Og_BillNo    │
        -- │        so all rows of the same bill get the     │
        -- │        SAME BillNo in stg-2.                    │
        -- └─────────────────────────────────────────────────┘
        v_bill_map := '{}'::JSONB;

        -- Loop through each record in the current batch
        FOR rec IN
            SELECT
                "BillNo", "BillDate", "Brand", "CategoryDesc",
                "ProductDesc", "ColorCode", "Size", "SKU",
                "TotalQty", "MRP", "SaleRate", "NetAmount",
                "MobileNo", "SalesMan1Name", "Supplier", "Time",
                "LocationName", "CreatedUser", "CategoryCode",
                "SubCategoryCode", "SubCategoryDesc", "ProductCode",
                "ColorDesc", "SizeRange", "BillDiscount",
                "TotalDiscountAmount", "TaxableAmount", "HSNCode",
                "HSNDesc", "TaxDesc", "TaxRate", "TaxAmount",
                "BillAmount", "Customer", "GSTIN", "BillComment",
                "Counter", "ModifiedUser", "DisplayStockDays",
                "LastPurDate", "row_no"
            FROM "shinde_shoes"."stg-1"
            WHERE "row_no" BETWEEN (v_offset + 1) AND (v_offset + p_batch_size)
            ORDER BY "row_no"
        LOOP
            v_existing_billno := NULL;
            v_date_key        := NULL;
            v_location_key    := NULL;

            IF print_notice THEN
                RAISE NOTICE 'Processing Og_BillNo=% row_no=%', rec."BillNo", rec."row_no";
            END IF;

            -- ── Step 1: Parse date ───────────────────────────────────
            v_rec_date := "shinde_shoes"."ParseDate_dd_mm_yyyy"(rec."BillDate");

            IF v_rec_date IS NULL THEN
                RAISE WARNING 'Skipping - Invalid date: BillNo=%, Date=%, row_no=%',
                    rec."BillNo", rec."BillDate", rec."row_no";
                CONTINUE;
            END IF;

            -- ── Step 2: Get DateKey ──────────────────────────────────
            -- ┌─────────────────────────────────────────────────────┐
            -- │ FIX 2: DimDate is pre-populated by you with future  │
            -- │        dates so this lookup should always succeed.   │
            -- │        If somehow it fails, use key=0 (UNKNOWN)     │
            -- │        instead of CONTINUE so the row is NOT lost.  │
            -- └─────────────────────────────────────────────────────┘
            SELECT "DateKey" INTO v_date_key
            FROM "shinde_shoes"."DimDate"
            WHERE "Fulldate" = v_rec_date
            LIMIT 1;

            IF NOT FOUND THEN
                v_date_key := 0;
                RAISE WARNING 'Date not in DimDate, using key=0: BillNo=%, Date=%, row_no=%',
                    rec."BillNo", v_rec_date, rec."row_no";
            END IF;

            -- ── Step 3: Get LocationKey ──────────────────────────────
            -- ┌─────────────────────────────────────────────────────┐
            -- │ FIX 2: DimLocation has fixed branch locations       │
            -- │        pre-populated by you so this should always   │
            -- │        succeed. If somehow it fails, use key=0      │
            -- │        (UNKNOWN) instead of CONTINUE so the row     │
            -- │        is NOT lost.                                 │
            -- └─────────────────────────────────────────────────────┘
            SELECT "LocationKey" INTO v_location_key
            FROM "shinde_shoes"."DimLocation"
            WHERE "locationName" = rec."LocationName"
            LIMIT 1;

            IF NOT FOUND THEN
                v_location_key := 0;
                RAISE WARNING 'Location not in DimLocation, using key=0: BillNo=%, Location=%, row_no=%',
                    rec."BillNo", rec."LocationName", rec."row_no";
            END IF;

            -- ── Step 4: Check FactSalesMaster for existing bill ──────
            SELECT "BillNo" INTO v_existing_billno
            FROM "shinde_shoes"."FactSalesMaster"
            WHERE "Og_BillNo"      = rec."BillNo"
              AND "DateFrKey"      = v_date_key
              AND "LocationFrKey"  = v_location_key
            LIMIT 1;

            IF NOT FOUND THEN
                v_existing_billno := NULL;
            END IF;

            IF print_notice THEN
                RAISE NOTICE 'Og_BillNo=% | v_existing_billno=%', rec."BillNo", v_existing_billno;
            END IF;

            -- ── Step 5: Decide BillNo ────────────────────────────────
            IF v_existing_billno IS NOT NULL THEN

                -- Bill already exists in FactSalesMaster from a previous batch
                -- Reuse the same BillNo
                v_new_billno := v_existing_billno;
				
			IF print_notice THEN	
                RAISE NOTICE 'Reusing BillNo % from FactSalesMaster for Og_BillNo=%, Location=%, Date=%',
                    v_new_billno, rec."BillNo", rec."LocationName", v_rec_date;
			end if;
			
                -- ┌───────────────────────────────────────────────────┐
                -- │ FIX 4 (Bug #4): CONTINUE removed.                │
                -- │ Previously this block had CONTINUE which silently │
                -- │ dropped all rows of a bill that was already in    │
                -- │ FactSalesMaster from a previous batch.            │
                -- │ Now the row falls through to the INSERT into      │
                -- │ stg-2 below. Fn_Insert_FactSalesDetail will skip  │
                -- │ duplicate lines via the business key check.       │
                -- └───────────────────────────────────────────────────┘

            ELSE

                -- ┌───────────────────────────────────────────────────┐
                -- │ FIX 3 (Bug #1): BillNo assignment now uses a map. │
                -- │                                                    │
                -- │ Map key = 'Og_BillNo_LocationKey'                 │
                -- │ If this bill was already seen earlier in THIS      │
                -- │ batch, reuse the BillNo from the map.             │
                -- │ This ensures all rows of the same bill get the    │
                -- │ SAME BillNo in stg-2 — not incremented per row.  │
                -- └───────────────────────────────────────────────────┘
                v_bill_map_key := rec."BillNo"::TEXT || '_' || v_location_key::TEXT;

                IF v_bill_map ? v_bill_map_key THEN

                    -- Already assigned a BillNo for this bill in this batch
                    -- Reuse it so all rows of same bill share one BillNo
                    v_new_billno := (v_bill_map ->> v_bill_map_key)::INTEGER;
					IF print_notice THEN	
	                    RAISE NOTICE 'Reusing batch-assigned BillNo % for Og_BillNo=%',
	                        v_new_billno, rec."BillNo";
					end if;
                ELSE

                    -- First row of this bill in this batch
                    -- Calculate BillNo with location offset
                    v_offset_location := CASE
                        WHEN rec."LocationName" = 'LT ROAD BRANCH'         THEN 990000
                        WHEN rec."LocationName" = 'GORAI BRANCH'           THEN 790000
                        WHEN rec."LocationName" = 'SHINDE SHOES (WOMENS)'  THEN 590000
                        WHEN rec."LocationName" = 'MAHARASTRA NAGAR'       THEN 390000
                        ELSE 5000
                    END;

                    v_new_billno := rec."BillNo" + v_offset_location;

                    -- ── Step 6: Collision check ──────────────────────
                    -- Runs ONCE per bill (first row only), not per row
                    WHILE EXISTS (
                        SELECT 1 FROM "shinde_shoes"."FactSalesMaster"
                        WHERE "BillNo" = v_new_billno
                    )
                    OR EXISTS (
                        SELECT 1 FROM "shinde_shoes"."stg-2"
                        WHERE "BillNo" = v_new_billno
                    )
                    LOOP
                        v_new_billno := v_new_billno + 1;
						IF print_notice THEN
                        	RAISE NOTICE 'BillNo collision, incrementing to %', v_new_billno;
						end if;
                    END LOOP;

                    -- Save assigned BillNo to map for remaining rows of this bill
                    v_bill_map := v_bill_map || jsonb_build_object(v_bill_map_key, v_new_billno);
					IF print_notice THEN
	                    RAISE NOTICE 'New BillNo % assigned for Og_BillNo=%, Location=%, Date=%',
	                        v_new_billno, rec."BillNo", rec."LocationName", v_rec_date;
					end if;

                END IF;

            END IF;

            IF print_notice THEN
                RAISE NOTICE 'step - 2 | About to INSERT into stg-2 | BillNo=%', v_new_billno;
            END IF;

            -- ── Step 7: Insert into stg-2 ───────────────────────────
            -- This INSERT now runs for ALL rows:
            --   new bills      → with freshly assigned BillNo
            --   existing bills → with reused BillNo from FactSalesMaster
            --   same bill rows → with same BillNo from v_bill_map
            INSERT INTO "shinde_shoes"."stg-2" (
                "Og_BillNO",
                "BillNo",
                "BillDate",
                "Brand",
                "CategoryDesc",
                "ProductDesc",
                "ColorCode",
                "Size",
                "SKU",
                "TotalQty",
                "MRP",
                "SaleRate",
                "NetAmount",
                "MobileNo",
                "SalesMan1Name",
                "Supplier",
                "Time",
                "LocationName",
                "CreatedUser",
                "CategoryCode",
                "SubCategoryCode",
                "SubCategoryDesc",
                "ProductCode",
                "ColorDesc",
                "SizeRange",
                "BillDiscount",
                "TotalDiscountAmount",
                "TaxableAmount",
                "HSNCode",
                "HSNDesc",
                "TaxDesc",
                "TaxRate",
                "TaxAmount",
                "BillAmount",
                "Customer",
                "GSTIN",
                "BillComment",
                "Counter",
                "ModifiedUser",
                "DisplayStockDays",
                "LastPurDate",
                "row_no"
            )
            VALUES (
                rec."BillNo",
                v_new_billno,
                rec."BillDate",
                rec."Brand",
                rec."CategoryDesc",
                rec."ProductDesc",
                rec."ColorCode",
                rec."Size",
                rec."SKU",
                rec."TotalQty",
                rec."MRP",
                rec."SaleRate",
                rec."NetAmount",
                rec."MobileNo",
                rec."SalesMan1Name",
                rec."Supplier",
                rec."Time",
                rec."LocationName",
                rec."CreatedUser",
                rec."CategoryCode",
                rec."SubCategoryCode",
                rec."SubCategoryDesc",
                rec."ProductCode",
                rec."ColorDesc",
                rec."SizeRange",
                rec."BillDiscount",
                rec."TotalDiscountAmount",
                rec."TaxableAmount",
                rec."HSNCode",
                rec."HSNDesc",
                rec."TaxDesc",
                rec."TaxRate",
                rec."TaxAmount",
                rec."BillAmount",
                rec."Customer",
                rec."GSTIN",
                rec."BillComment",
                rec."Counter",
                rec."ModifiedUser",
                rec."DisplayStockDays",
                rec."LastPurDate",
                rec."row_no" + v_max_rowno_from_detail
            );

            v_batch_rows_processed := v_batch_rows_processed + 1;

        END LOOP;

        IF print_notice THEN
            RAISE NOTICE 'step - 3 | Batch loop ended';
        END IF;

        v_end_time := clock_timestamp();

        -- Exit if no rows were found in this batch
        EXIT WHEN v_batch_rows_processed = 0;

        v_batch_count   := v_batch_count + 1;
        v_rows_inserted := v_rows_inserted + v_batch_rows_processed;
	
        RAISE NOTICE 'Batch % - Inserted % rows to stg-2 (row_no % to %) - Time: %',
            v_batch_count,
            v_batch_rows_processed,
            v_offset + 1,
            v_offset + p_batch_size,
            v_end_time - v_start_time;

        -- Call sp_process_sales_rowwise after each batch
		IF print_notice THEN
        	RAISE NOTICE 'Calling sp_process_sales_rowwise...';
		end if;
        v_start_time := clock_timestamp();

        CALL "shinde_shoes"."sp_process_sales_rowwise"();

        v_end_time := clock_timestamp();
        RAISE NOTICE 'sp_process_sales_rowwise completed - Time: %', v_end_time - v_start_time;
		IF print_notice THEN
        	RAISE NOTICE '========================================';
		end if;

        -- Advance offset for next batch
        v_offset := v_offset + p_batch_size;

    END LOOP;

    RAISE NOTICE '========================================';
    RAISE NOTICE 'PROCESSING COMPLETED!';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Total batches processed: %', v_batch_count;
    RAISE NOTICE 'Total rows inserted to stg-2: %', v_rows_inserted;
    RAISE NOTICE '========================================';

EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error occurred at batch %: %', v_batch_count, SQLERRM;
        RAISE;
END;
$procedure$
;
