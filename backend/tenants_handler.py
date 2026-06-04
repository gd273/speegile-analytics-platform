from datetime import timedelta
import pandas as pd
from sqlalchemy import text

from db_utils import log_load_error


# ---------------------------------------------------------
# TENANT: shinde_shoes
# ---------------------------------------------------------

def handle_shinde_shoes(conn, df, tenant_schema, target_table_name, load_id, log_load_error, engine):
    """
    excel_max_date is now computed internally from BillDate column.
    No longer passed as a parameter from upload_excel.
    """

    # ─────────────────────────────────────────────────────────────
    # STEP 0: BillDate processing (moved from upload_excel)
    # ─────────────────────────────────────────────────────────────
    if 'BillDate' not in df.columns:
        raise ValueError("Column 'BillDate' not found in uploaded file.")

    print(f"DEBUG [{tenant_schema}]: Processing BillDate column...", flush=True)

    # Remove rows with empty/null BillDate
    df = df[
        df['BillDate'].notna() &
        (df['BillDate'].astype(str).str.strip() != '')
    ].copy()

    # Convert to standard DD-MM-YYYY format
    df['BillDate'] = pd.to_datetime(
        df['BillDate'], dayfirst=True, errors='coerce'
    ).dt.strftime('%d-%m-%Y')

    # Validate — block upload if any dates are unrecognizable
    if df['BillDate'].isna().any():
        bad_rows  = df[df['BillDate'].isna()].index.tolist()
        error_msg = f"Invalid BillDate in rows: {bad_rows}. Expected format: DD-MM-YYYY."
        log_load_error(
            conn=conn, load_id=load_id,
            error_message=error_msg, row_number=None, column_name='BillDate'
        )
        raise ValueError(error_msg)

    # Compute excel_max_date from the processed BillDate column
    excel_max_date = pd.to_datetime(
        df['BillDate'], format='%d-%m-%Y'
    ).max().date()

    print(f"DEBUG [{tenant_schema}]: Excel max date: {excel_max_date}", flush=True)

    # ── Process LastPurDate if present (also moved from upload_excel)
    if 'LastPurDate' in df.columns:
        df['LastPurDate'] = pd.to_datetime(
            df['LastPurDate'], dayfirst=True, errors='coerce'
        ).dt.strftime('%d-%m-%Y')

    # ─────────────────────────────────────────────────────────────
    # STEP 1: Location + Date Validation
    # ─────────────────────────────────────────────────────────────
    if 'LocationName' not in df.columns:
        raise ValueError("Column 'LocationName' not found in uploaded file.")

    file_locations = (
        df['LocationName']
        .dropna()
        .str.strip()
        .unique()
        .tolist()
    )
    file_locations = [loc for loc in file_locations if loc != '']

    if not file_locations:
        raise ValueError("No valid 'LocationName' found in uploaded file.")

    print(f"DEBUG [{tenant_schema}]: File locations: {file_locations}", flush=True)
    print(f"DEBUG [{tenant_schema}]: File max BillDate: {excel_max_date}", flush=True)

    validation_errors = []

    with engine.connect() as val_conn:
        for location in file_locations:
            print(f"DEBUG [{tenant_schema}]: Querying base tables for location '{location}'...", flush=True)

            db_max_date = val_conn.execute(text(f"""
                SELECT MAX(dd."Fulldate")
                FROM "{tenant_schema}"."FactSalesMaster" fsm
                JOIN "{tenant_schema}"."DimDate" dd
                    ON fsm."DateFrKey" = dd."DateKey"
                JOIN "{tenant_schema}"."DimLocation" dl
                    ON fsm."LocationFrKey" = dl."LocationKey"
                WHERE TRIM(dl."locationName") = :loc
            """), {"loc": location}).scalar()

            print(f"DEBUG [{tenant_schema}]: DB max date for '{location}': {db_max_date}", flush=True)

            if db_max_date is None:
                print(f"DEBUG [{tenant_schema}]: '{location}' is a new location, first upload allowed.", flush=True)
                continue

            if hasattr(db_max_date, 'date'):
                db_max_date = db_max_date.date()

            if excel_max_date <= db_max_date:
                validation_errors.append(
                    f"Location '{location}': file max date "
                    f"({excel_max_date.strftime('%d-%m-%Y')}) must be after "
                    f"DB max date ({db_max_date.strftime('%d-%m-%Y')})."
                )

    if validation_errors:
        error_msg = "Upload blocked — " + " | ".join(validation_errors)
        print(f"DEBUG [{tenant_schema}]: Validation FAILED → {error_msg}", flush=True)
        log_load_error(
            conn=conn, load_id=load_id,
            error_message=error_msg, row_number=None, column_name='BillDate'
        )
        raise ValueError(error_msg)

    print(f"DEBUG [{tenant_schema}]: Validation PASSED for all locations.", flush=True)

    # ─────────────────────────────────────────────────────────────
    # STEP 2: Truncate staging table
    # ─────────────────────────────────────────────────────────────
    print(f"DEBUG [{tenant_schema}]: Truncating staging table...", flush=True)
    conn.execute(text(
        f'TRUNCATE TABLE "{tenant_schema}"."{target_table_name}" RESTART IDENTITY'
    ))
    print(f"DEBUG [{tenant_schema}]: Truncate done.", flush=True)

    # ─────────────────────────────────────────────────────────────
    # STEP 3: Bulk insert
    # ─────────────────────────────────────────────────────────────
    print(f"DEBUG [{tenant_schema}]: Starting bulk insert ({len(df)} rows)...", flush=True)
    df.to_sql(
        target_table_name,
        con=conn,
        schema=tenant_schema,
        if_exists='append',
        index=False
    )
    print(f"DEBUG [{tenant_schema}]: Bulk insert done.", flush=True)

    # ─────────────────────────────────────────────────────────────
    # STEP 4: staging -> dimension tables
    # ─────────────────────────────────────────────────────────────
    print(f"DEBUG [{tenant_schema}]: Calling sp_batch_insert_dummy_to_stagging_to_dim...", flush=True)
    conn.execute(text(
        f'CALL "{tenant_schema}".sp_batch_insert_dummy_to_stagging_to_dim(200000, 1, 0)'
    ))
    print(f"DEBUG [{tenant_schema}]: sp_batch_insert done.", flush=True)

    # ─────────────────────────────────────────────────────────────
    # STEP 5: Refresh date dimension
    # ─────────────────────────────────────────────────────────────
    print(f"DEBUG [{tenant_schema}]: Calling refresh_dimdate_offsets({excel_max_date})...", flush=True)
    conn.execute(
        text(f'CALL "{tenant_schema}".refresh_dimdate_offsets(:max_date)'),
        {"max_date": excel_max_date}
    )
    print(f"DEBUG [{tenant_schema}]: refresh_dimdate done.", flush=True)

    # ─────────────────────────────────────────────────────────────
    # STEP 6: Rebuild materialized views
    # ─────────────────────────────────────────────────────────────
    print(f"DEBUG [{tenant_schema}]: Calling refresh_all_mvs()...", flush=True)
    conn.execute(text(
        f'CALL "{tenant_schema}".refresh_all_mvs()'
    ))
    print(f"DEBUG [{tenant_schema}]: refresh_all_mvs done.", flush=True)

    print(f"DEBUG [{tenant_schema}]: All steps completed successfully.", flush=True)



