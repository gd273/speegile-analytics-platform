"""
Compare a "before" and "after" snapshot produced by snapshot_stock_tables.py
so you can see exactly what a test upload changed.

Usage:
    python compare_snapshots.py snapshot_before_sept8_20260912_153806.xlsx snapshot_after_sept8_20260912_154001.xlsx

Requires: pandas, openpyxl
    pip install pandas openpyxl

This prints the comparison to the console AND saves it as a new .xlsx file
(comparison_<timestamp>.xlsx) with 3 sheets: summary, changed_rows, new_rows
-- so you have something to open and browse, not just terminal text.
"""
import sys
import traceback
from datetime import datetime

import pandas as pd


def main():
    if len(sys.argv) != 3:
        print("Usage: python compare_snapshots.py <before.xlsx> <after.xlsx>")
        sys.exit(1)

    before_path, after_path = sys.argv[1], sys.argv[2]

    before_summary = pd.read_excel(before_path, sheet_name="summary")
    after_summary = pd.read_excel(after_path, sheet_name="summary")

    print("=== Headline totals: before vs after ===")
    compare_cols = [c for c in before_summary.columns if c not in ("label", "snapshot_taken_at")]
    summary_rows = []
    for col in compare_cols:
        b = before_summary.iloc[0][col]
        a = after_summary.iloc[0][col]
        changed_flag = bool(b != a)
        flag_text = "  <-- changed" if changed_flag else ""
        print(f"{col:38s} before={b!s:>14s} after={a!s:>14s}{flag_text}")
        summary_rows.append({"metric": col, "before": b, "after": a, "changed": changed_flag})
    summary_df = pd.DataFrame(summary_rows)

    before = pd.read_excel(before_path, sheet_name="stock_fact_master")
    after = pd.read_excel(after_path, sheet_name="stock_fact_master")

    keep_cols = ["SKUKey", "LocationKey", "current_qty"]
    if "SKU" in after.columns:
        keep_cols_after = keep_cols + ["SKU"]
    else:
        keep_cols_after = keep_cols

    merged = before[keep_cols].merge(
        after[keep_cols_after],
        on=["SKUKey", "LocationKey"],
        how="outer",
        suffixes=("_before", "_after"),
    )
    merged["qty_change"] = merged["current_qty_after"].fillna(0) - merged["current_qty_before"].fillna(0)
    changed = merged[merged["qty_change"] != 0].sort_values("qty_change")

    print("\n=== Per-SKU+Location current_qty changes ===")
    if changed.empty:
        print("No SKU+Location rows changed current_qty at all. Nothing was posted -- "
              "check the upload actually ran and sp_process_sales_stock_impact() "
              "(or the relevant process procedure) was called.")
    else:
        print(f"{len(changed)} row(s) changed (also saved to the output Excel file):")
        print(changed.head(30).to_string(index=False))
        if len(changed) > 30:
            print(f"... and {len(changed) - 30} more row(s), see the Excel file for the full list.")

    new_rows = merged[merged["current_qty_before"].isna()]
    print(f"\n=== New SKU+Location rows created ({len(new_rows)}) ===")

    stock_mismatch_before = int(before_summary.iloc[0]["stock_reconciliation_mismatches"])
    stock_mismatch_after = int(after_summary.iloc[0]["stock_reconciliation_mismatches"])
    print("\n=== Reconciliation ===")
    print(f"stock_fact_master mismatches: before={stock_mismatch_before} after={stock_mismatch_after}")
    if stock_mismatch_after != 0:
        print("WARNING: after-state has mismatches -- investigate before trusting this test as a pass.")

    out_path = f"comparison_{datetime.now().strftime('%Y%m%d_%H%M%S')}.xlsx"
    with pd.ExcelWriter(out_path, engine="openpyxl") as writer:
        summary_df.to_excel(writer, sheet_name="summary_comparison", index=False)
        changed.to_excel(writer, sheet_name="changed_rows", index=False)
        new_rows.to_excel(writer, sheet_name="new_rows", index=False)

    print(f"\nSaved comparison to: {out_path}")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        print("\n--- ERROR ---")
        traceback.print_exc()
        input("\nPress Enter to close...")