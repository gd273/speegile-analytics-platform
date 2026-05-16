import React, { useState, useEffect, useCallback } from "react";
import api from "./api";
import ChartCard from "./ChartCard";
import { Loader2, SlidersHorizontal, RotateCcw, X, ChevronDown, Zap } from "lucide-react";
import DashboardGrid from "./Dashboardgrid";

const BIGNUM_HEIGHT = 160;

function useWindowWidth() {
  const [w, setW] = useState(typeof window !== "undefined" ? window.innerWidth : 1280);
  useEffect(() => {
    const fn = () => setW(window.innerWidth);
    window.addEventListener("resize", fn);
    return () => window.removeEventListener("resize", fn);
  }, []);
  return w;
}



// ── Simple markdown renderer for dashboard text blocks ──────
function MarkdownBlock({ code }) {
  // ── Detect if content uses HTML tags ──────────────────────
  const hasHtml = /<[a-z][\s\S]*?>/i.test(code || "");

  const containerStyle = {
    background:   "#1e2129",
    border:       "1px solid rgba(255,255,255,0.065)",
    borderRadius: 10,
    padding:      "20px 22px",
    height:       "100%",
    boxSizing:    "border-box",
    overflowY:    "auto",
    position:     "relative",
  };

  const topBar = (
    <div style={{ position: "absolute", top: 0, left: 0, right: 0, height: 3,
      background: "linear-gradient(90deg,#1FA8C9,#454E7C,#A868B7)", opacity: 0.75 }} />
  );

  // ── HTML content — render directly ────────────────────────
  if (hasHtml) {
    return (
      <div style={containerStyle}>
        {topBar}
        <style>{`
          .md-html-block { font-size: 13px; color: #94a3b8; line-height: 1.7; }
          .md-html-block p  { margin: 0 0 8px; }
          .md-html-block b,
          .md-html-block strong { color: #cbd5e1; font-weight: 600; }
          .md-html-block h1 { font-size: 16px; color: #f1f5f9; font-weight: 700; margin: 0 0 12px; }
          .md-html-block h2 { font-size: 14px; color: #e2e8f0; font-weight: 700; margin: 0 0 10px; }
          .md-html-block h3 { font-size: 12px; color: #1FA8C9; font-weight: 700; margin: 12px 0 4px; text-transform: uppercase; }
          .md-html-block center { display: block; text-align: center; }
          .md-html-block a  { color: #1FA8C9; }
        `}</style>
        <div
          className="md-html-block"
          dangerouslySetInnerHTML={{ __html: code }}
        />
      </div>
    );
  }

  // ── Plain markdown content — line-by-line renderer ────────
  const lines = (code || "").split("\n");
  return (
    <div style={containerStyle}>
      {topBar}
      {lines.map((line, i) => {
        if (line.startsWith("### ")) return (
          <p key={i} style={{ fontSize: 12, fontWeight: 700, color: "#1FA8C9",
            margin: "12px 0 4px", letterSpacing: "0.04em", textTransform: "uppercase" }}>
            {line.slice(4)}
          </p>
        );
        if (line.startsWith("## ")) return (
          <h4 key={i} style={{ fontSize: 14, fontWeight: 700, color: "#e2e8f0", margin: "0 0 10px", lineHeight: 1.4 }}>
            {line.slice(3)}
          </h4>
        );
        if (line.startsWith("# ")) return (
          <h3 key={i} style={{ fontSize: 16, fontWeight: 700, color: "#f1f5f9", margin: "0 0 12px", lineHeight: 1.3 }}>
            {line.slice(2)}
          </h3>
        );
        if (line.trim() === "") return <div key={i} style={{ height: 10 }} />;
        const parts = line.split(/(\*\*.*?\*\*)/g).map((p, j) =>
          p.startsWith("**") && p.endsWith("**")
            ? <strong key={j} style={{ color: "#cbd5e1", fontWeight: 600 }}>{p.slice(2, -2)}</strong>
            : p
        );
        return (
          <p key={i} style={{ fontSize: 13, color: "#94a3b8", lineHeight: 1.7, margin: "0 0 8px" }}>
            {parts}
          </p>
        );
      })}
    </div>
  );
}