# ---------------------------------------------------------
# TENANT: shinde_shoes — STOCK file
# ---------------------------------------------------------


def handle_shinde_shoes_stock(conn, df, tenant_schema, target_table_name,
                               load_id, log_load_error, filename=None):
    """
    Handler for Shinde Shoes STOCK files.
    - Date extracted from filename (must be DD-MM-YYYY format)
    - Each column converted to its correct data type explicitly
    """
    import re                        # ← move imports here
    from datetime import datetime    # ← move imports here
    # ─────────────────────────────────────────────────────────────
    #  STEP 1: Extract and validate date from filename
    # ─────────────────────────────────────────────────────────────
    def extract_date_from_filename(fname):
        """
        Looks for DD-MM-YYYY or DD_MM_YYYY inside the filename.
        Valid examples:
            shindeshoes_stock_19-05-2026.xlsx
            shindeshoes_stock_19_05_2026.xlsx
        Returns 'DD-MM-YYYY' string or raises ValueError.
        """
        

        name = (fname or "").rsplit('.', 1)[0]

        m = re.search(r'(\d{2})[_\-](\d{2})[_\-](\d{4})', name)
        if not m:
            raise ValueError(
                f"Date not found in filename '{fname}'. "
                f"Please rename the file to include the date in DD-MM-YYYY format. "
                f"Example: shindeshoes_stock_19-05-2026.xlsx"
            )

        day, month, year = m.group(1), m.group(2), m.group(3)
        date_str = f"{day}-{month}-{year}"

        try:
            datetime.strptime(date_str, "%d-%m-%Y")
        except ValueError:
            raise ValueError(
                f"'{date_str}' extracted from '{fname}' is not a valid date. "
                f"Please use a valid date in DD-MM-YYYY format. "
                f"Example: shindeshoes_stock_19-05-2026.xlsx"
            )

        return date_str  # 'DD-MM-YYYY' — no conversion

    StockAsOn = extract_date_from_filename(filename)
    print(f"DEBUG [{tenant_schema}]: StockAsOn = {StockAsOn}", flush=True)

    # ─────────────────────────────────────────────────────────────
    #  STEP 2: Validate required column
    # ─────────────────────────────────────────────────────────────
    if 'BranchName' not in df.columns:
        raise ValueError("Column 'BranchName' not found in uploaded stock file.")

    print(f"DEBUG [{tenant_schema}]: Stock file — {len(df)} rows, "
          f"BranchName values: {df['BranchName'].dropna().unique().tolist()}",
          flush=True)

    # ─────────────────────────────────────────────────────────────
    #  STEP 3: Explicit column → type mapping
    # ─────────────────────────────────────────────────────────────
    COLUMN_TYPE_MAP = {
        "SKU":             "text",
        "Source":          "text",
        "AlternateCode":   "text",
        "Expiry":          "date",
        "SalesManPoints":  "int",
        "CostChar":        "text",
        "ProductGroup":    "text",
        "CollectionName":  "text",
        "FitName":         "text",
        "WashName":        "text",
        "MRP":             "numeric",
        "SellPrice":       "numeric",
        "PurchaseNo":      "int",
        "BillNo":          "text",
        "StockAsOn":       "date",
        "BillDate":        "date",
        "PeriodDays":      "int",
        "StockDays":       "int",
        "ExpiryDays":      "int",
        "Qty":             "int",
        "Product":         "text",
        "ProductDesc":     "text",
        "Composite":       "bool",
        "ColorCode":       "text",
        "ColorDesc":       "text",
        "SizeCode":        "text",
        "SizeDesc":        "text",
        "Size":            "text",
        "OptionalCategory":"text",
        "Category":        "int",
        "CategoryDesc":    "text",
        "Subcategory":     "int",
        "SubcategoryDesc": "text",
        "Supplier":        "text",
        "Brand":           "text",
        "Unit":            "text",
        "Cost":            "numeric",
        "CostAmount":      "numeric",
        "BaseCost":        "numeric",
        "BaseCostAmount":  "numeric",
        "StockType":       "text",
        "HSN":             "text",
        "BranchName":      "text",
    }

    # ─────────────────────────────────────────────────────────────
    #  STEP 4: Apply type conversions
    # ─────────────────────────────────────────────────────────────
    result = df.copy()

    for col, dtype in COLUMN_TYPE_MAP.items():
        if col not in result.columns:
            continue  # skip columns not present in this file

        # Normalise empty/null strings to None first
        series = result[col].replace(
            {'': None, 'nan': None, 'NaT': None, 'None': None, '<NA>': None}
        )

        if dtype == "text":
            result[col] = series.where(series.notna(), None)

        elif dtype == "int":
            result[col] = pd.to_numeric(series, errors='coerce').astype('Int64')

        elif dtype == "numeric":
            result[col] = pd.to_numeric(series, errors='coerce').astype(float)

        elif dtype == "date":
            result[col] = pd.to_datetime(
                series, dayfirst=True, errors='coerce'
            ).dt.date

        elif dtype == "bool":
            result[col] = series.map({
                'True': True, 'False': False,
                'true': True, 'false': False,
                '1':    True, '0':    False,
            })

    df = result
    print(f"DEBUG [{tenant_schema}]: Type conversion done. "
          f"Columns: { {c: str(df[c].dtype) for c in df.columns} }",
          flush=True)

    # ─────────────────────────────────────────────────────────────
    #  STEP 5: Add system columns
    # ─────────────────────────────────────────────────────────────
    df['load_id']     = load_id
    df['row_no']      = range(1, len(df) + 1)
    # df['StockAsOn'] = StockAsOn   # 'DD-MM-YYYY' string from filename
    df['StockAsOn'] = datetime.strptime(StockAsOn, "%d-%m-%Y").date() 

    def calc_new_bill_date(stock_as_on, stock_days):
        if stock_as_on is None or pd.isna(stock_days):
            return None
        return stock_as_on - timedelta(days=int(stock_days))
    df['NewBillDate'] = df['StockDays'].apply(
    lambda days: calc_new_bill_date(df['StockAsOn'].iloc[0], days)
    )

    print(f"DEBUG [{tenant_schema}]: NewBillDate sample → {df['NewBillDate'].head(3).tolist()}", flush=True)
    
    # ─────────────────────────────────────────────────────────────
    #  STEP 6: Truncate staging table
    # ─────────────────────────────────────────────────────────────
    print(f"DEBUG [{tenant_schema}]: Truncating '{target_table_name}'...", flush=True)
    conn.execute(text(
        f'TRUNCATE TABLE "{tenant_schema}"."{target_table_name}" RESTART IDENTITY'
    ))
    print(f"DEBUG [{tenant_schema}]: Truncate done.", flush=True)

    # ─────────────────────────────────────────────────────────────
    #  STEP 7: Bulk insert
    # ─────────────────────────────────────────────────────────────
    print(f"DEBUG [{tenant_schema}]: Inserting {len(df)} rows...", flush=True)
    df.to_sql(
        target_table_name,
        con=conn,
        schema=tenant_schema,
        if_exists='append',
        index=False
    )
    print(f"DEBUG [{tenant_schema}]: Stock insert done. StockAsOn={StockAsOn}", flush=True)


