import { useState, useRef, useEffect, useMemo } from "react";

// ─────────────────────────────────────────────────────────────
//  Formatters (mirrors ChartCard)
// ─────────────────────────────────────────────────────────────
const isTimestampMs = (v) => {
  const n = Number(v);
  if (!Number.isFinite(n) || n < 0) return false;
  if (n < 9.46e11 || n > 2.52e12) return false;
  try { const yr = new Date(n).getFullYear(); return yr >= 2000 && yr <= 2050; }
  catch { return false; }
};
const fmtDateMs = (ms) => {
  try {
    return new Date(Number(ms)).toLocaleDateString("en-IN", {
      day: "2-digit", month: "short", year: "numeric",
    });
  } catch { return String(ms); }
};
const si3 = (n, div, sfx) => {
  const x = n / div, abs = Math.abs(x);
  const s = abs >= 100 ? x.toFixed(0) : abs >= 10 ? x.toFixed(1) : x.toFixed(2);
  return s.replace(/\.?0+$/, "") + sfx;
};

const ID_COL_PATTERN = /pincode|zip|postal|pin_code|pin|order_id|invoice|phone|mobile|(_id|id)$/i;

const fmtNum = (v, colName = "") => {
  const n = Number(v);
  if (isNaN(n)) return String(v ?? "");
  if (isTimestampMs(n)) return fmtDateMs(n);
  if (colName && ID_COL_PATTERN.test(colName)) {
    return Number.isInteger(n) ? String(n) : n.toFixed(2);
  }
  const abs = Math.abs(n);
  if (abs === 0) return "0";
  if (abs >= 1e9) return si3(n, 1e9, "B");
  if (abs >= 1e6) return si3(n, 1e6, "M");
  if (abs >= 1e3) return si3(n, 1e3, "k");
  return parseFloat(n.toFixed(2)).toString();
};

const fmtCell = (v, colName = "") => {
  if (v === null || v === undefined) return "—";
  const n = Number(v);
  if (!isNaN(n) && v !== "") return fmtNum(v, colName);
  const s = String(v);
  if (s.match(/^\d{4}-\d{2}-\d{2}/) || s.includes("T00:00:00")) {
    try {
      const d = new Date(v);
      if (!isNaN(d.getTime()))
        return d.toLocaleDateString("en-IN", { month: "short", year: "2-digit" });
    } catch { /**/ }
  }
  return s;
};

const isNumericKey = (rows, key) =>
  rows.some(r => r[key] !== null && r[key] !== undefined && !isNaN(Number(r[key])) && !isTimestampMs(Number(r[key])));

// ─────────────────────────────────────────────────────────────
//  useContainerWidth
// ─────────────────────────────────────────────────────────────
function useContainerWidth(ref) {
  const [width, setWidth] = useState(0);
  useEffect(() => {
    if (!ref.current) return;
    const ro = new ResizeObserver(([entry]) => {
      setWidth(entry.contentRect.width);
    });
    ro.observe(ref.current);
    setWidth(ref.current.offsetWidth);
    return () => ro.disconnect();
  }, [ref]);
  return width;
}

// ─────────────────────────────────────────────────────────────
//  Sort state hook
// ─────────────────────────────────────────────────────────────
function useSort(rows) {
  const [sortKey, setSortKey] = useState(null);
  const [sortDir, setSortDir] = useState("asc");

  const toggle = (key) => {
    if (sortKey === key) setSortDir(d => d === "asc" ? "desc" : "asc");
    else { setSortKey(key); setSortDir("asc"); }
  };

  const sorted = useMemo(() => {
    if (!sortKey) return rows;
    return [...rows].sort((a, b) => {
      const av = a[sortKey], bv = b[sortKey];
      const an = Number(av), bn = Number(bv);
      const numericCmp = !isNaN(an) && !isNaN(bn) ? an - bn : String(av ?? "").localeCompare(String(bv ?? ""));
      return sortDir === "asc" ? numericCmp : -numericCmp;
    });
  }, [rows, sortKey, sortDir]);

  return { sorted, sortKey, sortDir, toggle };
}

