"""
Snapshot the shinde_shoes stock-pipeline fact tables to an Excel file.

Run this ONCE right before uploading a test file, and ONCE right after
processing it, using the same DB and two different labels. Nothing in
this script writes to the database -- it only reads and saves to Excel.

Usage:
    python snapshot_stock_tables.py "postgresql://user:pass@host:port/dbname" before_sept8
    python snapshot_stock_tables.py "postgresql://user:pass@host:port/dbname" after_sept8

Each run writes a timestamped .xlsx file with these sheets:
  - summary              headline totals + reconciliation status, one row
  - stock_fact_master    full table dump
  - purchase_fact_master full table dump
  - stock_mismatches     only present if fn_check_stock_fact_master_reconciliation() found any
  - purchase_mismatches  only present if fn_check_purchase_fact_master_reconciliation() found any

Requires: pandas, sqlalchemy, psycopg2-binary, openpyxl
    pip install pandas sqlalchemy psycopg2-binary openpyxl
"""
import sys
from datetime import datetime

import pandas as pd
from sqlalchemy import create_engine, text


def main():
    if len(sys.argv) != 3:
        print("Usage: python snapshot_stock_tables.py <database_url> <label>")
        print('Example label: before_sept8   or   after_sept8')
        sys.exit(1)

    db_url, label = sys.argv[1], sys.argv[2]
    engine = create_engine(db_url)

    stock_fact = pd.read_sql(
        'SELECT * FROM shinde_shoes.stock_fact_master ORDER BY "SKUKey", "LocationKey"',
        engine,
    )
    purchase_fact = pd.read_sql(
        'SELECT * FROM shinde_shoes.purchase_fact_master ORDER BY "SKUKey", "LocationKey"',
        engine,
    )

    with engine.connect() as conn:
        totals = conn.execute(text("""
            SELECT
                (SELECT COUNT(*) FROM shinde_shoes.stock_fact_master)                          AS stock_fact_rows,
                (SELECT SUM(current_qty) FROM shinde_shoes.stock_fact_master)                   AS stock_fact_total_qty,
                (SELECT COUNT(*) FROM shinde_shoes.stock_fact_master WHERE current_qty < 0)     AS negative_rows,
                (SELECT COUNT(*) FROM shinde_shoes.purchase_fact_master)                        AS purchase_fact_rows,
                (SELECT SUM(total_purchased_qty) FROM shinde_shoes.purchase_fact_master)        AS purchase_fact_total_qty,
                (SELECT MAX(transaction_date) FROM shinde_shoes.stock_transaction WHERE movement_type='OPENING')  AS max_opening_date,
                (SELECT MAX(transaction_date) FROM shinde_shoes.stock_transaction WHERE movement_type='PURCHASE') AS max_purchase_date,
                (SELECT MAX(transaction_date) FROM shinde_shoes.stock_transaction WHERE movement_type='SALE')     AS max_sale_date,
                (SELECT COUNT(*) FROM shinde_shoes.stock_transaction)                            AS ledger_row_count,
                (SELECT SUM(quantity) FROM shinde_shoes.stock_transaction)                       AS ledger_total_qty,
                (SELECT COUNT(*) FROM shinde_shoes."FactSalesDetail" WHERE posted_to_stock = false) AS sales_lines_unposted
        """)).mappings().first()

        recon_stock = conn.execute(
            text("SELECT * FROM shinde_shoes.fn_check_stock_fact_master_reconciliation()")
        ).mappings().all()
        recon_purchase = conn.execute(
            text("SELECT * FROM shinde_shoes.fn_check_purchase_fact_master_reconciliation()")
        ).mappings().all()

    summary = pd.DataFrame([{
        "label": label,
        "snapshot_taken_at": datetime.now().isoformat(timespec="seconds"),
        **dict(totals),
        "stock_reconciliation_mismatches": len(recon_stock),
        "purchase_reconciliation_mismatches": len(recon_purchase),
    }])

    out_path = f"snapshot_{label}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.xlsx"
    with pd.ExcelWriter(out_path, engine="openpyxl") as writer:
        summary.to_excel(writer, sheet_name="summary", index=False)
        stock_fact.to_excel(writer, sheet_name="stock_fact_master", index=False)
        purchase_fact.to_excel(writer, sheet_name="purchase_fact_master", index=False)
        if recon_stock:
            pd.DataFrame(recon_stock).to_excel(writer, sheet_name="stock_mismatches", index=False)
        if recon_purchase:
            pd.DataFrame(recon_purchase).to_excel(writer, sheet_name="purchase_mismatches", index=False)

    print(f"Saved: {out_path}\n")
    print(summary.to_string(index=False))


if __name__ == "__main__":
    main()