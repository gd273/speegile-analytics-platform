// import React, { useState, useEffect, useRef, useMemo } from "react";

// // ─────────────────────────────────────────────────────────────
// //  Formatters (mirrors ChartCard)
// // ─────────────────────────────────────────────────────────────
// const isTimestampMs = (v) => {
//   const n = Number(v);
//   if (!Number.isFinite(n) || n < 0) return false;
//   if (n < 9.46e11 || n > 2.52e12) return false;
//   try { const yr = new Date(n).getFullYear(); return yr >= 2000 && yr <= 2050; }
//   catch { return false; }
// };
// const fmtDateMs = (ms) => {
//   try {
//     return new Date(Number(ms)).toLocaleDateString("en-IN", {
//       day: "2-digit", month: "short", year: "numeric",
//     });
//   } catch { return String(ms); }
// };
// const si3 = (n, div, sfx) => {
//   const x = n / div, abs = Math.abs(x);
//   const s = abs >= 100 ? x.toFixed(0) : abs >= 10 ? x.toFixed(1) : x.toFixed(2);
//   return s.replace(/\.?0+$/, "") + sfx;
// };

// const ID_COL_PATTERN = /pincode|zip|postal|pin_code|pin|order_id|invoice|phone|mobile|contact|tel|fax|#|(_id|id)$/i;

// const fmtNum = (v, colName = "") => {
//   const n = Number(v);
//   if (isNaN(n)) return String(v ?? "");
//   if (isTimestampMs(n)) return fmtDateMs(n);
//   if (colName && ID_COL_PATTERN.test(colName)) {
//     return Number.isInteger(n) ? String(n) : n.toFixed(2);
//   }
//   const abs = Math.abs(n);
//   if (abs === 0) return "0";
//   if (abs >= 1e9) return si3(n, 1e9, "B");
//   if (abs >= 1e6) return si3(n, 1e6, "M");
//   if (abs >= 1e3) return si3(n, 1e3, "k");
//   return parseFloat(n.toFixed(2)).toString();
// };

// const fmtCell = (v, colName = "") => {
//   if (v === null || v === undefined) return "—";
//   const n = Number(v);
//   if (!isNaN(n) && v !== "") return fmtTableNum(v, colName);
//   const s = String(v);
//   if (s.match(/^\d{4}-\d{2}-\d{2}/) || s.includes("T00:00:00")) {
//     try {
//       const d = new Date(v);
//       if (!isNaN(d.getTime()))
//         return d.toLocaleDateString("en-IN", { month: "short", year: "2-digit" });
//     } catch { /**/ }
//   }
//   return s;
// };

// const isNumericKey = (rows, key) =>
//   rows.some(r => r[key] !== null && r[key] !== undefined && !isNaN(Number(r[key])) && !isTimestampMs(Number(r[key])));

// // ── Table number formatter — full value, no K/M abbreviation ──
// const CURRENCY_COL_PATTERN = /amount|revenue|cost|price|mrp|earning|income|profit|loss|(^|\s|_)(net|value|sell)(\s|_|$)/i;
// const QTY_COL_PATTERN      = /qty|quantity|count|units|pieces|pcs|no\.|nos|phone|mobile|contact|whatsapp|tel|fax|#/i;

// function isCurrencyCol(colName) {
//   if (!colName) return false;
//   if (QTY_COL_PATTERN.test(colName)) return false;
//   return CURRENCY_COL_PATTERN.test(colName);
// }

// function fmtTableNum(val, colName = "") {
//   if (val === null || val === undefined || val === "") return "—";
//   const n = Number(val);
//   if (isNaN(n)) return String(val);
//   if (isTimestampMs(n)) return fmtDateMs(n);

//   // ID / phone columns — show raw, no formatting
//   if (colName && ID_COL_PATTERN.test(colName)) {
//     return Number.isInteger(n) ? String(n) : n.toFixed(2);
//   }

//   // Format with Indian locale commas: 89,52,612
//   const formatted = new Intl.NumberFormat("en-IN", {
//     maximumFractionDigits: 2,
//     minimumFractionDigits: 0,
//   }).format(n);