# ---------------------------------------------------------
# TENANT: apparel_store
# ---------------------------------------------------------
def handle_apparel_store(conn, df_original, tenant_schema, load_id, log_load_error):

    df_original = df_original.dropna(how='all')
    df_original = df_original.where(df_original.notna(), None)

    insert_rows = []
    for _, row in df_original.iterrows():
        if not row.get("Sale ID"):
            continue
        insert_rows.append({
            "sale_id":       row.get("Sale ID"),
            "location_city": row.get("Location (City)"),
            "store_name":    row.get("Store Name"),
            "product":       row.get("Product"),
            "size":          row.get("Size"),
            "color":         row.get("Color"),
            "price_inr":     row.get("Price (INR)"),
            "quantity_sold": row.get("Quantity Sold"),
            "date":          row.get("Date"),
            "sales_rep":     row.get("Sales Rep"),
            "load_id":       load_id,
        })

    if insert_rows:
        conn.execute(
            text("""
                INSERT INTO apparel_sales.t_apparel_sales (
                    sale_id,
                    "location_(city)",
                    store_name,
                    product,
                    size,
                    color,
                    "price_(inr)",
                    quantity_sold,
                    date,
                    sales_rep,
                    load_id
                ) VALUES (
                    :sale_id, :location_city, :store_name, :product,
                    :size, :color, :price_inr, :quantity_sold,
                    :date, :sales_rep, :load_id
                )
            """),
            insert_rows
        )
        print(f"DEBUG [{tenant_schema}]: Inserted {len(insert_rows)} rows", flush=True)
    else:
        print(f"DEBUG [{tenant_schema}]: No rows to insert.", flush=True)