// ─────────────────────────────────────────────────────────────
//  Column derivation
// ─────────────────────────────────────────────────────────────
function deriveColumns(data, groupbyRows, groupbyColumns, metricKeys, colnames) {
  if (!data?.length) return { dimCols: [], metCols: [] };

  const allKeys = colnames?.length
    ? colnames
    : Object.keys(data[0]);

  const normalise = (arr) =>
    (arr || []).map(c =>
      typeof c === "string" ? c : c?.column_name || c?.column?.column_name || null
    ).filter(Boolean);

  const rowDims = normalise(groupbyRows);
  const colDims = normalise(groupbyColumns);
  const dimCols = [...new Set([...rowDims, ...colDims])].filter(k => allKeys.includes(k));
  const metCols = (metricKeys || []).filter(k => allKeys.includes(k));

  // if (dimCols.length || metCols.length) {
  //   const remaining = allKeys.filter(k =>
  //     !dimCols.includes(k) && !metCols.includes(k) && isNumericKey(data, k)
  //   );
  //   return { dimCols, metCols: metCols.length ? metCols : remaining };
  // }
  if (dimCols.length || metCols.length) {
  // ── ID-type columns belong in dimCols, not remaining metrics ──
  const idDimCols = allKeys.filter(k =>
    !dimCols.includes(k) &&
    !metCols.includes(k) &&
    ID_COL_PATTERN.test(k)
  );

  const remaining = allKeys.filter(k =>
    !dimCols.includes(k) &&
    !metCols.includes(k) &&
    isNumericKey(data, k) &&
    !ID_COL_PATTERN.test(k)   // ← exclude ID cols from metrics
  );

  return {
    dimCols: [...dimCols, ...idDimCols],   // ← pincode goes here now
    metCols: metCols.length ? metCols : remaining,
  };
}

  // FIX — ID-type columns always go to autoDim even if numeric
const ID_DIM_PATTERN = /pincode|zip|postal|pin_code|pin|order_id|invoice|phone|mobile|(_id|id)$/i;
const autoMet = allKeys.filter(k => isNumericKey(data, k) && !ID_DIM_PATTERN.test(k));
const autoDim = allKeys.filter(k => !autoMet.includes(k));
  return { dimCols: autoDim, metCols: autoMet };
}

// ─────────────────────────────────────────────────────────────
//  Styles
// ─────────────────────────────────────────────────────────────
const S = {
  wrapper: {
    width: "100%",
    boxSizing: "border-box",
    overflowX: "auto",
    overflowY: "auto",
    WebkitOverflowScrolling: "touch",
    scrollbarWidth: "thin",
    scrollbarColor: "#2d3748 transparent",
  },
  table: {
    width: "100%",
    borderCollapse: "collapse",
    tableLayout: "auto",
    minWidth: 0,
  },
  th: (isNum, sorted) => ({
    padding: "8px 12px",
    fontSize: 11,
    fontWeight: 600,
    textAlign: isNum ? "right" : "left",
    color: sorted ? "#1FA8C9" : "#64748b",
    background: "#191c24",
    borderBottom: "1px solid rgba(255,255,255,0.07)",
    whiteSpace: "nowrap",
    cursor: "pointer",
    userSelect: "none",
    position: "sticky",
    top: 0,
    zIndex: 2,
    letterSpacing: "0.04em",
  }),
  td: (isNum, isEven) => ({
    padding: "7px 12px",
    fontSize: 12,
    textAlign: isNum ? "right" : "left",
    color: isNum ? "#e2e8f0" : "#94a3b8",
    fontWeight: isNum ? 500 : 400,
    borderBottom: "1px solid rgba(255,255,255,0.04)",
    background: isEven ? "rgba(255,255,255,0.015)" : "transparent",
    whiteSpace: "nowrap",
    maxWidth: 200,
    overflow: "hidden",
    textOverflow: "ellipsis",
  }),
  sortArrow: (dir, active) => ({
    marginLeft: 4,
    opacity: active ? 1 : 0.25,
    fontSize: 9,
    color: "#1FA8C9",
  }),
  card: (isEven) => ({
    background: isEven ? "#1a1d26" : "#191c24",
    border: "1px solid rgba(255,255,255,0.06)",
    borderRadius: 8,
    padding: "10px 12px",
    marginBottom: 8,
    width: "100%",
    boxSizing: "border-box",
  }),
  cardRow: {
    display: "flex",
    justifyContent: "space-between",
    alignItems: "baseline",
    padding: "3px 0",
    borderBottom: "1px solid rgba(255,255,255,0.04)",
    gap: 8,
  },
  cardLabel: {
    fontSize: 11,
    color: "#64748b",
    fontWeight: 500,
    flexShrink: 0,
    maxWidth: "55%",
    overflow: "hidden",
    textOverflow: "ellipsis",
    whiteSpace: "nowrap",
  },
  cardValue: (isNum) => ({
    fontSize: 12,
    color: isNum ? "#e2e8f0" : "#94a3b8",
    fontWeight: isNum ? 600 : 400,
    textAlign: "right",
    wordBreak: "break-word",
  }),
  empty: {
    display: "flex",
    flexDirection: "column",
    alignItems: "center",
    justifyContent: "center",
    gap: 8,
    color: "#374151",
  },
  searchWrap: {
    padding: "0 0 10px",
    display: "flex",
    alignItems: "center",
    gap: 6,
  },
  searchInput: {
    flex: 1,
    background: "#12151f",
    border: "1px solid rgba(255,255,255,0.08)",
    borderRadius: 6,
    padding: "5px 10px",
    color: "#e2e8f0",
    fontSize: 11,
    outline: "none",
    minWidth: 0,
  },
};