//   // Add ₹ for currency columns only
//   if (isCurrencyCol(colName)) {
//     return `₹${formatted}`;
//   }

//   return formatted;
// }

// // ─────────────────────────────────────────────────────────────
// //  useContainerWidth
// // ─────────────────────────────────────────────────────────────
// function useContainerWidth(ref) {
//   const [width, setWidth] = useState(0);
//   useEffect(() => {
//     if (!ref.current) return;
//     const ro = new ResizeObserver(([entry]) => {
//       setWidth(entry.contentRect.width);
//     });
//     ro.observe(ref.current);
//     setWidth(ref.current.offsetWidth);
//     return () => ro.disconnect();
//   }, [ref]);
//   return width;
// }

// // ─────────────────────────────────────────────────────────────
// //  Sort state hook
// // ─────────────────────────────────────────────────────────────
// function useSort(rows) {
//   const [sortKey, setSortKey] = useState(null);
//   const [sortDir, setSortDir] = useState("asc");

//   const toggle = (key) => {
//     if (sortKey === key) setSortDir(d => d === "asc" ? "desc" : "asc");
//     else { setSortKey(key); setSortDir("asc"); }
//   };

//   const sorted = useMemo(() => {
//     if (!sortKey) return rows;
//     return [...rows].sort((a, b) => {
//       const av = a[sortKey], bv = b[sortKey];
//       const an = Number(av), bn = Number(bv);
//       const numericCmp = !isNaN(an) && !isNaN(bn) ? an - bn : String(av ?? "").localeCompare(String(bv ?? ""));
//       return sortDir === "asc" ? numericCmp : -numericCmp;
//     });
//   }, [rows, sortKey, sortDir]);

//   return { sorted, sortKey, sortDir, toggle };
// }

// // ─────────────────────────────────────────────────────────────
// //  Column derivation
// // ─────────────────────────────────────────────────────────────
// function deriveColumns(data, groupbyRows, groupbyColumns, metricKeys, colnames) {
//   if (!data?.length) return { dimCols: [], metCols: [] };

//   const allKeys = colnames?.length
//     ? colnames
//     : Object.keys(data[0]);

//   const normalise = (arr) =>
//     (arr || []).map(c =>
//       typeof c === "string" ? c : c?.column_name || c?.column?.column_name || null
//     ).filter(Boolean);

//   const rowDims = normalise(groupbyRows);
//   const colDims = normalise(groupbyColumns);
//   const dimCols = [...new Set([...rowDims, ...colDims])].filter(k => allKeys.includes(k));
//   const metCols = (metricKeys || []).filter(k => allKeys.includes(k));

//   if (dimCols.length || metCols.length) {
//     const idDimCols = allKeys.filter(k =>
//       !dimCols.includes(k) &&
//       !metCols.includes(k) &&
//       ID_COL_PATTERN.test(k)
//     );

//     const remaining = allKeys.filter(k =>
//       !dimCols.includes(k) &&
//       !metCols.includes(k) &&
//       isNumericKey(data, k) &&
//       !ID_COL_PATTERN.test(k)
//     );

//     return {
//       dimCols: [...dimCols, ...idDimCols],
//       metCols: metCols.length ? metCols : remaining,
//     };
//   }

//   const ID_DIM_PATTERN = /pincode|zip|postal|pin_code|pin|order_id|invoice|phone|mobile|(_id|id)$/i;
//   const autoMet = allKeys.filter(k => isNumericKey(data, k) && !ID_DIM_PATTERN.test(k));
//   const autoDim = allKeys.filter(k => !autoMet.includes(k));
//   return { dimCols: autoDim, metCols: autoMet };
// }