# ---------------------------------------------------------
# TENANT: sales_data (your new client)
# ---------------------------------------------------------

def handle_client_orders(conn, df, tenant_schema, target_table_name, load_id, log_load_error):
    import re
    from datetime import datetime

    df.columns = [str(c).strip().lower() for c in df.columns]
    df = df.where(df.notna(), None)

    if "date" not in df.columns:
        raise Exception("❌ date column missing in Excel")

    def parse_date_dd_mm_yyyy(val):
        """
        Python equivalent of shinde_shoes.parse_date_dd_mm_yyyy() SQL function.
        
        Logic:
          1. If None or blank  → return None
          2. If already a datetime/Timestamp (Excel date cell) → reformat to DD-MM-YYYY string first
          3. Normalize separators (/ → -)
          4. Parse strictly as DD-MM-YYYY
          5. On any error → return None with a warning (mirrors SQL EXCEPTION WHEN others)
        """
        if val is None:
            return None

        try:
            # Step 1: If Excel gave us a datetime object, convert to DD-MM-YYYY string
            # This mirrors how the SQL function receives text after your staging insert
            if isinstance(val, pd.Timestamp):
                if pd.isnull(val):
                    return None
                val = val.strftime("%d-%m-%Y")   # e.g. "01-04-2025"
            
            val_str = str(val).strip()
            
            if not val_str or val_str.lower() in ('nan', 'nat', 'none'):
                return None

            # Step 2: Normalize separators (/ → -), mirrors: replace(trim(p_date_text), '/', '-')
            val_str = val_str.replace('/', '-')

            # Step 3: If datetime string came as "2025-04-01 00:00:00" from dtype=str read,
            # extract date part and reformat to DD-MM-YYYY
            if re.match(r'^\d{4}-\d{2}-\d{2}', val_str):
                # Parse ISO format and reformat to DD-MM-YYYY
                val_str = datetime.strptime(val_str[:10], "%Y-%m-%d").strftime("%d-%m-%Y")

            # Step 4: Parse strictly as DD-MM-YYYY, mirrors: to_date(p_date_text, 'DD-MM-YYYY')
            return datetime.strptime(val_str, "%d-%m-%Y").date()

        except Exception as e:
            # Mirrors: RAISE WARNING 'Unrecognized date format: %', p_date_text; RETURN NULL;
            print(f"⚠️  parse_date_dd_mm_yyyy: Unrecognized date format '{val}' → NULL", flush=True)
            return None

    def clean_numeric(val, cast_type):
        """Handles messy values like '1 +1', '2+1', '190.00'"""
        if val is None:
            return None
        val_str = str(val).strip()
        if val_str == '' or val_str.lower() == 'nan':
            return None
        try:
            if re.fullmatch(r'[\d\s\+\-\.]+', val_str):
                return cast_type(eval(val_str))  # safe: only digits and basic operators
            return cast_type(val_str)
        except Exception:
            return None

    # Apply parse_date_dd_mm_yyyy to every value in the date column
    df["date"] = df["date"].apply(parse_date_dd_mm_yyyy)

    insert_data = []
    for _, row in df.iterrows():
        insert_data.append({
            "date":             row.get("date"),
            "invoice_no":       row.get("invoice_no") or row.get("invoice no"),
            "customer_details": row.get("customer_details") or row.get("customer details"),
            "pincode":          row.get("pincode"),
            "order_id":         row.get("order_id") or row.get("order id"),
            "delhivery":        row.get("delhivery"),
            "item_shipped":     row.get("item_shipped") or row.get("item shipped"),
            "qnty":             clean_numeric(row.get("qnty"), int),
            "amount":           clean_numeric(row.get("amount"), float),
            "load_id":          load_id,
        })

    # Filter out completely empty rows
    insert_data = [
        r for r in insert_data
        if any([r.get("invoice_no"), r.get("order_id"), r.get("amount")])
    ]

    if not insert_data:
        print(f"DEBUG [{tenant_schema}]: No valid rows to insert.", flush=True)
        return

    conn.execute(
        text(f"""
            INSERT INTO "{tenant_schema}"."{target_table_name}" (
                date, invoice_no, customer_details, pincode,
                order_id, delhivery, item_shipped, qnty, amount, load_id
            ) VALUES (
                :date, :invoice_no, :customer_details, :pincode,
                :order_id, :delhivery, :item_shipped, :qnty, :amount, :load_id
            )
        """),
        insert_data
    )
    print(f"✅ Inserted {len(insert_data)} rows into {tenant_schema}.{target_table_name}", flush=True)