// ─────────────────────────────────────────────────────────────
//  PivotTable
// ─────────────────────────────────────────────────────────────
export default function PivotTable({
  data           = [],
  height         = 320,
  groupbyRows    = [],
  groupbyColumns = [],
  metricKeys     = [],
  colnames       = [],
  onRowClick,        // ← called with (colName, value) on row click
  crossFilterValue,  // ← currently active filter value — highlights that row
}) {
  const containerRef        = useRef(null);
  const containerWidth      = useContainerWidth(containerRef);
  const [search, setSearch] = useState("");

  useEffect(() => {
    setSearch("");
  }, [data]);

  const useCardView = false;

  const { dimCols, metCols } = useMemo(
    () => deriveColumns(data, groupbyRows, groupbyColumns, metricKeys, colnames),
    [data, groupbyRows, groupbyColumns, metricKeys, colnames]
  );

  // const allCols = useMemo(() => {
  //   const combined = [...dimCols, ...metCols];
  //   if (combined.length) return combined;
  //   return data.length ? Object.keys(data[0]) : [];
  // }, [dimCols, metCols, data]);

  const allCols = useMemo(() => {
  // Always use original data column order from colnames/data
  // dimCols + metCols are used only for styling, not for deciding which cols to show
  const allDataKeys = colnames?.length
    ? colnames
    : (data.length ? Object.keys(data[0]) : []);
  if (allDataKeys.length) return allDataKeys;
  const combined = [...dimCols, ...metCols];
  return combined.length ? combined : [];
}, [dimCols, metCols, data, colnames]);

  const filteredData = useMemo(() => {
    if (!search.trim()) return data;
    const q = search.toLowerCase();
    return data.filter(row =>
      allCols.some(k => String(row[k] ?? "").toLowerCase().includes(q))
    );
  }, [data, allCols, search]);

  const { sorted, sortKey, sortDir, toggle } = useSort(filteredData);

  // ── Row click handler ─────────────────────────────────────────
  const handleRowClick = (row) => {
  if (!onRowClick) return;
  const dimKey = dimCols[0];
  if (!dimKey) return;

  const val = row[dimKey];
  if (val == null || val === "") return;

  // ── Skip if dim column is a date/time column ──────────────────
  // Sending timestamp values as IN filters causes Superset 400 errors.
  // This prevents Order Details (dimCols[0]='date') from cross-filtering.
  const isDateCol = /^date$|time|timestamp/i.test(dimKey) || isTimestampMs(Number(val));
  if (isDateCol) return;

  const isSameValue = String(val) === String(crossFilterValue);
  onRowClick(dimKey, isSameValue ? null : String(val));
};

  // ── Empty state ───────────────────────────────────────────────
  if (!data.length) {
    return (
      <div style={{ ...S.empty, height }}>
        <div style={{ fontSize: 28, opacity: 0.3 }}>◌</div>
        <span style={{ fontSize: 12 }}>No data</span>
      </div>
    );
  }

  const colLabel = (k) => {
    if (!k) return "";
    return k.length > 28 ? k.slice(0, 26) + "…" : k;
  };

  // ── Card view ─────────────────────────────────────────────────
  if (useCardView) {
    return (
      <div ref={containerRef} style={{ height, overflowY: "auto", WebkitOverflowScrolling: "touch", width: "100%", boxSizing: "border-box" }}>
        <div style={S.searchWrap}>
          <input
            style={S.searchInput}
            placeholder="Search…"
            value={search}
            onChange={e => setSearch(e.target.value)}
          />
        </div>
        {sorted.map((row, ri) => (
          <div key={ri} style={S.card(ri % 2 === 0)}>
            {allCols.map((k, ci) => {
              const isNum = metCols.includes(k) ||
            (isNumericKey(data, k) && !ID_COL_PATTERN.test(k) && !dimCols.includes(k));
              return (
                <div key={k} style={{
                  ...S.cardRow,
                  borderBottom: ci < allCols.length - 1 ? S.cardRow.borderBottom : "none",
                }}>
                  <span style={S.cardLabel}>{colLabel(k)}</span>
                  <span style={S.cardValue(isNum)}>{fmtCell(row[k], k)}</span>
                </div>
              );
            })}
          </div>
        ))}
        {sorted.length === 0 && (
          <div style={{ ...S.empty, height: 80 }}>
            <span style={{ fontSize: 12 }}>No results for "{search}"</span>
          </div>
        )}
      </div>
    );
  }

  // ── Table view ────────────────────────────────────────────────
  const isCompact = containerWidth > 0 && containerWidth < 600;
  const thStyle = (isNum, isSorted) => ({
    ...S.th(isNum, isSorted),
    padding: isCompact ? "6px 8px" : "8px 12px",
    fontSize: isCompact ? 10 : 11,
    textAlign: "center",
  });
  const tdStyle = (isNum, isEven) => ({
    ...S.td(isNum, isEven),
    padding: isCompact ? "5px 8px" : "7px 12px",
    fontSize: isCompact ? 11 : 12,
    textAlign: "center" ,
  });

  return (
    <div ref={containerRef} style={{ width: "100%", boxSizing: "border-box", display: "flex", flexDirection: "column" }}>

      {/* Search */}
      <div style={S.searchWrap}>
        <input
          style={S.searchInput}
          placeholder="Search…"
          value={search}
          onChange={e => setSearch(e.target.value)}
        />
        {search && (
          <span style={{ fontSize: 10, color: "#64748b", whiteSpace: "nowrap" }}>
            {sorted.length} / {data.length}
          </span>
        )}
      </div>

      {/* Scrollable table */}
      <div style={{ ...S.wrapper, height: height - 40 }}>
        <table style={S.table}>

          {/* ── Header ── */}
          <thead>
            <tr>
              {allCols.map(k => {
                const isNum    = metCols.includes(k) || isNumericKey(data, k);
                const isSorted = sortKey === k;
                return (
                  <th
                    key={k}
                    style={thStyle(isNum, isSorted)}
                    onClick={() => toggle(k)}
                    title={k}
                  >
                    {colLabel(k)}
                    <span style={S.sortArrow(sortDir, isSorted)}>
                      {isSorted ? (sortDir === "asc" ? " ▲" : " ▼") : " ↕"}
                    </span>
                  </th>
                );
              })}
            </tr>
          </thead>

          {/* ── Body ── */}
          <tbody>
            {sorted.length === 0 ? (
              <tr>
                <td
                  colSpan={allCols.length}
                  style={{ textAlign: "center", padding: "20px", color: "#64748b", fontSize: 12 }}
                >
                  No results for "{search}"
                </td>
              </tr>
            ) : (
              sorted.map((row, ri) => {
                const isSelected =
                  dimCols[0] != null &&
                  String(row[dimCols[0]]) === String(crossFilterValue);

                return (
                  <tr
                    key={ri}
                    onClick={() => handleRowClick(row)}
                    style={{
                      cursor:     onRowClick ? "pointer" : "default",
                      background: isSelected ? "rgba(31,168,201,0.15)" : undefined,
                      transition: "background 0.15s",
                    }}
                    onMouseEnter={e => {
                      if (onRowClick && !isSelected)
                        e.currentTarget.style.background = "rgba(255,255,255,0.05)";
                    }}
                    onMouseLeave={e => {
                      e.currentTarget.style.background = isSelected
                        ? "rgba(31,168,201,0.15)"
                        : "";
                    }}
                  >
                    {allCols.map((k, ki) => {
                      const isNum = metCols.includes(k) ||
                          (isNumericKey(data, k) && !ID_COL_PATTERN.test(k) && !dimCols.includes(k));
                      return (
                        <td
                          key={k}
                          style={{
                            ...tdStyle(isNum, ri % 2 === 0),
                            // cyan left border on first cell of selected row
                            ...(ki === 0 && isSelected
                              ? { borderLeft: "3px solid #1FA8C9", paddingLeft: 9 }
                              : {}),
                          }}
                          title={String(row[k] ?? "")}
                        >
                          {fmtCell(row[k], k)}
                        </td>
                      );
                    })}
                  </tr>
                );
              })
            )}
          </tbody>

        </table>
      </div>

      {/* Row count footer */}
      <div style={{ paddingTop: 6, fontSize: 10, color: "#374151", textAlign: "right" }}>
        {sorted.length} row{sorted.length !== 1 ? "s" : ""}
        {search ? ` (filtered from ${data.length})` : ""}
      </div>

    </div>
  );
}