// // ─────────────────────────────────────────────────────────────
// //  Styles
// // ─────────────────────────────────────────────────────────────
// const S = {
//   wrapper: {
//     width: "100%",
//     boxSizing: "border-box",
//     overflowX: "auto",
//     overflowY: "auto",
//     WebkitOverflowScrolling: "touch",
//     scrollbarWidth: "thin",
//     scrollbarColor: "#2d3748 transparent",
//   },
//   table: {
//     width: "100%",
//     borderCollapse: "collapse",
//     tableLayout: "auto",
//     minWidth: 0,
//   },
//   th: (isNum, sorted) => ({
//     padding: "8px 12px",
//     fontSize: 11,
//     fontWeight: 600,
//     textAlign: isNum ? "right" : "left",
//     color: sorted ? "#1FA8C9" : "#64748b",
//     background: "#191c24",
//     borderBottom: "1px solid rgba(255,255,255,0.07)",
//     whiteSpace: "nowrap",
//     cursor: "pointer",
//     userSelect: "none",
//     position: "sticky",
//     top: 0,
//     zIndex: 2,
//     letterSpacing: "0.04em",
//   }),
//   td: (isNum, isEven) => ({
//     padding: "7px 12px",
//     fontSize: 12,
//     textAlign: isNum ? "right" : "left",
//     color: isNum ? "#e2e8f0" : "#94a3b8",
//     fontWeight: isNum ? 500 : 400,
//     borderBottom: "1px solid rgba(255,255,255,0.04)",
//     background: isEven ? "rgba(255,255,255,0.015)" : "transparent",
//     whiteSpace: "nowrap",
//     maxWidth: 200,
//     overflow: "hidden",
//     textOverflow: "ellipsis",
//   }),
//   sortArrow: (dir, active) => ({
//     marginLeft: 4,
//     opacity: active ? 1 : 0.25,
//     fontSize: 9,
//     color: "#1FA8C9",
//   }),
//   card: (isEven) => ({
//     background: isEven ? "#1a1d26" : "#191c24",
//     border: "1px solid rgba(255,255,255,0.06)",
//     borderRadius: 8,
//     padding: "10px 12px",
//     marginBottom: 8,
//     width: "100%",
//     boxSizing: "border-box",
//   }),
//   cardRow: {
//     display: "flex",
//     justifyContent: "space-between",
//     alignItems: "baseline",
//     padding: "3px 0",
//     borderBottom: "1px solid rgba(255,255,255,0.04)",
//     gap: 8,
//   },
//   cardLabel: {
//     fontSize: 11,
//     color: "#64748b",
//     fontWeight: 500,
//     flexShrink: 0,
//     maxWidth: "55%",
//     overflow: "hidden",
//     textOverflow: "ellipsis",
//     whiteSpace: "nowrap",
//   },
//   cardValue: (isNum) => ({
//     fontSize: 12,
//     color: isNum ? "#e2e8f0" : "#94a3b8",
//     fontWeight: isNum ? 600 : 400,
//     textAlign: "right",
//     wordBreak: "break-word",
//   }),
//   empty: {
//     display: "flex",
//     flexDirection: "column",
//     alignItems: "center",
//     justifyContent: "center",
//     gap: 8,
//     color: "#374151",
//   },
//   searchWrap: {
//     padding: "0 0 10px",
//     display: "flex",
//     alignItems: "center",
//     gap: 6,
//   },
//   searchInput: {
//     flex: 1,
//     background: "#12151f",
//     border: "1px solid rgba(255,255,255,0.08)",
//     borderRadius: 6,
//     padding: "5px 10px",
//     color: "#e2e8f0",
//     fontSize: 11,
//     outline: "none",
//     minWidth: 0,
//   },
// };

// // ─────────────────────────────────────────────────────────────
// //  PivotTable
// // ─────────────────────────────────────────────────────────────
// export default function PivotTable({
//   data           = [],
//   height         = 320,
//   groupbyRows    = [],
//   groupbyColumns = [],
//   metricKeys     = [],
//   colnames       = [],
//   onRowClick,
//   crossFilterValue,
//   title          = "export",   // ← ADD
// }) {
//   const containerRef        = useRef(null);
//   const containerWidth      = useContainerWidth(containerRef);
//   const [search, setSearch] = useState("");

//   useEffect(() => {
//     setSearch("");
//   }, [data]);