# ---------------------------------------------------------
# Add new tenants below, following the same pattern:
#
# def handle_new_tenant(conn, df, tenant_schema, load_id, ...):
#     conn.execute(text(f'CALL "{tenant_schema}".your_procedure()'))
# ---------------------------------------------------------



# ---------------------------------------------------------
# TENANT: tally_data (your new client)
# ---------------------------------------------------------

# ---------------------------------------------------------
# TENANT: sales_vouchers (Tally Export)
# Exact columns: Date, Particulars, Buyer, Buyer Address,
#   Voucher Type, Voucher No., Quantity, Rate, Value,
#   Gross Total, Sales A/C, Discount on Sales, CGST@, SGST@, Round Off
# ---------------------------------------------------------
def handle_tally_sales(conn, df_original, tenant_schema, target_table_name, load_id, log_load_error):
    import re
    from datetime import datetime
    import pandas as pd

    # Step 1: Normalize column names (strip whitespace only, keep original case)
    df = df_original.copy()
    df.columns = [str(c).strip() for c in df.columns]
    df = df.where(df.notna(), None)


    print(f"DEBUG [{tenant_schema}]: Columns after normalization: {df.columns.tolist()}", flush=True)
    
    if "Date" not in df.columns:
        raise Exception("❌ 'Date' column missing in Excel")

    # ── Helpers ────────────────────────────────────────────

    def parse_date(val):
        if val is None:
            return None
        try:
            if isinstance(val, pd.Timestamp):
                return None if pd.isnull(val) else val.date()
            val_str = str(val).strip().replace('/', '-')
            if not val_str or val_str.lower() in ('nan', 'nat', 'none'):
                return None
            # Tally exports as "2025-04-01 00:00:00" when read as str
            if re.match(r'^\d{4}-\d{2}-\d{2}', val_str):
                return datetime.strptime(val_str[:10], "%Y-%m-%d").date()
            return datetime.strptime(val_str, "%d-%m-%Y").date()
        except Exception:
            print(f"⚠️  parse_date: Unrecognized format '{val}' → NULL", flush=True)
            return None

    def clean_numeric(val, cast_type=float):
        if val is None:
            return None
        val_str = str(val).strip().replace(',', '')
        if val_str == '' or val_str.lower() in ('nan', 'none'):
            return None
        try:
            return cast_type(val_str)
        except Exception:
            return None

    def extract_mobile_numbers(address_str):
        """Extract up to 2 mobile/phone numbers from Buyer Address string."""
        if not address_str:
            return None, None
        # Match patterns like: 09867395993, 9226290517, 0250 2500748
        numbers = re.findall(r'\b(?:\d[\d\s]{8,12}\d)\b', str(address_str))
        # Clean spaces inside numbers
        numbers = [re.sub(r'\s+', '', n) for n in numbers]
        mobile_1 = numbers[0] if len(numbers) > 0 else None
        mobile_2 = numbers[1] if len(numbers) > 1 else None
        return mobile_1, mobile_2

    def extract_pin(address_str):
        """Extract 6-digit PIN code from Buyer Address string."""
        if not address_str:
            return None
        match = re.search(r'\b(\d{6})\b', str(address_str))
        return match.group(1) if match else None

    def extract_city_state(address_str):
        """
        Extract city and state from Buyer Address.
        Tally format: '..., City-PINCODE. State. @, ...'
        Example: 'Mumbai-400 004. Maharashtra. @'
        """
        if not address_str:
            return None, None
        # Pattern: word(s) followed by dash + pincode, then state before '@'
        city_match = re.search(r',\s*([A-Za-z\s\(\)]+?)-\d{6}', str(address_str))
        city = city_match.group(1).strip() if city_match else None

        # State typically appears after the PIN and before '@'
        state_match = re.search(r'\d{3}\s*\d{3}\.?\s+([A-Za-z\s]+?)\.?\s*@', str(address_str))
        state = state_match.group(1).strip() if state_match else None

        return city, state

    # Step 2: Parse date column
    df["Date"] = df["Date"].apply(parse_date)

    # Step 3: Build insert rows
    insert_data = []
    for _, row in df.iterrows():

        address       = row.get("Buyer Address")
        mobile_1, mobile_2 = extract_mobile_numbers(address)
        pin           = extract_pin(address)
        city, state   = extract_city_state(address)

        insert_data.append({
            # ── Core fields (exact Excel column names as keys) ──
            "date":               row.get("Date"),
            "particulars":        row.get("Particulars"),
            "buyer_name":         row.get("Buyer"),
            "buyer_address":      address,

            # ── Parsed from Buyer Address ───────────────────────
            "buyer_city":         city,
            "buyer_state":        state,
            "buyer_pin":          pin,
            "buyer_mobile_1":     mobile_1,
            "buyer_mobile_2":     mobile_2,

            # ── Voucher fields ──────────────────────────────────
            "voucher_type":       row.get("Voucher Type"),
            "voucher_no":         row.get("Voucher No."),        # exact: "Voucher No."

            # ── Item fields ─────────────────────────────────────
            "quantity":           clean_numeric(row.get("Quantity"), int),
            "rate":               clean_numeric(row.get("Rate"), float),
            "value":              clean_numeric(row.get("Value"), float),

            # ── Financial fields (plain numbers, no Dr/Cr in file) ──
            "gross_total":        clean_numeric(row.get("Gross Total"), float),
            "sales_ac":           clean_numeric(row.get("Sales A/C"), float),
            "discount_on_sales":  clean_numeric(row.get("Discount on Sales"), float),
            "cgst_amount":        clean_numeric(row.get("CGST@"), float),      # exact: "CGST@"
            "sgst_amount":        clean_numeric(row.get("SGST@"), float),      # exact: "SGST@"
            "round_off":          clean_numeric(row.get("Round Off"), float),

            "load_id":            load_id,
        })

    # Step 4: Filter out completely empty rows
    insert_data = [
        r for r in insert_data
        if any([r.get("voucher_no"), r.get("buyer_name"), r.get("date")])
    ]

    if not insert_data:
        print(f"DEBUG [{tenant_schema}]: No valid rows to insert.", flush=True)
        return

    # Step 5: Insert into DB
    conn.execute(
        text(f"""
            INSERT INTO "{tenant_schema}"."{target_table_name}" (
                date, particulars,
                buyer_name, buyer_address,
                buyer_city, buyer_state, buyer_pin,
                buyer_mobile_1, buyer_mobile_2,
                voucher_type, voucher_no,
                quantity, rate, value,
                gross_total, sales_ac,
                discount_on_sales,
                cgst_amount, sgst_amount,
                round_off, load_id
            ) VALUES (
                :date, :particulars,
                :buyer_name, :buyer_address,
                :buyer_city, :buyer_state, :buyer_pin,
                :buyer_mobile_1, :buyer_mobile_2,
                :voucher_type, :voucher_no,
                :quantity, :rate, :value,
                :gross_total, :sales_ac,
                :discount_on_sales,
                :cgst_amount, :sgst_amount,
                :round_off, :load_id
            )
        """),
        insert_data
    )
    print(f"✅ Inserted {len(insert_data)} rows into {tenant_schema}.{target_table_name}", flush=True)