function parseSupersetLayout(positionJson) {
  if (!positionJson || typeof positionJson !== "object") return null;
  const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, Number.isFinite(Number(v)) ? Number(v) : lo));

  // function parseRowItems(rowComp) {
  //   const items = [];
  //   for (const childId of rowComp.children || []) {
  //     const child = positionJson[childId];
  //     if (!child) continue;
  //     if (child.type === "CHART" && child.meta?.chartId) {
  //       items.push({
  //         chartId:     child.meta.chartId,
  //         width:       clamp(child.meta.width || 6, 1, 12),
  //         heightUnits: child.meta.height || 50,
  //       });
  //     } else if (child.type === "COLUMN") {
  //       const colW = clamp(child.meta?.width || 6, 1, 12);
  //       for (const innerId of child.children || []) {
  //         const inner = positionJson[innerId];
  //         if (!inner) continue;
  //         if (inner.type === "CHART" && inner.meta?.chartId) {
  //           items.push({ chartId: inner.meta.chartId, width: colW, heightUnits: inner.meta.height || 50 });
  //         } else if (inner.type === "ROW") {
  //           items.push(...parseRowItems(inner));
  //         }
  //       }
  //     }
  //   }
  //   return items;
  // }

  function parseRowItems(rowComp) {
  const items = [];
  for (const childId of rowComp.children || []) {
    const child = positionJson[childId];
    if (!child) continue;

    if (child.type === "CHART" && child.meta?.chartId) {
      items.push({
        chartId:     child.meta.chartId,
        width:       clamp(child.meta.width || 6, 1, 12),
        heightUnits: child.meta.height || 50,
      });

    } else if (child.type === "MARKDOWN") {
      items.push({
        type:        "markdown",
        code:        child.meta?.code || "",
        width:       clamp(child.meta?.width || 4, 1, 12),
        heightUnits: child.meta?.height || 50,
      });

    } else if (child.type === "HEADER") {
      items.push({
        type:       "header",
        text:       child.meta?.text || "",
        width:      12,
        heightUnits: 20,
      });

    } else if (child.type === "COLUMN") {
  const colW = clamp(child.meta?.width || 6, 1, 12);
  for (const innerId of child.children || []) {
    const inner = positionJson[innerId];
    if (!inner) continue;
    if (inner.type === "CHART" && inner.meta?.chartId) {
      items.push({ chartId: inner.meta.chartId, width: colW, heightUnits: inner.meta.height || 50 });

    } else if (inner.type === "MARKDOWN") {   // ← ADD THIS
      items.push({
        type:        "markdown",
        code:        inner.meta?.code || "",
        width:       colW,
        heightUnits: inner.meta?.height || 50,
      });

    } else if (inner.type === "HEADER") {     // ← ADD THIS
      items.push({
        type:       "header",
        text:       inner.meta?.text || "",
        width:      colW,
        heightUnits: 20,
      });

    } else if (inner.type === "ROW") {
      items.push(...parseRowItems(inner));
    }
  }
}
  }
  return items;
}

  function idsToRows(childIds) {
    const rows = [];
    for (const id of childIds || []) {
      const comp = positionJson[id];
      if (!comp) continue;
      if (comp.type === "ROW") {
        const items = parseRowItems(comp);
        if (items.length) rows.push(items);
      } else if (comp.type === "COLUMN") {
        for (const innerId of comp.children || []) {
          const inner = positionJson[innerId];
          if (inner?.type === "ROW") {
            const items = parseRowItems(inner);
            if (items.length) rows.push(items);
          }
        }
      }
    }
    return rows;
  }

  function processTabChildren(childIds) {
    const rows = [];
    let nestedTabsSection = null;
    for (const id of childIds || []) {
      const comp = positionJson[id];
      if (!comp) continue;
      if (comp.type === "ROW") {
        const items = parseRowItems(comp);
        if (items.length) rows.push(items);
      } else if (comp.type === "COLUMN") {
        for (const innerId of comp.children || []) {
          const inner = positionJson[innerId];
          if (inner?.type === "ROW") {
            const items = parseRowItems(inner);
            if (items.length) rows.push(items);
          }
        }
      } else if (comp.type === "TABS" || comp.type === "TABS_V2") {
        const nestedTabs = processTabsComp(comp);
        if (nestedTabs.length) {
          nestedTabsSection = { type: "tabs", tabs: nestedTabs };
        }
      }
    }
    return { rows, nestedTabsSection };
  }

  function processTabsComp(tabsComp) {
    const tabs = [];
    for (const tabId of tabsComp.children || []) {
      const tab = positionJson[tabId];
      if (!tab || !tab.type?.startsWith("TAB")) continue;
      const name = (
        tab.meta?.text ||
        tab.meta?.defaultText ||
        tab.meta?.tabTextContent ||
        `Tab ${tabs.length + 1}`
      );
      const { rows, nestedTabsSection } = processTabChildren(tab.children || []);
      tabs.push({ id: tabId, name, rows, nestedTabsSection });
    }
    return tabs;
  }

  const sections = [];
  let pendingRowIds = [];

  function flushRows() {
    const rows = idsToRows(pendingRowIds);
    if (rows.length) sections.push({ type: "rows", rows });
    pendingRowIds = [];
  }

  const grid     = positionJson["GRID_ID"] || positionJson["ROOT_ID"];
  const gridKids = grid?.children || [];

  for (const childId of gridKids) {
    const comp = positionJson[childId];
    if (!comp) continue;
    if (comp.type === "TABS" || comp.type === "TABS_V2") {
      flushRows();
      const tabs = processTabsComp(comp);
      if (tabs.length) sections.push({ type: "tabs", tabs });
    } else if (comp.type === "ROW") {
      pendingRowIds.push(childId);
    }
  }
  flushRows();

  if (!sections.length) {
    const tabsEntries = Object.entries(positionJson)
      .filter(([, v]) => v?.type === "TABS" || v?.type === "TABS_V2");
    for (const [, tabsComp] of tabsEntries) {
      const tabs = processTabsComp(tabsComp);
      if (tabs.length) { sections.push({ type: "tabs", tabs }); break; }
    }
    if (!sections.length) {
      const rowEntries = Object.entries(positionJson)
        .filter(([k, v]) => v?.type === "ROW" &&
          (gridKids.includes(k) || (v.parents || []).some(p => p === "GRID_ID" || p === "ROOT_ID")));
      const rows = rowEntries.map(([, v]) => parseRowItems(v)).filter(i => i.length > 0);
      if (rows.length) sections.push({ type: "rows", rows });
    }
  }

  return sections.length > 0 ? sections : null;
}