//   const useCardView = false;

//   const { dimCols, metCols } = useMemo(
//     () => deriveColumns(data, groupbyRows, groupbyColumns, metricKeys, colnames),
//     [data, groupbyRows, groupbyColumns, metricKeys, colnames]
//   );

//   const allCols = useMemo(() => {
//     const allDataKeys = colnames?.length
//       ? colnames
//       : (data.length ? Object.keys(data[0]) : []);
//     if (allDataKeys.length) return allDataKeys;
//     const combined = [...dimCols, ...metCols];
//     return combined.length ? combined : [];
//   }, [dimCols, metCols, data, colnames]);

//   const filteredData = useMemo(() => {
//     if (!search.trim()) return data;
//     const q = search.toLowerCase();
//     return data.filter(row =>
//       allCols.some(k => String(row[k] ?? "").toLowerCase().includes(q))
//     );
//   }, [data, allCols, search]);

//   const { sorted, sortKey, sortDir, toggle } = useSort(filteredData);

//   // ── Row click handler ─────────────────────────────────────────
//   const handleRowClick = (row) => {
//     if (!onRowClick) return;
//     const dimKey = dimCols[0];
//     if (!dimKey) return;

//     const val = row[dimKey];
//     if (val == null || val === "") return;

//     const isDateCol = /^date$|time|timestamp/i.test(dimKey) || isTimestampMs(Number(val));
//     if (isDateCol) return;

//     const isSameValue = String(val) === String(crossFilterValue);
//     onRowClick(dimKey, isSameValue ? null : String(val));
//   };

//   // ── Export to Excel ───────────────────────────────────────────
//   const exportToExcel = () => {
//     // Use sorted+filtered data so what user sees is what gets exported
//     const rows = sorted;
//     if (!rows.length) return;

//     // Build CSV content with BOM for Excel to detect UTF-8 (₹ symbol support)
//     const BOM = "\uFEFF";

//     // Header row
//     const header = allCols.map(k => `"${String(k).replace(/"/g, '""')}"`).join(",");

//     // Data rows — export raw values (no ₹/commas) so Excel can treat as numbers
//     const body = rows.map(row =>
//           allCols.map(k => {
//             const v = row[k];
//             if (v === null || v === undefined) return "";

//             const n = Number(v);

//             // ── Timestamp → format as readable date string ──
//             if (!isNaN(n) && isTimestampMs(n)) {
//               try {
//                 const d = new Date(n);
//                 const dd = String(d.getDate()).padStart(2, "0");
//                 const mm = String(d.getMonth() + 1).padStart(2, "0");
//                 const yyyy = d.getFullYear();
//                 return `"${dd}-${mm}-${yyyy}"`;   // → "22-05-2026"
//               } catch { return `"${v}"`; }
//             }

//             // ── ID / phone columns → quoted string, no number formatting ──
//             if (!isNaN(n) && v !== "" && ID_COL_PATTERN.test(k)) {
//               return `"${String(v).replace(/"/g, '""')}"`;
//             }

//             // ── Regular numbers → plain number for Excel SUM/calculations ──
//             if (!isNaN(n) && v !== "") return n;

//             // ── Text values ──
//             return `"${String(v).replace(/"/g, '""')}"`;
//           }).join(",")
//         ).join("\n");

//     const csv     = BOM + header + "\n" + body;
//     const blob    = new Blob([csv], { type: "text/csv;charset=utf-8;" });
//     const url     = URL.createObjectURL(blob);
//     const link    = document.createElement("a");
//     const ts      = new Date().toISOString().slice(0, 10);
//     link.href     = url;
//     // link.download = `export_${ts}.csv`;
//     const safeName = title.replace(/[^a-z0-9]/gi, "_").toLowerCase();
//     link.download  = `${safeName}_${ts}.csv`;    
//     document.body.appendChild(link);
//     link.click();
//     document.body.removeChild(link);
//     URL.revokeObjectURL(url);
//   };