# ---------------------------------------------------------
# TENANT: tally_data2 (your new client)
# ---------------------------------------------------------

def handle_tally_sales_v2(conn, df_original, tenant_schema, target_table_name, load_id, log_load_error):
    import re
    import pandas as pd
    from datetime import datetime
    from sqlalchemy import text

    df = df_original.copy()
    df.columns = [str(c).strip() for c in df.columns]
    df = df.where(pd.notna(df), None)

    print(f"DEBUG Columns: {df.columns.tolist()}", flush=True)

    # ── Date parser ───────────────────────────────────────────
    def parse_date(val):
        if val is None:
            return None
        try:
            if isinstance(val, pd.Timestamp):
                return None if pd.isnull(val) else val.date()
            val_str = str(val).strip().replace('/', '-')
            if not val_str or val_str.lower() in ('nan', 'nat', 'none'):
                return None
            # Tally exports as "2025-04-01 00:00:00" when read as str
            if re.match(r'^\d{4}-\d{2}-\d{2}', val_str):
                return datetime.strptime(val_str[:10], "%Y-%m-%d").date()
            return datetime.strptime(val_str, "%d-%m-%Y").date()
        except Exception:
            print(f"⚠️  parse_date: Unrecognized format '{val}' → NULL", flush=True)
            return None

    # ── Address parsers ───────────────────────────────────────
    def extract_pincode(address):
        if not address:
            return None
        match = re.search(r'\b\d{6}\b', str(address))
        return match.group(0) if match else None

    def extract_phones(address):
        if not address:
            return None, None
        numbers = re.findall(r'\b\d{10}\b', str(address))
        return (
            numbers[0] if len(numbers) > 0 else None,
            numbers[1] if len(numbers) > 1 else None
        )

    def extract_state(address):
        if not address:
            return None
        match = re.search(r'\d{6}\s*,?\s*([A-Za-z ]+)', str(address))
        return match.group(1).strip() if match else None

    # ── Build insert rows ─────────────────────────────────────
    insert_data = []
    for _, row in df.iterrows():
        address = row.get("Buyer Address")
        phone1, phone2 = extract_phones(address)

        insert_data.append({
            "date":              parse_date(row.get("Date")),
            "particulars":       row.get("Particulars"),
            "buyer":             row.get("Buyer"),
            "buyer_address":     address,
            "voucher_type":      row.get("Voucher Type"),
            "voucher_no":        row.get("Voucher No."),
            "order_no_date":     row.get("Order No. & Date"),
            "terms_payment":     row.get("Terms of Payment"),
            "other_references":  row.get("Other References"),
            "terms_delivery":    row.get("Terms of Delivery"),
            "quantity":          row.get("Quantity"),
            "rate":              row.get("Rate"),
            "value":             row.get("Value"),
            "gross_total":       row.get("Gross Total"),
            "gst_sales":         row.get("GST SALES"),
            "cgst_6":            row.get("Output CGST @ 6%"),
            "sgst_6":            row.get("Output SGST @ 6%"),
            "rounded_off":       row.get("Rounded Off"),
            "transport_charges": row.get("Transportation & Forwarding Charges"),
            "igst_18":           row.get("Output IGST @ 18%"),
            "shipping_charges":  row.get("Shipping Charges"),
            "igst_12":           row.get("Output IGST @ 12%"),
            "cgst_2_5":          row.get("Output CGST @ 2.5%"),
            "sgst_2_5":          row.get("Output SGST @ 2.5%"),
            "igst_5":            row.get("Output IGST @ 5%"),
            "cost_of_sales":     row.get("Cost of Sales"),
            "gross_profit":      row.get("Gross Profit"),
            "gp_percent":        row.get("GP %"),
            "buyer_pincode":     extract_pincode(address),
            "buyer_state":       extract_state(address),
            "buyer_phone_1":     phone1,
            "buyer_phone_2":     phone2,
            "load_id":           load_id,
        })

    # Drop rows with no meaningful data
    insert_data = [
        r for r in insert_data
        if any([r.get("buyer"), r.get("voucher_no"), r.get("date")])
    ]

    if not insert_data:
        print("DEBUG: No valid rows to insert", flush=True)
        return

    conn.execute(
        text(f"""
            INSERT INTO "{tenant_schema}"."{target_table_name}" (
                "Date", "Particulars", "Buyer", "Buyer Address",
                "Voucher Type", "Voucher No.", "Order No. & Date",
                "Terms of Payment", "Other References", "Terms of Delivery",
                "Quantity", "Rate", "Value", "Gross Total",
                "GST SALES", "Output CGST @ 6%", "Output SGST @ 6%",
                "Rounded Off", "Transportation & Forwarding Charges",
                "Output IGST @ 18%", "Shipping Charges",
                "Output IGST @ 12%", "Output CGST @ 2.5%",
                "Output SGST @ 2.5%", "Output IGST @ 5%",
                "Cost of Sales", "Gross Profit", "GP %",
                buyer_pincode, buyer_state, buyer_phone_1, buyer_phone_2,
                load_id
            ) VALUES (
                :date, :particulars, :buyer, :buyer_address,
                :voucher_type, :voucher_no, :order_no_date,
                :terms_payment, :other_references, :terms_delivery,
                :quantity, :rate, :value, :gross_total,
                :gst_sales, :cgst_6, :sgst_6,
                :rounded_off, :transport_charges,
                :igst_18, :shipping_charges,
                :igst_12, :cgst_2_5,
                :sgst_2_5, :igst_5,
                :cost_of_sales, :gross_profit, :gp_percent,
                :buyer_pincode, :buyer_state, :buyer_phone_1, :buyer_phone_2,
                :load_id
            )
        """),
        insert_data
    )

    print(f"DEBUG: Inserted {len(insert_data)} rows into {tenant_schema}.{target_table_name}", flush=True)