const unitsToPx = (u) => Math.max(220, (u || 50) * 8);

// ── Cross-filter pills ──────────────────────────────────────
function CrossFilterPills({ crossFilters, onClear, onClearAll }) {
  const entries = Object.entries(crossFilters).filter(([, f]) => f.value);
  if (!entries.length) return null;
  return (
    <div style={{
      background: "rgba(31,168,201,0.07)", border: "1px solid rgba(31,168,201,0.2)",
      borderRadius: 10, padding: "10px 14px", marginBottom: 12,
      display: "flex", flexWrap: "wrap", gap: 8, alignItems: "center",
    }}>
      <div style={{ display: "flex", alignItems: "center", gap: 6, marginRight: 4 }}>
        <Zap size={13} style={{ color: "#1FA8C9" }} />
        <span style={{ fontSize: 11, fontWeight: 700, color: "#1FA8C9", letterSpacing: "0.07em", textTransform: "uppercase" }}>
          Cross-filters active
        </span>
      </div>
      {entries.map(([col, f]) => (
        <span key={col} style={{
          display: "flex", alignItems: "center", gap: 6, fontSize: 11,
          background: "rgba(31,168,201,0.15)", color: "#67c5d8",
          border: "1px solid rgba(31,168,201,0.3)", padding: "3px 10px 3px 12px", borderRadius: 16,
        }}>
          <span style={{ color: "#4a8fa8", fontSize: 9, fontWeight: 600 }}>{f.sourceChartTitle || "Chart"}:</span>
          <span style={{ color: "#e2e8f0", fontWeight: 600 }}>{f.value}</span>
          <button onClick={() => onClear(col)} style={{
            background: "none", border: "none", color: "#4a8fa8",
            cursor: "pointer", padding: 0, display: "flex", alignItems: "center",
          }}
            onMouseEnter={e => e.currentTarget.style.color = "#1FA8C9"}
            onMouseLeave={e => e.currentTarget.style.color = "#4a8fa8"}>
            <X size={11} />
          </button>
        </span>
      ))}
      {entries.length > 1 && (
        <button onClick={onClearAll} style={{
          fontSize: 10, color: "#4a8fa8", background: "none",
          border: "none", cursor: "pointer", textDecoration: "underline", padding: 0,
        }}
          onMouseEnter={e => e.currentTarget.style.color = "#1FA8C9"}
          onMouseLeave={e => e.currentTarget.style.color = "#4a8fa8"}>
          Clear all
        </button>
      )}
    </div>
  );
}