//   // ── Empty state ───────────────────────────────────────────────
//   if (!data.length) {
//     return (
//       <div style={{ ...S.empty, height }}>
//         <div style={{ fontSize: 28, opacity: 0.3 }}>◌</div>
//         <span style={{ fontSize: 12 }}>No data</span>
//       </div>
//     );
//   }

//   const colLabel = (k) => {
//     if (!k) return "";
//     return k.length > 28 ? k.slice(0, 26) + "…" : k;
//   };

//   // ── Card view ─────────────────────────────────────────────────
//   if (useCardView) {
//     return (
//       <div ref={containerRef} style={{ height, overflowY: "auto", WebkitOverflowScrolling: "touch", width: "100%", boxSizing: "border-box" }}>
//         <div style={S.searchWrap}>
//           <input
//             style={S.searchInput}
//             placeholder="Search…"
//             value={search}
//             onChange={e => setSearch(e.target.value)}
//           />
//         </div>
//         {sorted.map((row, ri) => (
//           <div key={ri} style={S.card(ri % 2 === 0)}>
//             {allCols.map((k, ci) => {
//               const isNum = metCols.includes(k) ||
//                 (isNumericKey(data, k) && !ID_COL_PATTERN.test(k) && !dimCols.includes(k));
//               return (
//                 <div key={k} style={{
//                   ...S.cardRow,
//                   borderBottom: ci < allCols.length - 1 ? S.cardRow.borderBottom : "none",
//                 }}>
//                   <span style={S.cardLabel}>{colLabel(k)}</span>
//                   <span style={S.cardValue(isNum)}>{fmtCell(row[k], k)}</span>
//                 </div>
//               );
//             })}
//           </div>
//         ))}
//         {sorted.length === 0 && (
//           <div style={{ ...S.empty, height: 80 }}>
//             <span style={{ fontSize: 12 }}>No results for "{search}"</span>
//           </div>
//         )}
//       </div>
//     );
//   }

//   // ── Table view ────────────────────────────────────────────────
//   const isCompact = containerWidth > 0 && containerWidth < 600;
//   const thStyle = (isNum, isSorted) => ({
//     ...S.th(isNum, isSorted),
//     padding: isCompact ? "6px 8px" : "8px 12px",
//     fontSize: isCompact ? 10 : 11,
//     textAlign: "center",
//   });
//   const tdStyle = (isNum, isEven) => ({
//     ...S.td(isNum, isEven),
//     padding: isCompact ? "5px 8px" : "7px 12px",
//     fontSize: isCompact ? 11 : 12,
//     textAlign: "center",
//   });

//   return (
//     <div ref={containerRef} style={{ width: "100%", boxSizing: "border-box", display: "flex", flexDirection: "column" }}>

//       {/* Search + Export */}
//       <div style={S.searchWrap}>
//         <input
//           style={S.searchInput}
//           placeholder="Search…"
//           value={search}
//           onChange={e => setSearch(e.target.value)}
//         />
//         {search && (
//           <span style={{ fontSize: 10, color: "#64748b", whiteSpace: "nowrap" }}>
//             {sorted.length} / {data.length}
//           </span>
//         )}
//         <button
//           onClick={exportToExcel}
//           title="Export to Excel"
//           style={{
//             display:     "flex",
//             alignItems:  "center",
//             gap:         5,
//             background:  "rgba(31,168,201,0.1)",
//             border:      "1px solid rgba(31,168,201,0.3)",
//             borderRadius: 6,
//             padding:     "4px 10px",
//             color:       "#1FA8C9",
//             fontSize:    11,
//             fontWeight:  600,
//             cursor:      "pointer",
//             whiteSpace:  "nowrap",
//             flexShrink:  0,
//             transition:  "background 0.15s",
//           }}
//           onMouseEnter={e => e.currentTarget.style.background = "rgba(31,168,201,0.2)"}
//           onMouseLeave={e => e.currentTarget.style.background = "rgba(31,168,201,0.1)"}
//         >
//           ⬇ Export
//         </button>
//       </div>

//       {/* Scrollable table */}
//       <div style={{ ...S.wrapper, height: height - 40 }}>
//         <table style={S.table}>

