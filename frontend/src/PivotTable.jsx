/**
 * PivotTable.jsx — v4
 * ─────────────────────────────────────────────────────────────────
 * Fix 1: Pivot colours — rules use metric name (e.g. "MIN(rn)")
 *         as column, NOT centername. Evaluate against mk not combo[0].
 * Fix 2: Missing header rows — add "Metric / centername / quarter_label"
 *         label rows exactly matching Superset's 3-row header structure.
 * Fix 3: Column order — use columnOrder from backend to sort colCombos
 *         so centername groups appear in Superset's exact sequence.
 */

import React, { useMemo, useState } from "react";

const ROWS_PER_PAGE = 1000;

// ── Excel export (proper .xlsx with bold headers + borders) ─────
// Uses SheetJS loaded from CDN — no npm install needed
function exportToExcel(filename, headers, rows2d) {
  const doExport = (XLSX) => {
    const wsData = [headers, ...rows2d];
    const ws = XLSX.utils.aoa_to_sheet(wsData);

    const colCount = headers.length;
    const rowCount = wsData.length;
    const borderStyle = { style: "thin", color: { rgb: "000000" } };
    const border = { top: borderStyle, bottom: borderStyle, left: borderStyle, right: borderStyle };

    for (let R = 0; R < rowCount; R++) {
      for (let C = 0; C < colCount; C++) {
        const cellRef = XLSX.utils.encode_cell({ r: R, c: C });
        if (!ws[cellRef]) ws[cellRef] = { v: "", t: "s" };
        ws[cellRef].s = {
          border,
          font: R === 0 ? { bold: true, sz: 11 } : { sz: 10 },
          alignment: { vertical: "center", wrapText: false },
        };
      }
    }

    ws["!cols"] = headers.map((h, ci) => {
      const maxLen = Math.max(String(h).length, ...rows2d.map(r => String(r[ci] ?? "").length));
      return { wch: Math.min(Math.max(maxLen + 2, 10), 40) };
    });

    const wb = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(wb, ws, "Data");
    XLSX.writeFile(wb, filename.endsWith(".xlsx") ? filename : filename + ".xlsx");
  };

  // Load SheetJS from CDN if not already loaded
  if (window.XLSX) {
    doExport(window.XLSX);
  } else {
    const script = document.createElement("script");
    script.src = "https://cdnjs.cloudflare.com/ajax/libs/xlsx/0.18.5/xlsx.full.min.js";
    script.onload = () => doExport(window.XLSX);
    script.onerror = () => {
      // Fallback to CSV if CDN fails
      const escape = (v) => { const s = String(v ?? ""); return s.includes(",") || s.includes('"') ? `"${s.replace(/"/g, '""')}"` : s; };
      const lines = [headers.map(escape).join(","), ...rows2d.map(r => r.map(escape).join(","))];
      const blob = new Blob([lines.join("")], { type: "text/csv;charset=utf-8;" });
      const a = Object.assign(document.createElement("a"), { href: URL.createObjectURL(blob), download: filename.replace(/\.xlsx$/, ".csv") });
      a.click(); URL.revokeObjectURL(a.href);
    };
    document.head.appendChild(script);
  }
}

// Export button component
function ExportBtn({ onClick }) {
  return (
    <button
      onClick={onClick}
      title="Export to Excel (.xlsx)"
      style={{
        display: "flex", alignItems: "center", gap: 5,
        padding: "4px 10px", borderRadius: 6, fontSize: 11, fontWeight: 600,
        border: "1px solid rgba(31,168,201,0.35)",
        background: "rgba(31,168,201,0.08)", color: "#1FA8C9",
        cursor: "pointer", flexShrink: 0, transition: "all .15s",
      }}
      onMouseEnter={e => { e.currentTarget.style.background = "rgba(31,168,201,0.18)"; }}
      onMouseLeave={e => { e.currentTarget.style.background = "rgba(31,168,201,0.08)"; }}
    >
      ⬇ Export xlsx
    </button>
  );
}

// Search bar component — flexible, takes available space, min 120px max 280px
function SearchBar({ value, onChange, placeholder = "Search..." }) {
  return (
    <div style={{ position: "relative", flex: 1, minWidth: 120, maxWidth: 280 }}>
      <svg style={{ position: "absolute", left: 8, top: "50%", transform: "translateY(-50%)",
                    width: 12, height: 12, opacity: 0.4, pointerEvents: "none" }}
           viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
        <circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/>
      </svg>
      <input
        type="text"
        value={value}
        onChange={e => onChange(e.target.value)}
        placeholder={placeholder}
        style={{
          width: "100%", boxSizing: "border-box",
          background: "#12151f",
          border: "1px solid rgba(255,255,255,0.09)",
          borderRadius: 6,
          padding: "5px 28px 5px 28px",
          color: "#c9d1d9", fontSize: 11, outline: "none",
          transition: "border-color .15s",
        }}
        onFocus={e => { e.currentTarget.style.borderColor = "rgba(31,168,201,0.45)"; }}
        onBlur={e =>  { e.currentTarget.style.borderColor = "rgba(255,255,255,0.09)"; }}
      />
      {value && (
        <span onClick={() => onChange("")} style={{
          position: "absolute", right: 8, top: "50%", transform: "translateY(-50%)",
          fontSize: 10, color: "#4a5568", cursor: "pointer", userSelect: "none",
        }}>✕</span>
      )}
    </div>
  );
}
const CURRENCY_COL_PATTERN =
  /amount|net|sales|revenue|value|cost|price|mrp|sell|earning|income|profit|loss/i;