# ----------------------------------------------------------------------------------------
#  New Accres Invoices Data
# ----------------------------------------------------------------------------------------

def handle_accrec(conn, df, tenant_schema, target_table_name, load_id, log_load_error):
    """
    Handler for AccRec (Accounts Receivable) invoice files.
    Source: Tally / manual export — Tab or CSV separated.

    Expected columns (exact names from export):
        Invoice No./Txn No., Date, Parent Party, Party Name,
        Category, GSTIN, Party Address, PINCODE, CITY, STATE,
        Party Phone No., Total Amount, Item Name, Description,
        Quantity, Unit, UnitPrice, Discount, Tax Percent, Tax, Amount
    """
    import re
    from datetime import datetime

    # ─────────────────────────────────────────────────────────────
    #  STEP 1: Validate required columns
    # ─────────────────────────────────────────────────────────────
    REQUIRED_COLS = ["Invoice No./Txn No.", "Date", "Party Name", "Amount"]
    missing = [c for c in REQUIRED_COLS if c not in df.columns]
    if missing:
        raise ValueError(
            f"Missing required columns in uploaded file: {missing}. "
            f"Found columns: {list(df.columns)}"
        )

    print(f"DEBUG [{tenant_schema}]: AccRec file — {len(df)} rows", flush=True)
    print(f"DEBUG [{tenant_schema}]: Columns: {list(df.columns)}", flush=True)

    # ─────────────────────────────────────────────────────────────
    #  STEP 2: Column rename map → clean DB column names
    # ─────────────────────────────────────────────────────────────
    COLUMN_MAP = {
        "Invoice No./Txn No.": "invoice_no",
        "Date":                "invoice_date",
        "Parent Party":        "parent_party",
        "Party Name":          "party_name",
        "Category":            "category",
        "GSTIN":               "gstin",
        "Party Address":       "party_address",
        "PINCODE":             "pincode",
        "CITY":                "city",
        "STATE":               "state",
        "Party Phone No.":     "party_phone",
        "Total Amount":        "total_amount",
        "Item Name":           "item_name",
        "Description":         "description",
        "Quantity":            "quantity",
        "Unit":                "unit",
        "UnitPrice":           "unit_price",
        "Discount":            "discount",
        "Tax Percent":         "tax_percent",
        "Tax":                 "tax",
        "Amount":              "amount",
    }

    # Rename only columns that exist in the file
    existing_map = {k: v for k, v in COLUMN_MAP.items() if k in df.columns}
    df = df.rename(columns=existing_map)

    # ─────────────────────────────────────────────────────────────
    #  STEP 3: Clean nullish strings
    # ─────────────────────────────────────────────────────────────
    df = df.replace(
        {'nan': None, 'NaT': None, 'None': None, '<NA>': None, '': None}
    )
    # Strip whitespace from all string columns
    for col in df.select_dtypes(include='object').columns:
        df[col] = df[col].str.strip()
    # Re-replace empty strings after strip
    df = df.replace({'': None})

    # ─────────────────────────────────────────────────────────────
    #  STEP 4: Explicit type conversions
    # ─────────────────────────────────────────────────────────────

    # ── Date: DD/MM/YYYY → Python date ───────────────────────────
    if "invoice_date" in df.columns:
        df["invoice_date"] = pd.to_datetime(
            df["invoice_date"], dayfirst=True, errors="coerce"
        ).dt.date

    # ── Amount column: remove commas, spaces, ₹ symbol ───────────
    def clean_amount(val):
        """'  17,500 '  →  17500.0"""
        if val is None:
            return None
        cleaned = re.sub(r'[₹,\s]', '', str(val))
        try:
            return float(cleaned) if cleaned else None
        except ValueError:
            return None

    NUMERIC_COLS = [
        "total_amount", "unit_price", "discount",
        "tax_percent", "tax", "amount"
    ]
    for col in NUMERIC_COLS:
        if col in df.columns:
            df[col] = df[col].apply(clean_amount)

    # ── Quantity: numeric ─────────────────────────────────────────
    if "quantity" in df.columns:
        df["quantity"] = pd.to_numeric(df["quantity"], errors="coerce")

    # ── PINCODE and phone: keep as text, no formatting ────────────
    for col in ["pincode", "party_phone"]:
        if col in df.columns:
            df[col] = df[col].astype(str).replace('nan', None)

    print(
        f"DEBUG [{tenant_schema}]: Types after conversion: "
        f"{ {c: str(df[c].dtype) for c in df.columns} }",
        flush=True
    )

    # ─────────────────────────────────────────────────────────────
    #  STEP 5: Add system columns
    # ─────────────────────────────────────────────────────────────
    df["load_id"] = load_id
    df["row_no"]  = range(1, len(df) + 1)

    # ─────────────────────────────────────────────────────────────
    #  STEP 6: Keep only columns that exist in the DB table
    # ─────────────────────────────────────────────────────────────
    table_columns = conn.execute(text("""
        SELECT column_name
        FROM information_schema.columns
        WHERE table_schema = :schema
          AND table_name   = :table
    """), {
        "schema": tenant_schema,
        "table":  target_table_name
    }).scalars().all()

    # Drop columns not in DB, keep all DB columns that exist in df
    df = df[[col for col in df.columns if col in table_columns]]

    print(
        f"DEBUG [{tenant_schema}]: Final columns for insert: {list(df.columns)}",
        flush=True
    )

    # ─────────────────────────────────────────────────────────────
    #  STEP 7: Insert (append — no truncate, each upload adds rows)
    # ─────────────────────────────────────────────────────────────
    print(
        f"DEBUG [{tenant_schema}]: Inserting {len(df)} invoice rows...",
        flush=True
    )
    df.to_sql(
        target_table_name,
        con=conn,
        schema=tenant_schema,
        if_exists="append",
        index=False,
    )
    print(
        f"DEBUG [{tenant_schema}]: AccRec insert done. load_id={load_id}",
        flush=True
    )    