//           {/* ── Header ── */}
//           <thead>
//             <tr>
//               {allCols.map(k => {
//                 const isNum    = metCols.includes(k) || isNumericKey(data, k);
//                 const isSorted = sortKey === k;
//                 return (
//                   <th
//                     key={k}
//                     style={thStyle(isNum, isSorted)}
//                     onClick={() => toggle(k)}
//                     title={k}
//                   >
//                     {colLabel(k)}
//                     <span style={S.sortArrow(sortDir, isSorted)}>
//                       {isSorted ? (sortDir === "asc" ? " ▲" : " ▼") : " ↕"}
//                     </span>
//                   </th>
//                 );
//               })}
//             </tr>
//           </thead>

//           {/* ── Body ── */}
//           <tbody>
//             {sorted.length === 0 ? (
//               <tr>
//                 <td
//                   colSpan={allCols.length}
//                   style={{ textAlign: "center", padding: "20px", color: "#64748b", fontSize: 12 }}
//                 >
//                   No results for "{search}"
//                 </td>
//               </tr>
//             ) : (
//               sorted.map((row, ri) => {
//                 const isSelected =
//                   dimCols[0] != null &&
//                   String(row[dimCols[0]]) === String(crossFilterValue);

//                 return (
//                   <tr
//                     key={ri}
//                     onClick={() => handleRowClick(row)}
//                     style={{
//                       cursor:     onRowClick ? "pointer" : "default",
//                       background: isSelected ? "rgba(31,168,201,0.15)" : undefined,
//                       transition: "background 0.15s",
//                     }}
//                     onMouseEnter={e => {
//                       if (onRowClick && !isSelected)
//                         e.currentTarget.style.background = "rgba(255,255,255,0.05)";
//                     }}
//                     onMouseLeave={e => {
//                       e.currentTarget.style.background = isSelected
//                         ? "rgba(31,168,201,0.15)"
//                         : "";
//                     }}
//                   >
//                     {allCols.map((k, ki) => {
//                       const isNum = metCols.includes(k) ||
//                         (isNumericKey(data, k) && !ID_COL_PATTERN.test(k) && !dimCols.includes(k));
//                       return (
//                         <td
//                           key={k}
//                           style={{
//                             ...tdStyle(isNum, ri % 2 === 0),
//                             ...(ki === 0 && isSelected
//                               ? { borderLeft: "3px solid #1FA8C9", paddingLeft: 9 }
//                               : {}),
//                           }}
//                           title={String(row[k] ?? "")}
//                         >
//                           {fmtCell(row[k], k)}
//                         </td>
//                       );
//                     })}
//                   </tr>
//                 );
//               })
//             )}
//           </tbody>

//         </table>
//       </div>

//       {/* Row count footer */}
//       <div style={{ paddingTop: 6, fontSize: 10, color: "#374151", textAlign: "right" }}>
//         {sorted.length} row{sorted.length !== 1 ? "s" : ""}
//         {search ? ` (filtered from ${data.length})` : ""}
//       </div>

//     </div>
//   );
// }


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
const ID_COL_PATTERN = /\bid\b|_id$|^id_/i;

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