// Columns that must NEVER be treated as "numbers to format" — mobile/phone/contact
// numbers, pincodes, IDs, invoice numbers etc. These should always render as plain text,
// never get thousands-separator commas, currency symbols, or right-alignment.
const ID_COL_PATTERN =
  /\bid\b|_id$|^id_|mobile|phone|contact|tel|fax|whatsapp|pincode|zip|postal|pin_code|\bpin\b|order[_ ]?no|order_id|invoice|^no\.?$|#/i;

// ── Conditional formatting evaluator ─────────────────────────────
// For PIVOT: Superset rules use the metric label (e.g. "MIN(rn)") as column.
// For FLAT:  rules use the actual column name.
function evalConditionalColor(cellValue, colName, rules) {
  if (!rules?.length) return null;
  const matching = rules.filter((r) => r.column === colName);
  if (!matching.length) return null;
  const num = Number(cellValue);
  for (const rule of matching) {
    const rv = rule.value;
    const op = rule.operator;
    let match = false;
    if (op === "==" || op === "=")  match = num === rv;
    else if (op === "!=")           match = num !== rv;
    else if (op === ">")            match = num > rv;
    else if (op === ">=")           match = num >= rv;
    else if (op === "<")            match = num < rv;
    else if (op === "<=")           match = num <= rv;
    if (match) return rule.color;
  }
  return null;
}