// ── Tab group ───────────────────────────────────────────────
// ✅ Now receives renderRows as a prop — uses DashboardGrid for responsive layout
function TabGroup({ tabs, chartMap, cardProps, isMobile, renderRows,onTabChange  }) {
  const [activeIdx, setActiveIdx] = useState(0);
  const activeTab = tabs[activeIdx];

  const hasContent = activeTab?.rows?.length > 0 || activeTab?.nestedTabsSection != null;

  return (
    <div style={{ marginBottom: 12 }}>
      {/* ── Tab bar ── */}
      <div style={{
        display: "flex", borderBottom: "2px solid rgba(255,255,255,0.07)",
        marginBottom: 14, overflowX: "auto", scrollbarWidth: "none",
      }}>
        {tabs.map((tab, i) => {
          const active = i === activeIdx;
          return (
            <button
              key={tab.id || i}
              // onClick={() => setActiveIdx(i)}
              onClick={() => {
                
                setActiveIdx(i);
                if (onTabChange) onTabChange();   // ← ADD THIS instead
              }}



              style={{
                padding: "10px 20px", fontSize: 13, fontWeight: active ? 700 : 500,
                color: active ? "#1FA8C9" : "#64748b", background: "none", border: "none",
                borderBottom: `2px solid ${active ? "#1FA8C9" : "transparent"}`,
                cursor: "pointer", transition: "color .15s, border-color .15s",
                whiteSpace: "nowrap", outline: "none", marginBottom: "-2px", flexShrink: 0,
              }}
              onMouseEnter={e => { if (!active) e.currentTarget.style.color = "#94a3b8"; }}
              onMouseLeave={e => { if (!active) e.currentTarget.style.color = "#64748b"; }}
            >
              {tab.name}
            </button>
          );
        })}
      </div>

      {/* ── Active tab: direct rows — uses renderRows for DashboardGrid ── */}
      {activeTab?.rows?.length > 0 && renderRows(activeTab.rows)}

      {/* ── Active tab: nested sub-tabs ── */}
      {activeTab?.nestedTabsSection && (
        <TabGroup
          tabs={activeTab.nestedTabsSection.tabs}
          chartMap={chartMap}
          cardProps={cardProps}
          isMobile={isMobile}
          renderRows={renderRows}  // ✅ pass down to nested tabs too
          onTabChange={onTabChange}
        />
      )}

      {/* ── Empty state ── */}
      {!hasContent && (
        <div style={{ padding: "40px 0", textAlign: "center", color: "#374151", fontSize: 13 }}>
          No charts in this tab
        </div>
      )}
    </div>
  );
}