// ── Number formatter ─────────────────────────────────────────────
function isTimestampMs(n) {
  return Number.isInteger(n) && n > 1_000_000_000_000;
}
function fmtDateMs(ms) {
  return new Date(ms).toLocaleDateString("en-IN", {
    day: "2-digit", month: "short", year: "numeric",
  });
}
function fmtTableNum(val, colName = "") {
  if (val === null || val === undefined || val === "") return "";
  const n = Number(val);
  if (isNaN(n)) return String(val);
  if (isTimestampMs(n)) return fmtDateMs(n);
  if (colName && ID_COL_PATTERN.test(colName)) return String(val);
  const formatted = new Intl.NumberFormat("en-IN", {
    maximumFractionDigits: 2, minimumFractionDigits: 0,
  }).format(n);
  if (colName && CURRENCY_COL_PATTERN.test(colName)) return `₹${formatted}`;
  return formatted;
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

  // Step 2: sort top-level by columnOrder if provided, else alphabetically
  let sortedTopVals;
  if (columnOrder?.length) {
    const orderMap = new Map(columnOrder.map((v, i) => [v, i]));
    sortedTopVals = [...topDimVals].sort((a, b) => {
      const ia = orderMap.has(a) ? orderMap.get(a) : 9999;
      const ib = orderMap.has(b) ? orderMap.get(b) : 9999;
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

// ── Pagination bar ────────────────────────────────────────────────
function PageTabs({ totalRows, page, setPage }) {
  const pageCount = Math.ceil(totalRows / ROWS_PER_PAGE);
  if (pageCount <= 1) return null;
  return (
    <div style={{
      display: "flex", alignItems: "center", gap: 4, padding: "6px 8px",
      borderTop: "1px solid rgba(255,255,255,0.08)", background: "#0d1117", flexWrap: "wrap",
    }}>
      <span style={{ fontSize: 11, color: "#8b8fa8", marginRight: 4, whiteSpace: "nowrap" }}>
        {totalRows.toLocaleString("en-IN")} rows ·
      </span>
      {Array.from({ length: pageCount }, (_, i) => (
        <button key={i} onClick={() => setPage(i)} style={{
          padding: "2px 10px", borderRadius: 4, fontSize: 11, fontWeight: page === i ? 700 : 400,
          border: page === i ? "1px solid #1FA8C9" : "1px solid rgba(255,255,255,0.12)",
          background: page === i ? "rgba(31,168,201,0.18)" : "transparent",
          color: page === i ? "#1FA8C9" : "#8b8fa8", cursor: "pointer", transition: "all .12s",
        }}>
          {(i * ROWS_PER_PAGE + 1).toLocaleString("en-IN")}–
          {Math.min((i + 1) * ROWS_PER_PAGE, totalRows).toLocaleString("en-IN")}
        </button>
      ))}
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
  conditionalFormatting, columnOrder, showCellBars,
}) {
  const [page, setPage]       = useState(0);
  const [search, setSearch]   = useState("");
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
          return v !== null && v !== undefined ? v : "";
        })
      ),
    ]);
    exportToExcel("pivot_table.csv", headers, rows2d);
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
              <tr key={ri} style={{ background: ri % 2 === 0 ? "#0d1117" : "#111820" }}>
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
function FlatTable({ data, height, metricKeys, columnOrder, colnames, conditionalFormatting, showCellBars }) {
  const [page,   setPage]   = useState(0);
  const [search, setSearch] = useState("");
  const rules   = conditionalFormatting || [];
  const allRows = data || [];

  // Column order priority:
  // 1. columnOrder from backend chart meta (column_config)
  // 2. colnames from API data response (res.data.colnames) -- Superset live order
  // 3. Object.keys(rows[0]) -- last resort
  const columns = useMemo(() => {
    if (!allRows.length) return [];
    const dataKeys = Object.keys(allRows[0]);
    const preferred = columnOrder?.length ? columnOrder
                    : colnames?.length    ? colnames
                    : [];
    if (!preferred.length) return dataKeys;
    const ordered = preferred.filter((c) => dataKeys.includes(c));
    const rest    = dataKeys.filter((c) => !preferred.includes(c));
    return [...ordered, ...rest];
  }, [allRows, columnOrder, colnames]);

  const metricSet = useMemo(() => new Set(metricKeys || []), [metricKeys]);

  const numericCols = useMemo(() => {
    const s = new Set(metricSet);
    if (!s.size) {
      for (const col of columns) {
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
    const rows2d = filteredRows.map(row => columns.map(col => row[col] ?? ""));
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
            {pageRows.map((row, ri) => (
              <tr key={ri} style={{ background: ri % 2 === 0 ? "#0d1117" : "#111820" }}>
                {columns.map((col) => {
                  const val   = row[col];
                  const isNum = numericCols.has(col);
                  if (isNum) {
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
            ))}
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
    />
  );
}