function contrastColor(hex) {
  if (!hex) return "#c9d1d9";
  // Handle rgba() format
  if (hex.startsWith("rgba")) {
    const m = hex.match(/rgba?\((\d+),\s*(\d+),\s*(\d+)/);
    if (!m) return "#ffffff";
    const lum2 = (0.299 * m[1] + 0.587 * m[2] + 0.114 * m[3]) / 255;
    return lum2 > 0.55 ? "#000000" : "#ffffff";
  }
  const h = hex.replace("#", "");
  const r = parseInt(h.substr(0, 2), 16);
  const g = parseInt(h.substr(2, 2), 16);
  const b = parseInt(h.substr(4, 2), 16);
  const lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
  return lum > 0.55 ? "#000000" : "#ffffff";
}

// Magnitude-based colour — used when show_cell_bars=true
// Mimics Superset's cell bar: light teal (low) → strong teal (high)
function cellBarColor(value, colValues) {
  const nums = colValues
    .filter(v => v !== null && v !== undefined && !isNaN(Number(v)))
    .map(Number);
  if (nums.length < 2) return null;
  const min = Math.min(...nums);
  const max = Math.max(...nums);
  if (min === max) return null;
  const pct = (Number(value) - min) / (max - min);
  const alpha = 0.12 + pct * 0.65;
  return `rgba(31,168,201,${alpha.toFixed(2)})`;
}

// ── Number / Date formatter ────────────────────────────────────────
function isTimestampMs(n) {
  return Number.isInteger(n) && n > 1_000_000_000_000;
}
// Simple, unambiguous ISO date — matches Superset's own default date display (YYYY-MM-DD)
function fmtDateMs(ms) {
  const d = new Date(ms);
  const yyyy = d.getFullYear();
  const mm = String(d.getMonth() + 1).padStart(2, "0");
  const dd = String(d.getDate()).padStart(2, "0");
  return `${yyyy}-${mm}-${dd}`;
}
function fmtTableNum(val, colName = "") {
  if (val === null || val === undefined || val === "") return "";
  // Mobile/phone/contact/ID/pincode etc. columns: always render exactly as received,
  // never run through number formatting (no commas, no currency symbol).
  if (colName && ID_COL_PATTERN.test(colName)) return String(val);
  const n = Number(val);
  if (isNaN(n)) return String(val);
  if (isTimestampMs(n)) return fmtDateMs(n);
  const formatted = new Intl.NumberFormat("en-IN", {
    maximumFractionDigits: 2, minimumFractionDigits: 0,
  }).format(n);
  if (colName && CURRENCY_COL_PATTERN.test(colName)) return `₹${formatted}`;
  return formatted;
}

// Value used specifically for Excel export. Differs from fmtTableNum in that
// plain numeric metric columns are kept as real numbers (so totals/sums still
// work in Excel), while dates are converted to a clean ISO string and
// mobile/ID-type columns are forced to text so Excel doesn't strip leading
// zeros or reformat them.
function exportCellValue(val, colName = "") {
  if (val === null || val === undefined) return "";
  if (colName && ID_COL_PATTERN.test(colName)) return String(val);
  const n = Number(val);
  if (!isNaN(n) && isTimestampMs(n)) return fmtDateMs(n);
  return val;
}

// ── Quarter/period sorter ─────────────────────────────────────────
// Sorts values that look like "2025-Q1", "2024-Q4", "Jan-25" etc chronologically.
// Non-period strings fall back to locale sort.
function sortPeriodValues(vals) {
  // Match "YYYY-QN" e.g. "2025-Q1"
  const quarterRe = /^(\d{4})-Q(\d)$/;
  // Match "YYYY-MM" e.g. "2025-01"
  const yearMonthRe = /^(\d{4})-(\d{2})$/;
  // Match "MMM-YY" e.g. "Jan-25", "Apr-25"
  const monYearRe = /^([A-Za-z]{3})-(\d{2})$/;
  const MONTHS = { jan:1,feb:2,mar:3,apr:4,may:5,jun:6,jul:7,aug:8,sep:9,oct:10,nov:11,dec:12 };

  const toNum = (v) => {
    let m;
    if ((m = String(v).match(quarterRe)))  return Number(m[1]) * 10 + Number(m[2]);
    if ((m = String(v).match(yearMonthRe))) return Number(m[1]) * 100 + Number(m[2]);
    if ((m = String(v).match(monYearRe))) {
      const mo = MONTHS[m[1].toLowerCase()] || 0;
      const yr = Number(m[2]) + 2000;
      return yr * 100 + mo;
    }
    return null;
  };

  const allNumeric = vals.every(v => toNum(v) !== null);
  if (!allNumeric) return [...vals].sort((a, b) => String(a).localeCompare(String(b)));
  return [...vals].sort((a, b) => toNum(a) - toNum(b));
}

// Normalizes a column-name-like string for tolerant matching (trims, lowercases,
// collapses internal whitespace). Used to line up backend `columnOrder` values
// against actual data keys even if casing/whitespace differs slightly.
function normKey(s) {
  return String(s ?? "").trim().toLowerCase().replace(/\s+/g, " ");
}

// ── Pivot builder ─────────────────────────────────────────────────
// columnOrder : top-level colDim values in desired order (centername)
// colnames    : full column list from API response (used for flat table)
function buildPivot(rows, groupbyRows, groupbyColumns, metricKeys, columnOrder) {
  if (!rows?.length || !groupbyColumns?.length || !metricKeys?.length) return null;
  const rowDims = groupbyRows || [];
  const colDims = groupbyColumns || [];
  const metrics = metricKeys || [];

  // ── Build colCombos directly from actual data rows ──────────────
  // This ensures each centername only shows quarters it actually has data for,
  // matching Superset's exact pivot layout (no phantom empty columns).
  // Insertion order is preserved = Superset's configured sort order.

  // Step 1: collect unique top-level values (centername) in insertion order
  const topDimSeen = new Set();
  const topDimVals = [];
  for (const r of rows) {
    const v = r[colDims[0]];
    if (v != null && !topDimSeen.has(v)) { topDimSeen.add(v); topDimVals.push(v); }
  }

  // Step 2: sort top-level by columnOrder if provided, else alphabetically.
  // Matching is done on a normalized (trimmed/lowercased) key so that minor
  // casing/whitespace differences between the backend-provided columnOrder
  // and the actual data values don't silently break the intended order.
  let sortedTopVals;
  if (columnOrder?.length) {
    const orderMap = new Map(columnOrder.map((v, i) => [normKey(v), i]));
    sortedTopVals = [...topDimVals].sort((a, b) => {
      const ia = orderMap.has(normKey(a)) ? orderMap.get(normKey(a)) : 9999;
      const ib = orderMap.has(normKey(b)) ? orderMap.get(normKey(b)) : 9999;
      return ia - ib;
    });
  } else {
    sortedTopVals = [...topDimVals].sort((a, b) => String(a).localeCompare(String(b)));
  }

  // Step 3: for each top-level value, collect its sub-dim combos
  // Sub-dims (quarters) are sorted chronologically using sortPeriodValues
  // because Superset returns rows sorted by metric value (rank), not by quarter
  const colCombos = [];
  for (const topVal of sortedTopVals) {
    if (colDims.length === 1) {
      colCombos.push([topVal]);
    } else {
      const subSeen = new Set();
      const subVals = [];
      for (const r of rows) {
        if (r[colDims[0]] !== topVal) continue;
        const subKey = colDims.slice(1).map(d => r[d] ?? "").join("||");
        if (!subSeen.has(subKey)) {
          subSeen.add(subKey);
          subVals.push(colDims.slice(1).map(d => r[d] ?? ""));
        }
      }
      // Sort sub-dim arrays chronologically by their first element (quarter_label)
      // sortPeriodValues returns sorted array; use it to get numeric rank of each value
      const allSubFirst = subVals.map(s => s[0]);
      const sortedSubFirst = sortPeriodValues(allSubFirst);
      const subRankMap = new Map(sortedSubFirst.map((v, i) => [v, i]));
      subVals.sort((a, b) => (subRankMap.get(a[0]) ?? 999) - (subRankMap.get(b[0]) ?? 999));
      for (const subArr of subVals) {
        colCombos.push([topVal, ...subArr]);
      }
    }
  }

  // colDimValues still needed for header rendering (unique values per level)
  const colDimValues = colDims.map((dim) => {
    const seen = new Set();
    const vals = [];
    for (const combo of colCombos) {
      const v = combo[colDims.indexOf(dim)];
      if (v != null && !seen.has(v)) { seen.add(v); vals.push(v); }
    }
    return vals;
  });


  const rowMap = new Map();
  for (const row of rows) {
    const rowKey = rowDims.map((d) => row[d] ?? "").join("||");
    if (!rowMap.has(rowKey)) {
      rowMap.set(rowKey, { dimValues: rowDims.map((d) => row[d] ?? ""), metricMap: {} });
    }
    const entry = rowMap.get(rowKey);
    for (const mk of metrics) {
      const cellKey = colDims.map((d) => row[d] ?? "").join("||") + "||" + mk;
      entry.metricMap[cellKey] = row[mk];
    }
  }
  return { rowDims, colDims, colDimValues, colCombos, metrics, rowMap };
}

function PageTabs({ totalRows, page, setPage }) {
  if (totalRows <= ROWS_PER_PAGE) return null;
  const totalPages = Math.ceil(totalRows / ROWS_PER_PAGE);

  return (
    <div style={{
      display: "flex",
      alignItems: "center",
      borderTop: "1px solid rgba(255,255,255,0.07)",
      background: "#12151f",
      padding: "6px 10px",
      gap: 8,
      minHeight: 38,
    }}>
      {/* ── Fixed left: row count — never scrolls ── */}
      <span style={{
        fontSize: 11,
        color: "#64748b",
        whiteSpace: "nowrap",
        flexShrink: 0,
      }}>
        {totalRows.toLocaleString()} rows
      </span>

      {/* ── Scrollable right: page buttons ── */}
      <div style={{
        display: "flex",
        alignItems: "center",
        gap: 4,
        overflowX: "auto",
        flex: 1,
        paddingBottom: 2,
        scrollbarWidth: "thin",
        scrollbarColor: "rgba(31,168,201,0.4) transparent",
      }}>
        {Array.from({ length: totalPages }, (_, i) => {
          const start = i * ROWS_PER_PAGE + 1;
          const end   = Math.min((i + 1) * ROWS_PER_PAGE, totalRows);
          const active = page === i;
          return (
            <button
              key={i}
              onClick={() => setPage(i)}
              style={{
                flexShrink: 0,
                padding: "3px 10px",
                borderRadius: 6,
                fontSize: 11,
                fontWeight: active ? 700 : 400,
                border: `1px solid ${active ? "#1FA8C9" : "rgba(255,255,255,0.1)"}`,
                background: active ? "rgba(31,168,201,0.18)" : "transparent",
                color: active ? "#1FA8C9" : "#64748b",
                cursor: "pointer",
                whiteSpace: "nowrap",
              }}
            >
              {start.toLocaleString()}–{end.toLocaleString()}
            </button>
          );
        })}
      </div>
    </div>
  );
}

// ── Shared styles ─────────────────────────────────────────────────
const S = {
  wrapper:   { overflowX: "auto", overflowY: "auto", maxHeight: "100%", fontSize: 12,
               fontFamily: "'Inter','Roboto',sans-serif" },
  table:     { borderCollapse: "collapse", width: "100%", minWidth: 400 },

  // FIX 2: Header label rows (Metric / centername / quarter_label)
  thLabel:   { padding: "3px 8px", textAlign: "left", fontWeight: 400, fontSize: 10,
               whiteSpace: "nowrap", borderBottom: "1px solid rgba(255,255,255,0.06)",
               borderRight: "1px solid rgba(255,255,255,0.04)", background: "#0d1117",
               color: "#4a5568", fontStyle: "italic" },
  thLabelDim:{ padding: "3px 8px", textAlign: "left", fontWeight: 400, fontSize: 10,
               whiteSpace: "nowrap", borderBottom: "1px solid rgba(255,255,255,0.06)",
               borderRight: "1px solid rgba(255,255,255,0.06)", background: "#0d1117",
               color: "#4a5568", fontStyle: "italic" },

  thBase:    { padding: "5px 10px", textAlign: "left", fontWeight: 600, fontSize: 11,
               whiteSpace: "nowrap", borderBottom: "1px solid rgba(255,255,255,0.10)",
               borderRight: "1px solid rgba(255,255,255,0.06)", background: "#161b22",
               color: "#8b9dc3", position: "sticky", top: 0, zIndex: 2 },
  thGroup:   { padding: "5px 10px", textAlign: "center", fontWeight: 700, fontSize: 12,
               whiteSpace: "nowrap", borderBottom: "1px solid rgba(255,255,255,0.10)",
               borderRight: "2px solid rgba(31,168,201,0.25)", background: "#0d1a26",
               color: "#1FA8C9", position: "sticky", top: 0, zIndex: 2 },
  thSub:     { padding: "4px 8px", textAlign: "center", fontWeight: 600, fontSize: 11,
               whiteSpace: "nowrap", borderBottom: "1px solid rgba(255,255,255,0.10)",
               borderRight: "1px solid rgba(255,255,255,0.06)", background: "#12171f",
               color: "#5a9fbf", position: "sticky", zIndex: 2 },
  thDim:     { padding: "4px 8px", textAlign: "left", fontWeight: 600, fontSize: 11,
               color: "#6b7fa8", background: "#161b22",
               borderBottom: "1px solid rgba(255,255,255,0.08)",
               borderRight: "1px solid rgba(255,255,255,0.06)",
               position: "sticky", top: 0, zIndex: 3 },
  td:        { padding: "4px 10px", borderBottom: "1px solid rgba(255,255,255,0.05)",
               borderRight: "1px solid rgba(255,255,255,0.04)", color: "#c9d1d9",
               whiteSpace: "nowrap" },
  tdNum:     { padding: "4px 10px", textAlign: "right",
               borderBottom: "1px solid rgba(255,255,255,0.05)",
               borderRight: "1px solid rgba(255,255,255,0.04)",
               fontVariantNumeric: "tabular-nums" },
  tdEmpty:   { padding: "4px 10px", textAlign: "right",
               borderBottom: "1px solid rgba(255,255,255,0.05)",
               borderRight: "1px solid rgba(255,255,255,0.04)" },
  tdRowDim:  { padding: "4px 10px", borderBottom: "1px solid rgba(255,255,255,0.05)",
               borderRight: "1px solid rgba(255,255,255,0.08)", color: "#e6edf3",
               fontWeight: 500, whiteSpace: "nowrap", background: "#0d1117" },
};

// ── PIVOT TABLE ───────────────────────────────────────────────────
function ProperPivotTable({
  data, height, groupbyRows, groupbyColumns, metricKeys,
  conditionalFormatting, columnOrder, showCellBars, onRowClick,
}) {
  const [page, setPage]       = useState(0);
  const [search, setSearch]   = useState("");
  const [hoveredRow, setHoveredRow] = useState(null);
  const rules = conditionalFormatting || [];

  const pivot = useMemo(
    () => buildPivot(data, groupbyRows, groupbyColumns, metricKeys, columnOrder),
    [data, groupbyRows, groupbyColumns, metricKeys, columnOrder]
  );

  // ALL hooks must be called before any early return
  const topGroups = useMemo(() => {
    if (!pivot || pivot.colDims.length < 2) return null;
    const seen = new Map();
    for (const combo of pivot.colCombos) {
      const top = combo[0];
      seen.set(top, (seen.get(top) || 0) + pivot.metrics.length);
    }
    return [...seen.entries()];
  }, [pivot]);

  // Per-metric value arrays for cell bar magnitude colouring
  // Must be before early return to satisfy hooks rules
  const metricColValues = useMemo(() => {
    if (!pivot || !showCellBars) return {};
    const map = {};
    for (const mk of pivot.metrics) {
      map[mk] = [];
      for (const entry of pivot.rowMap.values()) {
        for (const combo of pivot.colCombos) {
          const cellKey = combo.join("||") + "||" + mk;
          const v = entry.metricMap[cellKey];
          if (v !== null && v !== undefined && !isNaN(Number(v))) map[mk].push(Number(v));
        }
      }
    }
    return map;
  }, [pivot, showCellBars]);

  // Now safe to return early — all hooks have been called above
  if (!pivot) return null;

  const allRows = [...pivot.rowMap.values()];

  // Filter rows by search term (matches any row dim value)
  const filteredRows = search.trim()
    ? allRows.filter(entry =>
        entry.dimValues.some(v => String(v).toLowerCase().includes(search.toLowerCase()))
      )
    : allRows;

  const total    = filteredRows.length;
  const pageRows = filteredRows.slice(page * ROWS_PER_PAGE, (page + 1) * ROWS_PER_PAGE);

  const rowHeight = 28;
  const LABEL_ROWS = pivot.colDims.length;

  // ── Pivot export handler ─────────────────────────────────────────
  const handlePivotExport = () => {
    const headers = [
      ...pivot.rowDims,
      ...pivot.colCombos.flatMap(combo =>
        pivot.metrics.map(mk =>
          pivot.metrics.length > 1
            ? combo.join(" | ") + " | " + mk
            : combo.join(" | ")
        )
      ),
    ];
    const rows2d = filteredRows.map(entry => [
      ...entry.dimValues,
      ...pivot.colCombos.flatMap(combo =>
        pivot.metrics.map(mk => {
          const cellKey = combo.join("||") + "||" + mk;
          const v = entry.metricMap[cellKey];
          return exportCellValue(v, mk);
        })
      ),
    ]);
    exportToExcel("pivot_table.xlsx", headers, rows2d);
  };

  return (
    <div style={{ display: "flex", flexDirection: "column", height: height || "100%", overflow: "hidden" }}>
      {/* Toolbar: search left, export right */}
      <div style={{ display: "flex", alignItems: "center", gap: 8,
                    padding: "6px 8px", borderBottom: "1px solid rgba(255,255,255,0.05)",
                    background: "#0d1117", flexShrink: 0 }}>
        <SearchBar value={search} onChange={v => { setSearch(v); setPage(0); }}
                   placeholder="Search rows..." />
        {search.trim() && (
          <span style={{ fontSize: 10, color: "#4a5568", whiteSpace: "nowrap" }}>
            {total} result{total !== 1 ? "s" : ""}
          </span>
        )}
        <div style={{ flex: 1 }} />
        <ExportBtn onClick={handlePivotExport} />
      </div>
      <div style={{ ...S.wrapper, flex: 1 }}>
        <table style={S.table}>
          <thead>

            {/* ── FIX 2: Row 0 — "Metric" label row ───────────────────────
                Matches Superset's top header row showing metric name label
                Left side: empty dim cells  |  Right: metric name spanning all cols */}
            <tr>
              {/* Empty cell spanning all row-dim columns */}
              <td
                colSpan={pivot.rowDims.length}
                style={{ ...S.thLabelDim, position: "sticky", top: 0, zIndex: 3 }}
              >
                Metric
              </td>
              {/* Metric name spanning all value columns */}
              <td
                colSpan={pivot.colCombos.length * pivot.metrics.length}
                style={{ ...S.thLabel, position: "sticky", top: 0, zIndex: 2 }}
              >
                {pivot.metrics.join(", ")}
              </td>
            </tr>

            {/* ── FIX 2: Row 1 — centername groups ────────────────────────
                Shows centername values spanning their quarter columns,
                plus the row-dim label (e.g. "tags") on the left */}
            {pivot.colDims.length >= 2 && topGroups && (
              <tr>
                {pivot.rowDims.map((dim, i) => (
                  <th
                    key={`rh-${i}`}
                    style={{ ...S.thDim, top: `${rowHeight}px` }}
                    rowSpan={LABEL_ROWS}  // spans through all sub-dim rows
                  >
                    {dim}
                  </th>
                ))}
                {topGroups.map(([val, span], gi) => (
                  <th
                    key={val}
                    colSpan={span}
                    style={{
                      ...S.thGroup,
                      top: `${rowHeight}px`,
                      borderLeft: gi === 0 ? "2px solid rgba(31,168,201,0.3)" : undefined,
                    }}
                  >
                    {val}
                  </th>
                ))}
              </tr>
            )}

            {/* ── FIX 2: Row 2..N — quarter_label sub-headers ─────────────
                Shows the sub-dim values (quarters) under each centername */}
            {pivot.colDims.length >= 2 &&
              Array.from({ length: pivot.colDims.length - 1 }, (_, dimIdx) => (
                <tr key={`sub-${dimIdx}`}>
                  {pivot.colCombos.flatMap((combo) =>
                    pivot.metrics.map((mk) => (
                      <th
                        key={combo.join("||") + mk}
                        style={{
                          ...S.thSub,
                          top: `${(dimIdx + 2) * rowHeight}px`, // +2 because row 0 is Metric label
                        }}
                      >
                        {combo[dimIdx + 1]}
                        {pivot.metrics.length > 1 && (
                          <div style={{ fontSize: 9, color: "#4a8fa8", fontWeight: 400 }}>{mk}</div>
                        )}
                      </th>
                    ))
                  )}
                </tr>
              ))}

            {/* ── Single-level (no centername grouping) ────────────────── */}
            {pivot.colDims.length === 1 && (
              <tr>
                {pivot.rowDims.map((dim, i) => (
                  <th key={`rh-${i}`} style={S.thBase}>{dim}</th>
                ))}
                {pivot.colCombos.flatMap((combo) =>
                  pivot.metrics.map((mk) => (
                    <th key={combo.join("||") + mk} style={{ ...S.thBase, textAlign: "center" }}>
                      {combo[0]}
                      {pivot.metrics.length > 1 && (
                        <div style={{ fontSize: 9, color: "#5a9fbf" }}>{mk}</div>
                      )}
                    </th>
                  ))
                )}
              </tr>
            )}

          </thead>

          <tbody>
            {pageRows.map((entry, ri) => (
              <tr
                key={ri}
                onClick={() => {
                  if (!onRowClick) return;
                  const col = pivot.rowDims[0];
                  const val = entry.dimValues[0];
                  if (col && val) onRowClick(col, val);
                }}
                onMouseEnter={() => setHoveredRow(ri)}
                onMouseLeave={() => setHoveredRow(null)}
                style={{
                  background: hoveredRow === ri
                    ? "rgba(31,168,201,0.08)"
                    : ri % 2 === 0 ? "#0d1117" : "#111820",
                  cursor: onRowClick ? "pointer" : "default",
                  transition: "background .1s",
                }}
              >
                {entry.dimValues.map((val, di) => (
                  <td key={`d-${di}`} style={S.tdRowDim}>{val}</td>
                ))}
                {pivot.colCombos.flatMap((combo) =>
                  pivot.metrics.map((mk) => {
                    const cellKey = combo.join("||") + "||" + mk;
                    const raw = entry.metricMap[cellKey];
                    const hasValue = raw !== null && raw !== undefined && raw !== "";
                    if (!hasValue) return <td key={cellKey} style={S.tdEmpty} />;

                    // Colour priority: conditional rule → cell bar → default
                    const cfColor  = evalConditionalColor(raw, mk, rules);
                    const barColor = (!cfColor && showCellBars)
                      ? cellBarColor(raw, metricColValues[mk] || []) : null;
                    const bgColor  = cfColor || barColor;
                    const cellStyle = bgColor
                      ? { ...S.tdNum, background: bgColor, color: contrastColor(bgColor), fontWeight: cfColor ? 600 : 400 }
                      : { ...S.tdNum, color: "#1FA8C9" };

                    return (
                      <td key={cellKey} style={cellStyle}>
                        {fmtTableNum(raw, mk)}
                      </td>
                    );
                  })
                )}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <PageTabs totalRows={total} page={page} setPage={setPage} />
    </div>
  );
}

// ── FLAT TABLE ────────────────────────────────────────────────────
function FlatTable({ data, height, metricKeys, columnOrder, colnames, conditionalFormatting, showCellBars, onRowClick }) {
  const [page,   setPage]   = useState(0);
  const [search, setSearch] = useState("");
  const [hoveredRow, setHoveredRow] = useState(null);
  const rules   = conditionalFormatting || [];
  const allRows = data || [];

  // Column order priority:
  // 1. columnOrder from backend chart meta (column_config)
  // 2. colnames from API data response (res.data.colnames) -- Superset live order
  // 3. Object.keys(rows[0]) -- last resort
  // Matching is done both exactly AND on a normalized (trim + lowercase) key so
  // minor casing/whitespace mismatches between the backend list and the actual
  // data keys don't cause a column to drop out of order silently.
  const columns = useMemo(() => {
    if (!allRows.length) return [];
    const dataKeys = Object.keys(allRows[0]).filter(k => k !== "__summary__");
    const preferred = columnOrder?.length ? columnOrder
                    : colnames?.length    ? colnames
                    : [];
    if (!preferred.length) return dataKeys;

    const dataKeyByNorm = new Map(dataKeys.map(k => [normKey(k), k]));
    const ordered = [];
    const used = new Set();
    for (const p of preferred) {
      let match = dataKeys.includes(p) ? p : dataKeyByNorm.get(normKey(p));
      if (match && !used.has(match)) { ordered.push(match); used.add(match); }
    }
    const rest = dataKeys.filter((c) => !used.has(c));
    return [...ordered, ...rest];
  }, [allRows, columnOrder, colnames]);

  const metricSet = useMemo(() => new Set(metricKeys || []), [metricKeys]);

  const numericCols = useMemo(() => {
    const s = new Set(metricSet);
    if (!s.size) {
      for (const col of columns) {
        // Never auto-detect mobile/phone/contact/ID/pincode-type columns as numeric,
        // even if every sampled value happens to parse as a number.
        if (ID_COL_PATTERN.test(col)) continue;
        const sample = allRows.slice(0, 20).map((r) => r[col]).filter((v) => v != null);
        if (sample.length && sample.every((v) => !isNaN(Number(v)))) s.add(col);
      }
    }
    return s;
  }, [columns, allRows, metricSet]);

  // Per-column value arrays for cell bar magnitude colouring
  const colBarValues = useMemo(() => {
    if (!showCellBars) return {};
    const map = {};
    for (const col of columns) {
      if (numericCols.has(col)) {
        map[col] = allRows.map(r => Number(r[col])).filter(v => !isNaN(v));
      }
    }
    return map;
  }, [allRows, columns, numericCols, showCellBars]);

  // Filter rows by search term — checks all column values
  const filteredRows = search.trim()
    ? allRows.filter(row =>
        columns.some(col => String(row[col] ?? "").toLowerCase().includes(search.toLowerCase()))
      )
    : allRows;

  const total    = filteredRows.length;
  const pageRows = filteredRows.slice(page * ROWS_PER_PAGE, (page + 1) * ROWS_PER_PAGE);

  if (!allRows.length) return <div style={{ color: "#8b8fa8", padding: 16 }}>No data</div>;

  const handleFlatExport = () => {
    const rows2d = filteredRows.map(row => columns.map(col => exportCellValue(row[col], col)));
    exportToExcel("table_data.xlsx", columns, rows2d);
  };

  return (
    <div style={{ display: "flex", flexDirection: "column", height: height || "100%", overflow: "hidden" }}>
      {/* Toolbar: search left, export right */}
      <div style={{ display: "flex", alignItems: "center", gap: 8,
                    padding: "6px 8px", borderBottom: "1px solid rgba(255,255,255,0.05)",
                    background: "#0d1117", flexShrink: 0 }}>
        <SearchBar value={search} onChange={v => { setSearch(v); setPage(0); }}
                   placeholder="Search table..." />
        {search.trim() && (
          <span style={{ fontSize: 10, color: "#4a5568", whiteSpace: "nowrap" }}>
            {total} result{total !== 1 ? "s" : ""}
          </span>
        )}
        <div style={{ flex: 1 }} />
        <ExportBtn onClick={handleFlatExport} />
      </div>
      <div style={{ ...S.wrapper, flex: 1 }}>
        <table style={S.table}>
          <thead>
            <tr>
              {columns.map((col) => (
                <th key={col} style={S.thBase}>{col}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {pageRows.map((row, ri) => {
              const isSummary = row.__summary__;
              return (
              <tr
                key={ri}
                onClick={() => {
                  if (isSummary || !onRowClick) return;
                  const dimCol = columns.find(c => !numericCols.has(c));
                  if (dimCol && row[dimCol]) onRowClick(dimCol, row[dimCol]);
                }}
                onMouseEnter={() => !isSummary && setHoveredRow(ri)}
                onMouseLeave={() => setHoveredRow(null)}
                style={{
                  background: isSummary
                    ? "rgba(31,168,201,0.12)"
                    : hoveredRow === ri
                    ? "rgba(31,168,201,0.08)"
                    : ri % 2 === 0 ? "#0d1117" : "#111820",
                  cursor: (!isSummary && onRowClick) ? "pointer" : "default",
                  transition: "background .1s",
                  fontWeight: isSummary ? 700 : 400,
                  borderTop: isSummary ? "2px solid rgba(31,168,201,0.3)" : undefined,
                }}
              >
                {columns.map((col) => {
                  if (col === "__summary__") return null;
                  const val   = row[col];
                  const isNum = numericCols.has(col);
                  if (isSummary) {
                    return (
                      <td key={col} style={{
                        ...( isNum ? S.tdNum : S.td ),
                        color: "#1FA8C9", fontWeight: 700,
                        borderTop: "2px solid rgba(31,168,201,0.3)",
                      }}>
                        {val !== undefined ? fmtTableNum(val, col) : ""}
                      </td>
                    );
                  }
                  const isNum2 = numericCols.has(col);
                  if (isNum2) {
                    const cfColor  = evalConditionalColor(val, col, rules);
                    const barColor = (!cfColor && showCellBars)
                      ? cellBarColor(val, colBarValues[col] || []) : null;
                    const bgColor  = cfColor || barColor;
                    const cellStyle = bgColor
                      ? { ...S.tdNum, background: bgColor, color: contrastColor(bgColor), fontWeight: cfColor ? 600 : 400 }
                      : { ...S.tdNum, color: "#1FA8C9" };
                    return <td key={col} style={cellStyle}>{fmtTableNum(val, col)}</td>;
                  }
                  return <td key={col} style={S.td}>{val ?? ""}</td>;
                })}
              </tr>
              );
            })}
          </tbody>
        </table>
      </div>
      <PageTabs totalRows={total} page={page} setPage={setPage} />
    </div>
  );
}

// ── Main export ───────────────────────────────────────────────────
export default function PivotTable({
  data,
  height,
  groupbyRows,
  groupbyColumns,
  metricKeys,
  columnOrder,
  colnames,
  conditionalFormatting,
  showCellBars,
  onRowClick,
}) {
  const isPivot =
    groupbyColumns?.length > 0 && groupbyRows?.length > 0 && metricKeys?.length > 0;

  if (isPivot) {
    const pivot = buildPivot(data, groupbyRows, groupbyColumns, metricKeys, columnOrder);
    if (pivot) {
      return (
        <ProperPivotTable
          data={data}
          height={height}
          groupbyRows={groupbyRows}
          groupbyColumns={groupbyColumns}
          metricKeys={metricKeys}
          columnOrder={columnOrder}
          conditionalFormatting={conditionalFormatting}
          showCellBars={showCellBars}
          onRowClick={onRowClick}
        />
      );
    }
  }

  return (
    <FlatTable
      data={data}
      height={height}
      metricKeys={metricKeys}
      columnOrder={columnOrder}
      colnames={colnames}
      conditionalFormatting={conditionalFormatting}
      showCellBars={showCellBars}
      onRowClick={onRowClick}
    />
  );
}