// ── Filter panel ────────────────────────────────────────────
function FilterPanel({ filterDefs, activeFilters, dateFrom, dateTo, onFilterChange, onDateFromChange, onDateToChange, onReset }) {
  const [open, setOpen] = useState(false);
  if (!filterDefs?.length) return null;

  const hasActive = Object.values(activeFilters).some(Boolean) || !!dateFrom;

  return (
    <div style={{ background: "#12151f", border: "1px solid rgba(255,255,255,0.07)", borderRadius: 10, marginBottom: 14, overflow: "hidden" }}>

      {/* ── Header ── */}
      <div
        onClick={() => setOpen(p => !p)}
        style={{
          display: "flex", alignItems: "center", justifyContent: "space-between",
          padding: "10px 16px", cursor: "pointer", userSelect: "none",
          borderBottom: open ? "1px solid rgba(255,255,255,0.06)" : "none",
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
          <SlidersHorizontal size={13} style={{ color: "#64748b" }} />
          <span style={{ fontSize: 11, fontWeight: 700, color: "#64748b", letterSpacing: "0.09em", textTransform: "uppercase" }}>
            Filters
          </span>
          {hasActive && (
            <span style={{ fontSize: 9, background: "#1FA8C9", color: "#fff", borderRadius: 8, padding: "1px 6px", fontWeight: 700 }}>
              ACTIVE
            </span>
          )}
        </div>
        <ChevronDown size={14} style={{ color: "#374151", transition: "transform .2s", transform: open ? "rotate(180deg)" : "rotate(0deg)" }} />
      </div>

      {/* ── Controls ── */}
      {open && (
        <div style={{ padding: "14px 16px", display: "flex", flexDirection: "column", gap: 16 }}>
          {filterDefs.map(fd => {

            if (fd.type === "date") return (
              <div key={fd.id}>
                <FLabel>{fd.name}</FLabel>
                <div style={{ display: "flex", alignItems: "center", gap: 7 }}>
                  <FDate value={dateFrom} onChange={e => onDateFromChange(e.target.value)} />
                  <span style={{ fontSize: 11, color: "#2d3748" }}>→</span>
                  <FDate value={dateTo} onChange={e => onDateToChange(e.target.value)} />
                </div>
              </div>
            );

            if (fd.type === "select") return (
              <div key={fd.id}>
                <FLabel>{fd.name}</FLabel>
                <div style={{
                  maxHeight: 132, overflowY: "auto", overflowX: "hidden",
                  paddingRight: 4, paddingBottom: 4,
                  scrollbarWidth: "thin", scrollbarColor: "#2d3748 transparent",
                }}>
                  <style>{`
                    .fp-pill-wrap::-webkit-scrollbar { width: 4px; }
                    .fp-pill-wrap::-webkit-scrollbar-track { background: transparent; }
                    .fp-pill-wrap::-webkit-scrollbar-thumb { background: #2d3748; border-radius: 4px; }
                    .fp-pill-wrap::-webkit-scrollbar-thumb:hover { background: #374151; }
                  `}</style>
                  <div className="fp-pill-wrap" style={{ display: "flex", flexWrap: "wrap", gap: 5 }}>
                    {fd.values.map(val => {
                      const active = activeFilters[fd.column] === val;
                      return (
                        <button
                          key={val}
                          onClick={() => onFilterChange && onFilterChange(fd.column, val)}
                          style={{
                            padding: "4px 11px", borderRadius: 16, fontSize: 11,
                            fontWeight: 600, cursor: "pointer", border: "1px solid",
                            outline: "none", flexShrink: 0, transition: "all .15s ease",
                            background: active ? "#1FA8C9" : "rgba(31,168,201,0.08)",
                            color: active ? "#fff" : "#5ba8b9",
                            borderColor: active ? "#1FA8C9" : "rgba(31,168,201,0.22)",
                          }}
                        >
                          {val}
                        </button>
                      );
                    })}
                  </div>
                </div>
                {fd.values.length > 20 && (
                  <p style={{ fontSize: 9, color: "#374151", marginTop: 5, letterSpacing: "0.06em" }}>
                    {fd.values.length} options · scroll to see more
                  </p>
                )}
              </div>
            );

            return null;
          })}
          <div><FResetBtn onClick={onReset} /></div>
        </div>
      )}
    </div>
  );
}

const FLabel = ({ children }) => (
  <p style={{ fontSize: 10, color: "#475569", textTransform: "uppercase", letterSpacing: "0.08em", marginBottom: 7, fontWeight: 700 }}>
    {children}
  </p>
);
const FDate = ({ value, onChange }) => (
  <input type="date" value={value} onChange={onChange} style={{
    background: "#0d1117", border: "1px solid #2d3748", borderRadius: 7,
    padding: "5px 9px", fontSize: 11, color: "#94a3b8", width: 132, outline: "none", cursor: "pointer",
  }} />
);
function FResetBtn({ onClick }) {
  const [hov, setHov] = useState(false);
  return (
    <button
      onClick={onClick}
      onMouseEnter={() => setHov(true)}
      onMouseLeave={() => setHov(false)}
      style={{
        display: "flex", alignItems: "center", gap: 5, padding: "6px 13px", borderRadius: 7,
        fontSize: 11, fontWeight: 600, border: `1px solid ${hov ? "#475569" : "#2d3748"}`,
        color: hov ? "#94a3b8" : "#64748b", background: "transparent", cursor: "pointer", transition: "all .15s",
      }}
    >
      <RotateCcw size={11} /> Reset
    </button>
  );
}

function ActivePills({ activeFilters, dateFrom, dateTo, onRemove, onRemoveDate }) {
  const entries = Object.entries(activeFilters).filter(([, v]) => v);
  if (!entries.length && !dateFrom) return null;
  return (
    <div style={{ display: "flex", flexWrap: "wrap", gap: 6, marginBottom: 14, alignItems: "center" }}>
      <span style={{ fontSize: 9, color: "#374151", fontWeight: 700, letterSpacing: "0.09em", textTransform: "uppercase" }}>Active:</span>
      {entries.map(([col, val]) => (
        <span key={col} style={{
          display: "flex", alignItems: "center", gap: 5, fontSize: 11,
          background: "rgba(31,168,201,0.12)", color: "#67c5d8",
          border: "1px solid rgba(31,168,201,0.22)", padding: "3px 8px 3px 10px", borderRadius: 16,
        }}>
          <span style={{ color: "#4a5568", fontSize: 9 }}>{col}:</span>&nbsp;{val}
          <button onClick={() => onRemove(col)} style={{ background: "none", border: "none", color: "#64748b", cursor: "pointer", padding: 0, display: "flex", alignItems: "center" }}>
            <X size={10} />
          </button>
        </span>
      ))}
      {dateFrom && dateTo && (
        <span style={{
          display: "flex", alignItems: "center", gap: 5, fontSize: 11,
          background: "rgba(139,92,246,0.12)", color: "#a78bfa",
          border: "1px solid rgba(139,92,246,0.22)", padding: "3px 8px 3px 10px", borderRadius: 16,
        }}>
          {dateFrom} → {dateTo}
          <button onClick={onRemoveDate} style={{ background: "none", border: "none", color: "#64748b", cursor: "pointer", padding: 0, display: "flex", alignItems: "center" }}>
            <X size={10} />
          </button>
        </span>
      )}
    </div>
  );
}





// ══════════════════════════════════════════════════════════════
//  MAIN COMPONENT
// ══════════════════════════════════════════════════════════════
export default function DashboardChartsPage({ dashboardNumericId }) {
  const [charts,        setCharts]        = useState([]);
  const [sections,      setSections]      = useState(null);
  const [filterDefs,    setFilterDefs]    = useState([]);
  const [activeFilters, setActiveFilters] = useState({});
  const [dateFrom,      setDateFrom]      = useState("");
  const [dateTo,        setDateTo]        = useState("");
  const [loading,       setLoading]       = useState(true);
  const [error,         setError]         = useState(null);
  const [crossFilters,  setCrossFilters]  = useState({});

  const windowWidth = useWindowWidth();
  const isMobile    = windowWidth < 768;
  

  useEffect(() => {
    if (!dashboardNumericId) return;
    setLoading(true); setError(null);
    setActiveFilters({}); setDateFrom(""); setDateTo("");
    setSections(null); setCrossFilters({});

    Promise.all([
      api.get("/dashboard-charts", { params: { dashboardId: dashboardNumericId } }),
      api.get("/dashboard-layout",  { params: { dashboardId: dashboardNumericId } }).catch(() => null),
      api.get("/filter-options",    { params: { dashboardId: dashboardNumericId } }).catch(() => null),
    ]).then(([cR, lR, fR]) => {
      if (cR.data.success) setCharts(cR.data.charts.filter(c => c.viz_type !== "filter_box"));
      if (lR?.data?.success) { const p = parseSupersetLayout(lR.data.layout); setSections(p); }
      if (fR?.data?.success) setFilterDefs(fR.data.filters || []);
    }).catch(() => setError("Failed to load dashboard."))
      .finally(() => setLoading(false));
  }, [dashboardNumericId]);

  const handleFilterChange   = useCallback((col, val) => setActiveFilters(prev => ({ ...prev, [col]: prev[col] === val ? null : val })), []);
  const handleReset          = useCallback(() => { setActiveFilters({}); setDateFrom(""); setDateTo(""); }, []);

  const handleCrossFilter = useCallback((column, value, sourceChartId, sourceChartTitle, fromTable = false) => {
      setCrossFilters(prev => {
        if (!value) { const next = {...prev}; delete next[column]; return next; }
        return { ...prev, [column]: { value, sourceChartId, sourceChartTitle, fromTable } };
      });
    }, []);


  const clearCrossFilter     = useCallback((col) => setCrossFilters(prev => { const n = { ...prev }; delete n[col]; return n; }), []);
  const clearAllCrossFilters = useCallback(() => setCrossFilters({}), []);

  if (loading) return (
    <div style={{ display: "flex", alignItems: "center", justifyContent: "center", padding: "64px 0" }}>
      <Loader2 size={20} style={{ color: "#1FA8C9", animation: "spin .9s linear infinite" }} />
      <span style={{ marginLeft: 10, color: "#64748b", fontSize: 14 }}>Loading dashboard…</span>
      <style>{`@keyframes spin{from{transform:rotate(0)}to{transform:rotate(360deg)}}`}</style>
    </div>
  );
  if (error) return <div style={{ textAlign: "center", padding: "64px 0", color: "#f87171", fontSize: 13 }}>⚠ {error}</div>;
  if (!charts.length) return <div style={{ textAlign: "center", padding: "64px 0", color: "#374151", fontSize: 13 }}>No charts found.</div>;

  const chartMap = Object.fromEntries(charts.map(c => [c.slice_id, c]));

  // const cardProps = (chart, chartHeightPx = 320) => ({
  //   sliceId:        chart.slice_id,
  //   title:          chart.slice_name,
  //   vizType:        chart.viz_type,
  //   xAxis:          chart.x_axis,

  //   height:         chartHeightPx,
  //   activeFilters,
  //   dateFrom:       dateFrom || null,
  //   dateTo:         dateTo   || null,
  //   crossFilters,
  //   onCrossFilter:  handleCrossFilter,
  //   onDrillDown:    handleFilterChange,
  //   metrics:        chart.metrics       || [],
  //   groupby:        chart.groupby       || [],
  //   groupbyRows:    chart.groupby_rows  || [],
  //   groupbyColumns: chart.groupby_cols  || [],
  // });

  // ── Update cardProps ──
const cardProps = (chart, chartHeightPx = 320) => ({
  sliceId:        chart.slice_id,
  title:          chart.slice_name,
  vizType:        chart.viz_type,
  xAxis:          chart.x_axis,
  // ← bignum always gets fixed height, other charts use layout height
  height: (chart.viz_type || "").toLowerCase().includes("big_number")
    ? BIGNUM_HEIGHT
    : chartHeightPx,
  activeFilters,
  dateFrom:       dateFrom || null,
  dateTo:         dateTo   || null,
  crossFilters,
  onCrossFilter:  handleCrossFilter,
  onDrillDown:    handleFilterChange,
  metrics:        chart.metrics       || [],
  groupby:        chart.groupby       || [],
  groupbyRows:    chart.groupby_rows  || [],
  groupbyColumns: chart.groupby_cols  || [],
  zoomable:       chart.zoomable      || false,   // ← ADD THIS
});

  // ✅ Uses DashboardGrid — handles mobile/tablet/desktop breakpoints automatically
  const renderRows = (rows) => rows.map((row, rIdx) => {
    const totalCols = row.reduce((sum, item) => sum + (item.width || 6), 0);
    const gridCols  = Math.min(Math.max(totalCols, 1), 12);

    return (
    <div key={rIdx} style={{ marginBottom: 20 }}>  {/* ✅ vertical spacing between rows */}
      <DashboardGrid columns={gridCols} gap={12}>
        {row.map((item, cIdx) => {
              // ── Markdown text block ──
              if (item.type === "markdown") {
                return (
                  <div key={cIdx} style={{
                    gridColumn: isMobile ? "span 1" : `span ${item.width}`,
                    height:     unitsToPx(item.heightUnits),
                  }}>
                    <MarkdownBlock code={item.code} />
                  </div>
                );
              }

              // ── Header text ──
              if (item.type === "header") {
                return (
                  <div key={cIdx} style={{ gridColumn: "span 12", padding: "4px 0" }}>
                    <h2 style={{ fontSize: 16, fontWeight: 600, color: "#cbd5e1", margin: 0 }}>
                      {item.text}
                    </h2>
                  </div>
                );
              }

              // ── Regular chart ──
              const chart = chartMap[item.chartId];
              if (!chart) return null;
              return (
                <div key={cIdx} style={{ gridColumn: isMobile ? "span 1" : `span ${item.width}` }}>
                  <ChartCard {...cardProps(chart, unitsToPx(item.heightUnits))} />
                </div>
              );
            })}
                  </DashboardGrid>
                </div>
              );
            });

  const renderWithLayout = () => sections.map((section, sIdx) => {
    if (section.type === "rows")
      return <React.Fragment key={sIdx}>{renderRows(section.rows)}</React.Fragment>;
    if (section.type === "tabs")
      return (
        <TabGroup
          key={sIdx}
          tabs={section.tabs}
          chartMap={chartMap}
          cardProps={cardProps}
          isMobile={isMobile}
          renderRows={renderRows}
          onTabChange={() => setCrossFilters({})}
        />
      );
    return null;
  });

  const renderFallback = () => (
    <div style={{
      display: "grid",
      gridTemplateColumns: isMobile ? "1fr" : "repeat(auto-fill,minmax(min(100%,480px),1fr))",
      gap: 12,
    }}>
      {charts.map(chart => <ChartCard key={chart.slice_id} {...cardProps(chart, 320)} />)}
    </div>
  );

  return (
    <div style={{ background: "#0d1117", minHeight: "100vh", padding: isMobile ? "10px" : "16px", position: "relative" }}>
      <CrossFilterPills crossFilters={crossFilters} onClear={clearCrossFilter} onClearAll={clearAllCrossFilters} />
      <FilterPanel
        filterDefs={filterDefs} activeFilters={activeFilters}
        dateFrom={dateFrom} dateTo={dateTo}
        onFilterChange={handleFilterChange}
        onDateFromChange={setDateFrom} onDateToChange={setDateTo}
        onReset={handleReset}
      />
      <ActivePills
        activeFilters={activeFilters} dateFrom={dateFrom} dateTo={dateTo}
        onRemove={col => setActiveFilters(p => ({ ...p, [col]: null }))}
        onRemoveDate={() => { setDateFrom(""); setDateTo(""); }}
      />
      {sections ? renderWithLayout() : renderFallback()}
    </div>
  );
}
