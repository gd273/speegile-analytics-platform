import React, { useState, useEffect, useCallback, useRef } from "react";
import api from "./api";
import ChartCard from "./ChartCard";
import { Loader2, SlidersHorizontal, RotateCcw, X, ChevronDown, Zap, Check } from "lucide-react";
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

// ── PDF progress overlay ────────────────────────────────────
function PdfProgressOverlay({ progress }) {
  if (!progress) return null;
  const pct = progress.total > 0
    ? Math.round((progress.current / progress.total) * 100)
    : 0;
  return (
    <div style={{ position: "fixed", inset: 0, zIndex: 9999, background: "rgba(0,0,0,0.82)", display: "flex", alignItems: "center", justifyContent: "center" }}>
      <style>{`
        @keyframes pdf-spin    { to { transform: rotate(360deg); } }
        @keyframes pdf-shimmer { 0%{background-position:200% 0} 100%{background-position:-200% 0} }
      `}</style>
      <div style={{ background: "#1a1d26", border: "1px solid rgba(31,168,201,0.25)", borderRadius: 16, padding: "36px 44px", width: 400, display: "flex", flexDirection: "column", alignItems: "center", gap: 22, boxShadow: "0 24px 60px rgba(0,0,0,0.6)" }}>
        <div style={{ position: "relative", width: 56, height: 56 }}>
          <div style={{ position: "absolute", inset: 0, borderRadius: "50%", border: "3px solid rgba(31,168,201,0.12)" }} />
          <div style={{ position: "absolute", inset: 0, borderRadius: "50%", border: "3px solid transparent", borderTopColor: "#1FA8C9", animation: "pdf-spin 1s linear infinite" }} />
          <div style={{ position: "absolute", inset: 0, display: "flex", alignItems: "center", justifyContent: "center", fontSize: 22 }}>📄</div>
        </div>
        <div style={{ textAlign: "center" }}>
          <div style={{ fontSize: 17, fontWeight: 700, color: "#e2e8f0", marginBottom: 8 }}>Generating PDF</div>
          <div style={{ fontSize: 12, color: "#64748b" }}>Processing: <span style={{ color: "#1FA8C9", fontWeight: 600 }}>{progress.tabName}</span></div>
        </div>
        <div style={{ width: "100%" }}>
          <div style={{ width: "100%", height: 8, background: "rgba(255,255,255,0.06)", borderRadius: 99, overflow: "hidden" }}>
            <div style={{ width: `${pct}%`, height: "100%", borderRadius: 99, background: "linear-gradient(90deg,#1FA8C9 0%,#A868B7 60%,#1FA8C9 100%)", backgroundSize: "200% 100%", animation: "pdf-shimmer 1.5s linear infinite", transition: "width 0.6s ease" }} />
          </div>
          <div style={{ display: "flex", justifyContent: "space-between", marginTop: 8 }}>
            <span style={{ fontSize: 11, color: "#374151" }}>Page {progress.current} of {progress.total}</span>
            <span style={{ fontSize: 11, color: "#1FA8C9", fontWeight: 700 }}>{pct}%</span>
          </div>
        </div>
        <div style={{ fontSize: 11, color: "#374151", letterSpacing: "0.03em" }}>Please keep this window open</div>
      </div>
    </div>
  );
}

// ── Simple markdown renderer ────────────────────────────────
function MarkdownBlock({ code }) {
  const hasHtml = /<[a-z][\s\S]*?>/i.test(code || "");
  const containerStyle = { background: "#1e2129", border: "1px solid rgba(255,255,255,0.065)", borderRadius: 10, padding: "20px 22px", height: "100%", boxSizing: "border-box", overflowY: "auto", position: "relative" };
  const topBar = <div style={{ position: "absolute", top: 0, left: 0, right: 0, height: 3, background: "linear-gradient(90deg,#1FA8C9,#454E7C,#A868B7)", opacity: 0.75 }} />;
  if (hasHtml) {
    return (
      <div style={containerStyle}>
        {topBar}
        <style>{`.md-html-block{font-size:13px;color:#94a3b8;line-height:1.7}.md-html-block p{margin:0 0 8px}.md-html-block b,.md-html-block strong{color:#cbd5e1;font-weight:600}.md-html-block h1{font-size:16px;color:#f1f5f9;font-weight:700;margin:0 0 12px}.md-html-block h2{font-size:14px;color:#e2e8f0;font-weight:700;margin:0 0 10px}.md-html-block h3{font-size:12px;color:#1FA8C9;font-weight:700;margin:12px 0 4px;text-transform:uppercase}.md-html-block center{display:block;text-align:center}.md-html-block a{color:#1FA8C9}`}</style>
        <div className="md-html-block" dangerouslySetInnerHTML={{ __html: code }} />
      </div>
    );
  }
  const lines = (code || "").split("\n");
  return (
    <div style={containerStyle}>
      {topBar}
      {lines.map((line, i) => {
        if (line.startsWith("### ")) return <p key={i} style={{ fontSize: 12, fontWeight: 700, color: "#1FA8C9", margin: "12px 0 4px", letterSpacing: "0.04em", textTransform: "uppercase" }}>{line.slice(4)}</p>;
        if (line.startsWith("## "))  return <h4 key={i} style={{ fontSize: 14, fontWeight: 700, color: "#e2e8f0", margin: "0 0 10px", lineHeight: 1.4 }}>{line.slice(3)}</h4>;
        if (line.startsWith("# "))   return <h3 key={i} style={{ fontSize: 16, fontWeight: 700, color: "#f1f5f9", margin: "0 0 12px", lineHeight: 1.3 }}>{line.slice(2)}</h3>;
        if (line.trim() === "")      return <div key={i} style={{ height: 10 }} />;
        const parts = line.split(/(\*\*.*?\*\*)/g).map((p, j) =>
          p.startsWith("**") && p.endsWith("**")
            ? <strong key={j} style={{ color: "#cbd5e1", fontWeight: 600 }}>{p.slice(2, -2)}</strong>
            : p
        );
        return <p key={i} style={{ fontSize: 13, color: "#94a3b8", lineHeight: 1.7, margin: "0 0 8px" }}>{parts}</p>;
      })}
    </div>
  );
}

// ── Layout parser ───────────────────────────────────────────
function parseSupersetLayout(positionJson) {
  if (!positionJson || typeof positionJson !== "object") return null;
  const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, Number.isFinite(Number(v)) ? Number(v) : lo));

  function parseRowItems(rowComp) {
    const items = [];
    for (const childId of rowComp.children || []) {
      const child = positionJson[childId];
      if (!child) continue;
      if (child.type === "CHART" && child.meta?.chartId) {
        items.push({ chartId: child.meta.chartId, width: clamp(child.meta.width || 6, 1, 12), heightUnits: child.meta.height || 50 });
      } else if (child.type === "MARKDOWN") {
        items.push({ type: "markdown", code: child.meta?.code || "", width: clamp(child.meta?.width || 4, 1, 12), heightUnits: child.meta?.height || 50 });
      } else if (child.type === "HEADER") {
        items.push({ type: "header", text: child.meta?.text || "", width: 12, heightUnits: 20 });
      } else if (child.type === "COLUMN") {
        const colW = clamp(child.meta?.width || 6, 1, 12);
        for (const innerId of child.children || []) {
          const inner = positionJson[innerId];
          if (!inner) continue;
          if (inner.type === "CHART" && inner.meta?.chartId) {
            items.push({ chartId: inner.meta.chartId, width: colW, heightUnits: inner.meta.height || 50 });
          } else if (inner.type === "MARKDOWN") {
            items.push({ type: "markdown", code: inner.meta?.code || "", width: colW, heightUnits: inner.meta?.height || 50 });
          } else if (inner.type === "HEADER") {
            items.push({ type: "header", text: inner.meta?.text || "", width: colW, heightUnits: 20 });
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
          if (inner?.type === "ROW") { const items = parseRowItems(inner); if (items.length) rows.push(items); }
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
          if (inner?.type === "ROW") { const items = parseRowItems(inner); if (items.length) rows.push(items); }
        }
      } else if (comp.type === "TABS" || comp.type === "TABS_V2") {
        const nestedTabs = processTabsComp(comp);
        if (nestedTabs.length) nestedTabsSection = { type: "tabs", tabs: nestedTabs };
      }
    }
    return { rows, nestedTabsSection };
  }

  function processTabsComp(tabsComp) {
    const tabs = [];
    for (const tabId of tabsComp.children || []) {
      const tab = positionJson[tabId];
      if (!tab || !tab.type?.startsWith("TAB")) continue;
      const name = tab.meta?.text || tab.meta?.defaultText || tab.meta?.tabTextContent || `Tab ${tabs.length + 1}`;
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
    const tabsEntries = Object.entries(positionJson).filter(([, v]) => v?.type === "TABS" || v?.type === "TABS_V2");
    for (const [, tabsComp] of tabsEntries) {
      const tabs = processTabsComp(tabsComp);
      if (tabs.length) { sections.push({ type: "tabs", tabs }); break; }
    }
    if (!sections.length) {
      const rowEntries = Object.entries(positionJson)
        .filter(([k, v]) => v?.type === "ROW" && (gridKids.includes(k) || (v.parents || []).some(p => p === "GRID_ID" || p === "ROOT_ID")));
      const rows = rowEntries.map(([, v]) => parseRowItems(v)).filter(i => i.length > 0);
      if (rows.length) sections.push({ type: "rows", rows });
    }
  }
  return sections.length > 0 ? sections : null;
}

const unitsToPx = (u) => Math.max(220, (u || 50) * 8);

// ── Cross-filter pills ──────────────────────────────────────
// function CrossFilterPills({ crossFilters, onClear, onClearAll }) {
//   const entries = Object.entries(crossFilters).filter(([, f]) => f.value)
//   if (!entries.length) return null;
//   return (
//     <div style={{ background: "rgba(31,168,201,0.07)", border: "1px solid rgba(31,168,201,0.2)", borderRadius: 10, padding: "10px 14px", marginBottom: 12, display: "flex", flexWrap: "wrap", gap: 8, alignItems: "center" }}>
//       <div style={{ display: "flex", alignItems: "center", gap: 6, marginRight: 4 }}>
//         <Zap size={13} style={{ color: "#1FA8C9" }} />
//         <span style={{ fontSize: 11, fontWeight: 700, color: "#1FA8C9", letterSpacing: "0.07em", textTransform: "uppercase" }}>Cross-filters active</span>
//       </div>
//       {entries.map(([col, f]) => (
//         <span key={col} style={{ display: "flex", alignItems: "center", gap: 6, fontSize: 11, background: "rgba(31,168,201,0.15)", color: "#67c5d8", border: "1px solid rgba(31,168,201,0.3)", padding: "3px 10px 3px 12px", borderRadius: 16 }}>
//           <span style={{ color: "#4a8fa8", fontSize: 9, fontWeight: 600 }}>{f.sourceChartTitle || "Chart"}:</span>
//           <span style={{ color: "#e2e8f0", fontWeight: 600 }}>{f.value}</span>
//           <button onClick={() => onClear(col)} style={{ background: "none", border: "none", color: "#4a8fa8", cursor: "pointer", padding: 0, display: "flex", alignItems: "center" }}
//             onMouseEnter={e => e.currentTarget.style.color = "#1FA8C9"}
//             onMouseLeave={e => e.currentTarget.style.color = "#4a8fa8"}>
//             <X size={11} />
//           </button>
//         </span>
//       ))}
//       {entries.length > 1 && (
//         <button onClick={onClearAll} style={{ fontSize: 10, color: "#4a8fa8", background: "none", border: "none", cursor: "pointer", textDecoration: "underline", padding: 0 }}
//           onMouseEnter={e => e.currentTarget.style.color = "#1FA8C9"}
//           onMouseLeave={e => e.currentTarget.style.color = "#4a8fa8"}>
//           Clear all
//         </button>
//       )}
//     </div>
//   );
// }


function CrossFilterPills({ crossFilters, onClear, onClearAll, crossFilterScopeMap = {}, crossFiltersEnabled = false }) {
  const scopeMapLoaded = crossFilterScopeMap && Object.keys(crossFilterScopeMap).length > 0;

  const entries = Object.entries(crossFilters).filter(([, f]) => {
    if (!f.value) return false;
    if (!scopeMapLoaded) return true;
    if (!crossFiltersEnabled) return false;
    const sourceId = Number(f.sourceChartId);
    if (!crossFilterScopeMap.hasOwnProperty(sourceId)) return true;
    return crossFilterScopeMap[sourceId].length > 0;
  });

  if (!entries.length) return null;
  return (
    <div style={{ background: "rgba(31,168,201,0.07)", border: "1px solid rgba(31,168,201,0.2)", borderRadius: 10, padding: "10px 14px", marginBottom: 12, display: "flex", flexWrap: "wrap", gap: 8, alignItems: "center" }}>
      <div style={{ display: "flex", alignItems: "center", gap: 6, marginRight: 4 }}>
        <Zap size={13} style={{ color: "#1FA8C9" }} />
        <span style={{ fontSize: 11, fontWeight: 700, color: "#1FA8C9", letterSpacing: "0.07em", textTransform: "uppercase" }}>Cross-filters active</span>
      </div>
      {entries.map(([col, f]) => (
        <span key={col} style={{ display: "flex", alignItems: "center", gap: 6, fontSize: 11, background: "rgba(31,168,201,0.15)", color: "#67c5d8", border: "1px solid rgba(31,168,201,0.3)", padding: "3px 10px 3px 12px", borderRadius: 16 }}>
          <span style={{ color: "#4a8fa8", fontSize: 9, fontWeight: 600 }}>{f.sourceChartTitle || "Chart"}:</span>
          <span style={{ color: "#e2e8f0", fontWeight: 600 }}>{f.value}</span>
          <button onClick={() => onClear(col)} style={{ background: "none", border: "none", color: "#4a8fa8", cursor: "pointer", padding: 0, display: "flex", alignItems: "center" }}
            onMouseEnter={e => e.currentTarget.style.color = "#1FA8C9"}
            onMouseLeave={e => e.currentTarget.style.color = "#4a8fa8"}>
            <X size={11} />
          </button>
        </span>
      ))}
      {entries.length > 1 && (
        <button onClick={onClearAll} style={{ fontSize: 10, color: "#4a8fa8", background: "none", border: "none", cursor: "pointer", textDecoration: "underline", padding: 0 }}
          onMouseEnter={e => e.currentTarget.style.color = "#1FA8C9"}
          onMouseLeave={e => e.currentTarget.style.color = "#4a8fa8"}>
          Clear all
        </button>
      )}
    </div>
  );
}


// ── Date Range Picker ───────────────────────────────────────
function DateRangePicker({ dateFrom, dateTo, onFromChange, onToChange, onClear, dataDateRange }) {
  const [draftFrom, setDraftFrom] = useState(dateFrom || "");
  const [draftTo,   setDraftTo]   = useState(dateTo   || "");

  useEffect(() => {
    setDraftFrom(dateFrom || "");
    setDraftTo(dateTo     || "");
  }, [dateFrom, dateTo]);

  const hasDate = dateFrom || dateTo;

  const handleSearch = () => {
    console.log("🔍 handleSearch called:", { draftFrom, draftTo }); // ADD
    onFromChange(draftFrom || null);
    onToChange(draftTo     || null);
  };

  const handleClear = () => {
    setDraftFrom("");
    setDraftTo("");
    onClear();
  };

  const inputStyle = (hasVal) => ({
    background: "#12151f",
    border: `1px solid ${hasVal ? "#1FA8C9" : "rgba(255,255,255,0.1)"}`,
    borderRadius: 6, padding: "4px 8px",
    color: hasVal ? "#e2e8f0" : "#64748b",
    fontSize: 11, cursor: "pointer", outline: "none", colorScheme: "dark",
  });

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 4 }}>
      <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
        <span style={{ fontSize: 12, color: "#64748b", whiteSpace: "nowrap" }}>📅 Date</span>
        <input type="date" value={draftFrom}
          min={dataDateRange?.min || undefined}
          max={draftTo || dataDateRange?.max || undefined}
          onChange={e => setDraftFrom(e.target.value)}
          style={inputStyle(draftFrom)} />
        <span style={{ color: "#64748b", fontSize: 11 }}>→</span>
        <input type="date" value={draftTo}
          min={draftFrom || dataDateRange?.min || undefined}
          max={dataDateRange?.max || undefined}
          onChange={e => setDraftTo(e.target.value)}
          style={inputStyle(draftTo)} />
        {/* <button onClick={handleSearch} disabled={!draftFrom || !draftTo} */}
        <button onClick={() => {
                console.log("🔍 BUTTON CLICKED", { draftFrom, draftTo });
                handleSearch();
              }} 
              disabled={!draftFrom || !draftTo}
          style={{
            display: "flex", alignItems: "center", gap: 4,
            background: (draftFrom && draftTo) ? "rgba(31,168,201,0.15)" : "rgba(255,255,255,0.03)",
            border: `1px solid ${(draftFrom && draftTo) ? "rgba(31,168,201,0.4)" : "rgba(255,255,255,0.08)"}`,
            borderRadius: 6, padding: "4px 12px",
            color: (draftFrom && draftTo) ? "#1FA8C9" : "#374151",
            fontSize: 11, fontWeight: 600,
            cursor: (draftFrom && draftTo) ? "pointer" : "not-allowed",
            whiteSpace: "nowrap", transition: "all 0.15s",
          }}>
          🔍 Search
        </button>
        {hasDate && (
          <button onClick={handleClear}
            style={{ background: "rgba(248,113,113,0.1)", border: "1px solid rgba(248,113,113,0.3)", borderRadius: 6, padding: "4px 8px", color: "#f87171", fontSize: 11, cursor: "pointer" }}>
            ✕
          </button>
        )}
      </div>
      {dataDateRange?.min && dataDateRange?.max && (
        <div style={{ fontSize: 10, color: "#475569", paddingLeft: 24, letterSpacing: "0.02em" }}>
          {/* Data available hint commented out */}
        </div>
      )}
    </div>
  );
}

// ── Tab group ───────────────────────────────────────────────
function TabGroup({ tabs = [], chartMap, cardProps, isMobile, renderRows, onTabChange, pdfTabIdx, pdfNestedTabIdx, dateFrom, dateTo, setDateFrom, setDateTo, dataDateRange, hasTimeFilter  }) {
  const [activeIdx, setActiveIdx] = useState(0);

  useEffect(() => {
    if (tabs.length > 0 && onTabChange) onTabChange(tabs[0].id);
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  const displayIdx = (pdfTabIdx !== null && pdfTabIdx !== undefined) ? Math.min(pdfTabIdx, tabs.length - 1) : activeIdx;
  const activeTab  = tabs[displayIdx];
  const hasContent = activeTab?.rows?.length > 0 || activeTab?.nestedTabsSection != null;

  return (
    <div style={{ marginBottom: 12 }}>
      <div>
  <style>{`
    .tabs-scroll-container::-webkit-scrollbar { height: 3px; }
    .tabs-scroll-container::-webkit-scrollbar-track { background: rgba(255,255,255,0.04); border-radius: 10px; }
    .tabs-scroll-container::-webkit-scrollbar-thumb { background: rgba(31,168,201,0.4); border-radius: 10px; transition: background 0.2s; }
    .tabs-scroll-container::-webkit-scrollbar-thumb:hover { background: rgba(31,168,201,0.8); }
    .tabs-scroll-container { scrollbar-width: thin; scrollbar-color: rgba(31,168,201,0.4) rgba(255,255,255,0.04); }
  `}</style>

  {/* ── Tab buttons row ── */}
  <div style={{ display: "flex", alignItems: "center", borderBottom: "1px solid rgba(255,255,255,0.07)", background: "#12151f", minHeight: 42, marginBottom:14 }}>
    {tabs.length > 0 && (
      <div className="tabs-scroll-container"
        onWheel={(e) => { if (e.deltaY !== 0) { e.currentTarget.scrollLeft += e.deltaY; } }}
        style={{ flex: 1, display: "flex", alignItems: "center", overflowX: "auto", overflowY: "hidden", gap: 2, padding: "4px 8px 8px 8px", minWidth: 0, cursor: "grab" }}>
        {tabs.map((tab, i) => (
          <button key={tab.id}
            onClick={() => { setActiveIdx(i); if (onTabChange) onTabChange(tab.id); }}
            style={{ flexShrink: 0, padding: "10px 18px", fontSize: 13, fontWeight: displayIdx === i ? 600 : 400, color: displayIdx === i ? "#1FA8C9" : "#64748b", background: "transparent", border: "none", borderBottom: displayIdx === i ? "2px solid #1FA8C9" : "2px solid transparent", cursor: "pointer", whiteSpace: "nowrap", transition: "color 0.15s, border-color 0.15s" }}>
            {tab.name}
          </button>
        ))}
      </div>
    )}
  </div>

  {/* ── Date picker row — separate from tab scroll ── */}
  {/* {hasTimeFilter && (
    <div style={{ background: "#12151f", borderBottom: "1px solid rgba(255,255,255,0.07)", padding: "8px 12px", display: "flex", justifyContent: "flex-end", marginBottom: 14 }}>
      <DateRangePicker
        dateFrom={dateFrom}
        dateTo={dateTo}
        onFromChange={setDateFrom}
        onToChange={setDateTo}
        onClear={() => { setDateFrom(null); setDateTo(null); }}
        dataDateRange={dataDateRange}
      />
    </div>
  )} */}

    

  {/* ── If no time filter, still add bottom margin ── */}
  {!hasTimeFilter && <div style={{ marginBottom: 14 }} />}
</div>

      {activeTab?.rows?.length > 0 && renderRows(activeTab.rows)}

      {activeTab?.nestedTabsSection && (
        <TabGroup
          tabs={activeTab.nestedTabsSection.tabs}
          chartMap={chartMap} cardProps={cardProps} isMobile={isMobile} renderRows={renderRows}
          onTabChange={onTabChange} pdfTabIdx={pdfNestedTabIdx} pdfNestedTabIdx={null}
          dateFrom={dateFrom} dateTo={dateTo} setDateFrom={setDateFrom} setDateTo={setDateTo}
          dataDateRange={dataDateRange}
          hasTimeFilter={hasTimeFilter}
        />
      )}

      {tabs.length > 0 && !hasContent && (
        <div style={{ padding: "40px 0", textAlign: "center", color: "#374151", fontSize: 13 }}>No charts in this tab</div>
      )}
    </div>
  );
}

// ── Filter dropdown ─────────────────────────────────────────
function FilterDropdown({ fd, activeFilters, dateFrom, dateTo, onFilterChange, onDateFromChange, onDateToChange }) {
  const [open,   setOpen]   = useState(false);
  const [search, setSearch] = useState("");
  const [draftFrom, setDraftFrom] = useState("");
  const [draftTo,   setDraftTo]   = useState("");
  const ref = useRef(null);

  useEffect(() => {
    if (!open) return;
    const fn = (e) => { if (ref.current && !ref.current.contains(e.target)) { setOpen(false); setSearch(""); } };
    document.addEventListener("mousedown", fn);
    return () => document.removeEventListener("mousedown", fn);
  }, [open]);

  const rawVal       = activeFilters[fd.column];
  const selectedVals = Array.isArray(rawVal) ? rawVal : (rawVal ? [rawVal] : []);
  const hasSelection = fd.type === "date" ? !!dateFrom : selectedVals.length > 0;
  const selCount     = selectedVals.length;
  const displayed    = fd.type === "select" ? (fd.values || []).filter(v => !search.trim() || String(v).toLowerCase().includes(search.toLowerCase())) : [];

  const handleClearAll = (e) => {
    e?.stopPropagation();
    if (fd.type === "date") { onDateFromChange?.(""); onDateToChange?.(""); }
    else selectedVals.forEach(v => onFilterChange?.(fd.column, v));
  };
  const handleToggle    = (val) => onFilterChange?.(fd.column, val);
  const handleSelectAll = () => displayed.forEach(v => { if (!selectedVals.includes(v)) onFilterChange?.(fd.column, v); });
  const isAllSelected   = displayed.length > 0 && displayed.every(v => selectedVals.includes(v));

  return (
    <div ref={ref} style={{ position: "relative", flexShrink: 0 }}>
      {/* <button onClick={() => { setOpen(p => !p); setSearch(""); }} */}
      <button onClick={() => {
            const opening = !open;
            setOpen(p => !p);
            setSearch("");
            if (opening) {
              setDraftFrom(dateFrom || "");
              setDraftTo(dateTo || "");
            }
          }}
        style={{ display: "flex", alignItems: "center", gap: 6, padding: "6px 12px", borderRadius: 8, fontSize: 12, fontWeight: hasSelection ? 700 : 500, border: `1px solid ${hasSelection ? "rgba(31,168,201,0.55)" : open ? "rgba(255,255,255,0.18)" : "rgba(255,255,255,0.09)"}`, background: hasSelection ? "rgba(31,168,201,0.13)" : open ? "rgba(255,255,255,0.07)" : "rgba(255,255,255,0.03)", color: hasSelection ? "#1FA8C9" : "#94a3b8", cursor: "pointer", outline: "none", whiteSpace: "nowrap", userSelect: "none", transition: "all .15s" }}>
        <span>{fd.name}</span>
        {selCount > 0 && <span style={{ fontSize: 9, background: "#1FA8C9", color: "#fff", borderRadius: 8, padding: "1px 6px", fontWeight: 700, lineHeight: 1.5, flexShrink: 0 }}>{selCount}</span>}
        {hasSelection
          ? <X size={11} onClick={handleClearAll} style={{ color: "#1FA8C9", cursor: "pointer", flexShrink: 0 }} />
          : <ChevronDown size={11} style={{ color: open ? "#94a3b8" : "#475569", transform: open ? "rotate(180deg)" : "rotate(0deg)", transition: "transform .15s", flexShrink: 0 }} />}
      </button>

      {open && (
        <div style={{ position: "absolute", top: "calc(100% + 6px)", left: 0, minWidth: 240, maxWidth: 380, background: "#181b24", border: "1px solid rgba(255,255,255,0.1)", borderRadius: 10, boxShadow: "0 16px 48px rgba(0,0,0,0.65)", zIndex: 500, overflow: "hidden" }}>
          <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", padding: "9px 14px 8px", borderBottom: "1px solid rgba(255,255,255,0.06)" }}>
            <div style={{ display: "flex", alignItems: "center", gap: 7 }}>
              <span style={{ fontSize: 11, fontWeight: 700, color: "#cbd5e1", textTransform: "uppercase", letterSpacing: "0.07em" }}>{fd.name}</span>
              {selCount > 0 && <span style={{ fontSize: 10, color: "#1FA8C9", fontWeight: 600 }}>{selCount} selected</span>}
            </div>
            <div style={{ display: "flex", gap: 10 }}>
              {fd.type === "select" && <button onClick={isAllSelected ? handleClearAll : handleSelectAll} style={{ fontSize: 10, color: "#64748b", background: "none", border: "none", cursor: "pointer", padding: 0 }} onMouseEnter={e => e.currentTarget.style.color = "#1FA8C9"} onMouseLeave={e => e.currentTarget.style.color = "#64748b"}>{isAllSelected ? "Deselect all" : "Select all"}</button>}
              {hasSelection && <button onClick={handleClearAll} style={{ fontSize: 10, color: "#64748b", background: "none", border: "none", cursor: "pointer", padding: 0 }} onMouseEnter={e => e.currentTarget.style.color = "#f87171"} onMouseLeave={e => e.currentTarget.style.color = "#64748b"}>Clear</button>}
            </div>
          </div>

          {/* {fd.type === "date" && (
            <div style={{ padding: "12px 14px", display: "flex", flexDirection: "column", gap: 10 }}>
              {[["From", dateFrom, onDateFromChange], ["To", dateTo, onDateToChange]].map(([label, val, setter]) => (
                <div key={label}>
                  <p style={{ fontSize: 10, color: "#475569", marginBottom: 5, fontWeight: 600, textTransform: "uppercase", letterSpacing: "0.06em" }}>{label}</p>
                  <input type="date" value={val} onChange={e => setter?.(e.target.value)} style={{ background: "#0d1117", border: "1px solid #2d3748", borderRadius: 6, padding: "6px 10px", fontSize: 11, color: "#94a3b8", width: "100%", outline: "none", cursor: "pointer" }} />
                </div>
              ))}
            </div>
          )} */}
          {fd.type === "date" && (
            <div style={{ padding: "12px 14px", display: "flex", flexDirection: "column", gap: 10 }}>
              <div>
                <p style={{ fontSize: 10, color: "#475569", marginBottom: 5, fontWeight: 600, textTransform: "uppercase", letterSpacing: "0.06em" }}>From</p>
                <input
                  type="date"
                  onClick={(e) => e.currentTarget.showPicker?.()}
                  value={draftFrom}
                  onChange={e => setDraftFrom(e.target.value)}
                  style={{ background: "#0d1117", border: "1px solid #2d3748", borderRadius: 6, padding: "6px 10px", fontSize: 11, color: "#94a3b8", width: "100%", outline: "none", cursor: "pointer" }}
                />
              </div>
              <div>
                <p style={{ fontSize: 10, color: "#475569", marginBottom: 5, fontWeight: 600, textTransform: "uppercase", letterSpacing: "0.06em" }}>To</p>
                <input
                  type="date"
                  onClick={(e) => e.currentTarget.showPicker?.()}
                  value={draftTo}
                  onChange={e => setDraftTo(e.target.value)}
                  style={{ background: "#0d1117", border: "1px solid #2d3748", borderRadius: 6, padding: "6px 10px", fontSize: 11, color: "#94a3b8", width: "100%", outline: "none", cursor: "pointer" }}
                />
              </div>
              <button
                disabled={!draftFrom || !draftTo}
                onClick={() => {
                  if (draftFrom && draftTo) {
                    onDateFromChange?.(draftFrom);
                    onDateToChange?.(draftTo);
                    setOpen(false);
                  }
                }}
                style={{
                  marginTop: 4,
                  padding: "7px 0",
                  borderRadius: 7,
                  fontSize: 12,
                  fontWeight: 600,
                  cursor: (draftFrom && draftTo) ? "pointer" : "not-allowed",
                  border: `1px solid ${(draftFrom && draftTo) ? "rgba(31,168,201,0.5)" : "rgba(255,255,255,0.08)"}`,
                  background: (draftFrom && draftTo) ? "rgba(31,168,201,0.15)" : "rgba(255,255,255,0.03)",
                  color: (draftFrom && draftTo) ? "#1FA8C9" : "#374151",
                  width: "100%",
                  transition: "all 0.15s",
                }}>
                🔍 Apply
              </button>
            </div>
          )}

          {fd.type === "select" && (
            <>
              {fd.values.length > 8 && (
                <div style={{ padding: "8px 12px 6px", borderBottom: "1px solid rgba(255,255,255,0.05)" }}>
                  <input autoFocus placeholder={`Search ${fd.name.toLowerCase()}…`} value={search} onChange={e => setSearch(e.target.value)} style={{ width: "100%", background: "rgba(255,255,255,0.05)", border: "1px solid rgba(255,255,255,0.09)", borderRadius: 6, padding: "5px 10px", fontSize: 11, color: "#e2e8f0", outline: "none" }} />
                </div>
              )}
              {selCount > 0 && !search && (
                <div style={{ padding: "8px 12px 6px", borderBottom: "1px solid rgba(255,255,255,0.05)", display: "flex", flexWrap: "wrap", gap: 4 }}>
                  {selectedVals.map(v => (
                    <span key={v} style={{ display: "flex", alignItems: "center", gap: 3, padding: "3px 8px", borderRadius: 14, fontSize: 10, fontWeight: 700, background: "rgba(31,168,201,0.2)", color: "#1FA8C9", border: "1px solid rgba(31,168,201,0.4)" }}>
                      {v}<X size={9} style={{ cursor: "pointer", opacity: 0.7 }} onClick={() => handleToggle(v)} />
                    </span>
                  ))}
                </div>
              )}
              <div style={{ padding: "8px 12px 10px", maxHeight: 200, overflowY: "auto", scrollbarWidth: "thin", scrollbarColor: "#2d3748 transparent", display: "flex", flexWrap: "wrap", gap: 5 }}>
                {displayed.length === 0 && <span style={{ fontSize: 11, color: "#374151", padding: "4px 2px" }}>No results</span>}
                {displayed.map(val => {
                  const active = selectedVals.includes(val);
                  return (
                    <button key={val} onClick={() => handleToggle(val)} style={{ display: "flex", alignItems: "center", gap: 4, padding: "4px 10px", borderRadius: 16, fontSize: 11, fontWeight: 600, cursor: "pointer", border: `1px solid ${active ? "#1FA8C9" : "rgba(31,168,201,0.2)"}`, background: active ? "#1FA8C9" : "rgba(31,168,201,0.07)", color: active ? "#fff" : "#5ba8b9", outline: "none", transition: "all .12s ease" }}>
                      {active && <Check size={9} />}{val}
                    </button>
                  );
                })}
              </div>
              <div style={{ padding: "5px 14px 8px", fontSize: 10, color: "#374151", borderTop: "1px solid rgba(255,255,255,0.04)", display: "flex", justifyContent: "space-between" }}>
                <span>{fd.values.length} option{fd.values.length !== 1 ? "s" : ""}{search ? ` · ${displayed.length} matching` : ""}</span>
                {selCount > 0 && <span style={{ color: "#1FA8C9", fontWeight: 600 }}>{selCount} selected</span>}
              </div>
            </>
          )}
        </div>
      )}
    </div>
  );
}

// ── Filter panel ────────────────────────────────────────────
function FilterPanel({ filterDefs, activeFilters, dateFrom, dateTo, onFilterChange, onDateFromChange, onDateToChange, onReset }) {
  if (!filterDefs?.length) return null;
  const activeCount = Object.values(activeFilters).reduce((acc, v) => acc + (Array.isArray(v) ? v.length : (v ? 1 : 0)), 0) + (dateFrom ? 1 : 0);
  const hasActive   = activeCount > 0;
  return (
    <div style={{ background: "#12151f", border: "1px solid rgba(255,255,255,0.07)", borderRadius: 10, marginBottom: 14, padding: "10px 14px" }}>
      <div style={{ display: "flex", alignItems: "center", flexWrap: "wrap", gap: 8 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 7, flexShrink: 0 }}>
          <SlidersHorizontal size={13} style={{ color: "#475569" }} />
          <span style={{ fontSize: 11, fontWeight: 700, color: "#475569", letterSpacing: "0.09em", textTransform: "uppercase" }}>Filters</span>
          {hasActive && <span style={{ fontSize: 9, background: "#1FA8C9", color: "#fff", borderRadius: 8, padding: "1px 6px", fontWeight: 700 }}>{activeCount}</span>}
        </div>
        <div style={{ width: 1, height: 18, background: "rgba(255,255,255,0.08)", flexShrink: 0 }} />
        {filterDefs.map(fd => (
          <FilterDropdown key={fd.id} fd={fd} activeFilters={activeFilters} dateFrom={dateFrom} dateTo={dateTo} onFilterChange={onFilterChange} onDateFromChange={onDateFromChange} onDateToChange={onDateToChange} />
        ))}
        {hasActive && (
          <>
            <div style={{ width: 1, height: 18, background: "rgba(255,255,255,0.08)", flexShrink: 0 }} />
            <button onClick={onReset} style={{ display: "flex", alignItems: "center", gap: 5, padding: "5px 11px", borderRadius: 7, fontSize: 11, fontWeight: 600, border: "1px solid rgba(239,68,68,0.28)", color: "#f87171", background: "rgba(239,68,68,0.06)", cursor: "pointer", flexShrink: 0, outline: "none", transition: "all .15s" }} onMouseEnter={e => { e.currentTarget.style.background = "rgba(239,68,68,0.12)"; e.currentTarget.style.borderColor = "rgba(239,68,68,0.5)"; }} onMouseLeave={e => { e.currentTarget.style.background = "rgba(239,68,68,0.06)"; e.currentTarget.style.borderColor = "rgba(239,68,68,0.28)"; }}>
              <RotateCcw size={10} /> Reset
            </button>
          </>
        )}
      </div>
    </div>
  );
}

// ── Active pills ────────────────────────────────────────────
function ActivePills({ activeFilters, dateFrom, dateTo, onRemove, onRemoveDate }) {
  const pills = [];
  for (const [col, val] of Object.entries(activeFilters)) {
    if (!val) continue;
    const vals = Array.isArray(val) ? val : [val];
    vals.forEach(v => pills.push({ col, val: v }));
  }
  if (!pills.length && !dateFrom) return null;
  return (
    <div style={{ display: "flex", flexWrap: "wrap", gap: 6, marginBottom: 14, alignItems: "center" }}>
      <span style={{ fontSize: 9, color: "#374151", fontWeight: 700, letterSpacing: "0.09em", textTransform: "uppercase" }}>Active:</span>
      {pills.map(({ col, val }) => (
        <span key={`${col}:${val}`} style={{ display: "flex", alignItems: "center", gap: 5, fontSize: 11, background: "rgba(31,168,201,0.12)", color: "#67c5d8", border: "1px solid rgba(31,168,201,0.22)", padding: "3px 8px 3px 10px", borderRadius: 16 }}>
          <span style={{ color: "#4a5568", fontSize: 9 }}>{col}:</span>&nbsp;{val}
          <button onClick={() => onRemove(col, val)} style={{ background: "none", border: "none", color: "#64748b", cursor: "pointer", padding: 0, display: "flex", alignItems: "center" }}><X size={10} /></button>
        </span>
      ))}
      {dateFrom && dateTo && (
        <span style={{ display: "flex", alignItems: "center", gap: 5, fontSize: 11, background: "rgba(139,92,246,0.12)", color: "#a78bfa", border: "1px solid rgba(139,92,246,0.22)", padding: "3px 8px 3px 10px", borderRadius: 16 }}>
          {dateFrom} → {dateTo}
          <button onClick={onRemoveDate} style={{ background: "none", border: "none", color: "#64748b", cursor: "pointer", padding: 0, display: "flex", alignItems: "center" }}><X size={10} /></button>
        </span>
      )}
    </div>
  );
}

// ══════════════════════════════════════════════════════════════
//  MAIN COMPONENT
// ══════════════════════════════════════════════════════════════
export default function DashboardChartsPage({ dashboardNumericId, dashboardTitle, onPdfReady }) {

  // ── State ─────────────────────────────────────────────────
  const [charts,          setCharts]          = useState([]);
  const [sections,        setSections]        = useState(null);
  const [filterDefs,      setFilterDefs]      = useState([]);
  const [activeFilters,   setActiveFilters]   = useState({});
  const [loading,         setLoading]         = useState(true);
  const [error,           setError]           = useState(null);
  const [crossFilters,    setCrossFilters]    = useState({});
  const [dataDateRange,   setDataDateRange]   = useState({ min: null, max: null });
  const [dateFrom,        setDateFrom]        = useState(null);
  const [dateTo,          setDateTo]          = useState(null);
  const [hasTimeFilter,   setHasTimeFilter]   = useState(false);
  const [timeFilterId,    setTimeFilterId]    = useState(null);
  const [activeTabId,     setActiveTabId]     = useState(null);
  const [isPdfLoading,    setIsPdfLoading]    = useState(false); // eslint-disable-line no-unused-vars
  const [pdfTabIdx,       setPdfTabIdx]       = useState(null);
  const [pdfNestedTabIdx, setPdfNestedTabIdx] = useState(null);
  const [pdfProgress,     setPdfProgress]     = useState(null);

  // ── Refs ──────────────────────────────────────────────────
  const dashboardContentRef = useRef(null);
  const pdfResolveRef       = useRef(null);
  const isPdfLoadingRef     = useRef(false);
  const sectionsRef         = useRef(null);
  const downloadRef         = useRef(null);

  const windowWidth = useWindowWidth();
  const isMobile    = windowWidth < 768;

  // ── Refs for PDF (snapshot of state at PDF click time) ────
  const [tenantLogoUrl, setTenantLogoUrl] = useState(null);
  const tenantLogoRef    = useRef(null);
  const dashboardTitleRef  = useRef(null);
  const activeFiltersRef = useRef({});
  const crossFiltersRef  = useRef({});
  const dateFromRef      = useRef(null);
  const dateToRef        = useRef(null);
  const filterDefsRef    = useRef([]);

  // pop-up State
  const [crossFilterWarning, setCrossFilterWarning] = useState(null);

  // cross-filter scoping state
const [crossFilterScopeMap, setCrossFilterScopeMap] = useState({}); // { chartId -> [chartIds] }
const [crossFiltersEnabled, setCrossFiltersEnabled] = useState(false);


  // ── Keep refs in sync with state ──────────────────────────
  useEffect(() => { sectionsRef.current      = sections;      }, [sections]);
  useEffect(() => { tenantLogoRef.current    = tenantLogoUrl; }, [tenantLogoUrl]);
  useEffect(() => { dashboardTitleRef.current  = dashboardTitle; }, [dashboardTitle]);
  useEffect(() => { activeFiltersRef.current = activeFilters; }, [activeFilters]);
  useEffect(() => { crossFiltersRef.current  = crossFilters;  }, [crossFilters]);
  useEffect(() => { dateFromRef.current      = dateFrom;      }, [dateFrom]);
  useEffect(() => { dateToRef.current        = dateTo;        }, [dateTo]);
  useEffect(() => { filterDefsRef.current    = filterDefs;    }, [filterDefs]);  // ← ADD THIS LINE

  // ── Fetch tenant logo for PDF header ──────────────────────
  useEffect(() => {
    api.get("/branding")
      .then(r => { if (r.data?.logo_url) setTenantLogoUrl(r.data.logo_url); })
      .catch(() => {});
  }, []);

  // ── Callbacks ─────────────────────────────────────────────
  const handleDateRangeDetected = useCallback((minDate, maxDate) => {
    setDataDateRange(prev => ({
      min: !prev.min || minDate < prev.min ? minDate : prev.min,
      max: !prev.max || maxDate > prev.max ? maxDate : prev.max,
    }));
  }, []);

  const handleFilterChange = useCallback((col, val) => {
    setActiveFilters(prev => {
      const current = Array.isArray(prev[col]) ? prev[col] : (prev[col] ? [prev[col]] : []);
      const exists  = current.includes(val);
      const updated = exists ? current.filter(v => v !== val) : [...current, val];
      if (updated.length === 0) { const next = { ...prev }; delete next[col]; return next; }
      return { ...prev, [col]: updated };
    });
  }, []);

  const handleReset = useCallback(() => {
  setActiveFilters({});
  setDateFrom(null);
  setDateTo(null);
}, []);

  const handleCrossFilter = useCallback((column, value, sourceChartId, sourceChartTitle, fromTable = false, chartsInScope = null) => {
    const normalizedScope = chartsInScope ? chartsInScope.map(Number) : null;
    setCrossFilters(prev => {
      if (!value) { const next = { ...prev }; delete next[column]; return next; }
      return { ...prev, [column]: { value, sourceChartId, sourceChartTitle, fromTable, chartsInScope: normalizedScope } };
    });
  }, []);

  const clearCrossFilter     = useCallback((col) => setCrossFilters(prev => { const n = { ...prev }; delete n[col]; return n; }), []);
  const clearAllCrossFilters = useCallback(() => setCrossFilters({}), []);

  // ── PDF tab change resolver ───────────────────────────────
  useEffect(() => {
    if (pdfResolveRef.current) {
      const resolve = pdfResolveRef.current;
      pdfResolveRef.current = null;
      setTimeout(resolve, 8000);
    }
  }, [pdfTabIdx, pdfNestedTabIdx]);

  // ── PDF download ──────────────────────────────────────────
  const downloadDashboardPDF = useCallback(async () => {
    if (isPdfLoadingRef.current || !dashboardContentRef.current) return;
    isPdfLoadingRef.current = true;
    setIsPdfLoading(true);

    try {
      const [{ default: jsPDF }, { default: html2canvas }] = await Promise.all([
        import("jspdf"),
        import("html2canvas"),
      ]);

      const pdf   = new jsPDF({ orientation: "landscape", unit: "mm", format: "a4" });
      const pageW = pdf.internal.pageSize.getWidth();
      const pageH = pdf.internal.pageSize.getHeight();
      const HDR   = 18;
      const FTR   = 11;

      // ── Snapshot all filter state at the moment Download is clicked ──
      // Nothing will change these during PDF generation.
      // What the user had active = what shows in the PDF.
      const snapshotFilters     = { ...activeFiltersRef.current };
      const snapshotCrossFilters = { ...crossFiltersRef.current };
      const snapshotDateFrom    = dateFromRef.current;
      const snapshotDateTo      = dateToRef.current;


      // ── ADD THIS BLOCK HERE ───────────────────────────────────────────
      const applyTabScopedFilters = (tabId) => {
        if (!tabId) return;
        const scopedFilters = {};
        for (const [col, val] of Object.entries(snapshotFilters)) {
          const filterDef = filterDefsRef.current.find(fd => fd.column === col);
          const inScope = (
            !filterDef ||
            !filterDef.tabsInScope?.length ||
            filterDef.tabsInScope.includes(tabId)
          );
          if (inScope) scopedFilters[col] = val;
        }
        setActiveFilters(scopedFilters);
      };
      // ─────────────────────────────────────────────────────────────────




      // ── Build filter text from snapshot ───────────────────────────────
      // Simple: just show whatever was active when user clicked Download.
      // No chartsInScope checking. No tab scoping. Just show as-is.
      // ── Build filter text ─────────────────────────────────────────────
      // const buildFilterText = () => {
      //   const parts = [];

      //   // Panel filters — already scoped by applyTabScopedFilters
      //   const af = { ...activeFiltersRef.current };
      //   for (const [col, val] of Object.entries(af)) {
      //     if (!val) continue;
      //     const vals = Array.isArray(val) ? val : [val];
      //     if (vals.length) parts.push(`${col}: ${vals.join(", ")}`);
      //   }

      //   // Cross-filters
      //   for (const [col, filter] of Object.entries(snapshotCrossFilters)) {
      //     if (filter?.value) parts.push(`${col}: ${filter.value}`);
      //   }

      //   // Date range
      //   if (snapshotDateFrom && snapshotDateTo)
      //     parts.push(`Date: ${snapshotDateFrom} → ${snapshotDateTo}`);
      //   else if (snapshotDateFrom)
      //     parts.push(`From: ${snapshotDateFrom}`);
      //   else if (snapshotDateTo)
      //     parts.push(`To: ${snapshotDateTo}`);

      //   return parts.length ? `Filters: ${parts.join("  |  ")}` : "";
      // };

      const buildFilterParts = () => {
        const parts = [];

        // Panel filters — already scoped by applyTabScopedFilters
        const af = { ...activeFiltersRef.current };
        for (const [col, val] of Object.entries(af)) {
          if (!val) continue;
          const vals = Array.isArray(val) ? val : [val];
          if (vals.length) parts.push(`${col}: ${vals.join(", ")}`);
        }

        // Cross-filters
        for (const [col, filter] of Object.entries(snapshotCrossFilters)) {
          if (filter?.value) parts.push(`${col}: ${filter.value}`);
        }

        // Date range
        if (snapshotDateFrom && snapshotDateTo)
          parts.push(`${snapshotDateFrom} → ${snapshotDateTo}`);
        else if (snapshotDateFrom)
          parts.push(`From ${snapshotDateFrom}`);
        else if (snapshotDateTo)
          parts.push(`To ${snapshotDateTo}`);

        return parts;
      };

      // ── Load logos ─────────────────────────────────────────────────────
      const loadImg = (url) => new Promise((resolve) => {
        if (!url) return resolve(null);
        const img = new Image();
        img.crossOrigin = "anonymous";
        img.onload = () => {
          try {
            const c = document.createElement("canvas");
            c.width = img.naturalWidth; c.height = img.naturalHeight;
            c.getContext("2d").drawImage(img, 0, 0);
            resolve(c.toDataURL("image/png"));
          } catch { resolve(null); }
        };
        img.onerror = () => resolve(null);
        img.src = url;
      });

      const tenantLogoB64   = await loadImg(tenantLogoRef.current);
      console.log("DEBUG tenantLogoUrl:", tenantLogoRef.current, "| loaded base64:", tenantLogoB64 ? "SUCCESS" : "FAILED");
      const speegileLogoB64 = await loadImg("/speegile-logo.png");
      const downloadDate    = new Date().toLocaleDateString("en-IN", {
        day: "2-digit", month: "short", year: "numeric"
      });

      // ── Screenshot ─────────────────────────────────────────────────────
      const capture = () => html2canvas(dashboardContentRef.current, {
        scale:           3,
        useCORS:         true,
        allowTaint:      true,
        backgroundColor: "#0d1117",
        logging:         false,
        imageTimeout:    0,
        onclone: (doc) => {
          doc.querySelectorAll("svg").forEach(s => { s.style.overflow = "visible"; });
          // Replace date inputs with readable spans
          doc.querySelectorAll('input[type="date"]').forEach(input => {
            const val  = input.value;
            const span = doc.createElement("span");
            span.style.cssText = `
              display: inline-block;
              background: #12151f;
              border: 1px solid ${val ? "#1FA8C9" : "rgba(255,255,255,0.1)"};
              border-radius: 6px;
              padding: 4px 10px;
              color: ${val ? "#e2e8f0" : "#64748b"};
              font-size: 11px;
              font-family: inherit;
              min-width: 90px;
            `;
            if (val) {
              try {
                span.textContent = new Date(val).toLocaleDateString("en-IN", {
                  day: "2-digit", month: "short", year: "numeric"
                });
              } catch { span.textContent = val; }
            } else {
              span.textContent = "dd-mm-yyyy";
            }
            input.parentNode?.replaceChild(span, input);
          });
        },
      });

      // ── Add one page to PDF ─────────────────────────────────────────────
      // const addPage = (canvas, tabName, isFirst, pageNum, totalPages) => {
      //   if (!isFirst) pdf.addPage();

      //   const filterText = buildFilterText();
      //   const filterH    = filterText ? 7 : 0;
      //   const topOffset  = HDR + filterH;
      //   const margin     = 2;
      //   const availW     = pageW - margin * 2;
      //   const availH     = pageH - topOffset - FTR - margin;
      //   const aspect     = canvas.width / canvas.height;
      //   const img        = canvas.toDataURL("image/jpeg", 0.98);

      //   // Background
      //   pdf.setFillColor(13, 17, 23);
      //   pdf.rect(0, 0, pageW, pageH, "F");

      //   // Chart screenshot
      //   let w, h, x, y;
      //   if (aspect > availW / availH) {
      //     w = availW; h = availW / aspect; x = margin; y = topOffset + margin;
      //   } else {
      //     h = availH; w = availH * aspect;
      //     x = margin + (availW - w) / 2; y = topOffset + margin;
      //   }
      //   pdf.addImage(img, "JPEG", x, y, w, h);

      //   // Header strip
      //   pdf.setFillColor(18, 21, 31);
      //   pdf.rect(0, 0, pageW, HDR, "F");
      //   pdf.setDrawColor(45, 55, 72);
      //   pdf.setLineWidth(0.3);
      //   pdf.line(0, HDR, pageW, HDR);

      //   // Tenant logo left
      //   let logoDrawn = false;
      //   if (tenantLogoB64) {
      //     try { pdf.addImage(tenantLogoB64, "PNG", 6, 3, 0, 12); logoDrawn = true; }
      //     catch { logoDrawn = false; }
      //   }
      //   if (!logoDrawn) {
      //     pdf.setFont("helvetica", "bold"); pdf.setFontSize(11);
      //     pdf.setTextColor(255, 255, 255);
      //     pdf.text("Dashboard", 8, 11.5);
      //   }

      //   // Tab name right
      //   if (tabName) {
      //     pdf.setFont("helvetica", "normal"); pdf.setFontSize(9);
      //     pdf.setTextColor(203, 213, 225);
      //     pdf.text(tabName, pageW - 8, 11.5, { align: "right" });
      //   }

      //   // Filter strip — shows what filters were active at download time
      //   if (filterText) {
      //     pdf.setFillColor(15, 20, 30);
      //     pdf.rect(0, HDR, pageW, filterH, "F");
      //     pdf.setDrawColor(31, 50, 70);
      //     pdf.setLineWidth(0.2);
      //     pdf.line(0, HDR + filterH, pageW, HDR + filterH);
      //     pdf.setFont("helvetica", "normal"); pdf.setFontSize(7);
      //     pdf.setTextColor(100, 148, 180);
      //     const txt = filterText.length > 160
      //       ? filterText.slice(0, 160) + "..."
      //       : filterText;
      //     pdf.text(txt, 8, HDR + filterH - 1.5);
      //   }

      //   // Footer strip
      //   const footerY = pageH - FTR;
      //   pdf.setFillColor(18, 21, 31);
      //   pdf.rect(0, footerY, pageW, FTR, "F");
      //   pdf.setDrawColor(45, 55, 72);
      //   pdf.setLineWidth(0.3);
      //   pdf.line(0, footerY, pageW, footerY);

      //   let footerLogoDrawn = false;
      //   if (speegileLogoB64) {
      //     try { pdf.addImage(speegileLogoB64, "PNG", 6, footerY + 1.5, 0, 6); footerLogoDrawn = true; }
      //     catch { footerLogoDrawn = false; }
      //   }
      //   if (!footerLogoDrawn) {
      //     pdf.setFont("helvetica", "bold"); pdf.setFontSize(7);
      //     pdf.setTextColor(31, 168, 201);
      //     pdf.text("Speegile Analytics", 6, footerY + 6.5);
      //   }

      //   pdf.setFont("helvetica", "normal"); pdf.setFontSize(7.5);
      //   pdf.setTextColor(100, 116, 139);
      //   pdf.text(`Downloaded: ${downloadDate}`, pageW / 2, footerY + 6.5, { align: "center" });
      //   pdf.text(`Page ${pageNum} of ${totalPages}`, pageW - 8, footerY + 6.5, { align: "right" });
      // };

      // ── Gradient helper — draws a thin horizontal teal→slate→purple bar ──
      const drawGradientBar = (x, y, w, h) => {
        const stops = [
          [31, 168, 201],   // #1FA8C9 teal
          [69, 78, 124],    // #454E7C slate
          [168, 104, 183],  // #A868B7 purple
        ];
        const steps = 80;
        const segW  = w / steps;
        for (let i = 0; i < steps; i++) {
          const t = i / (steps - 1);
          let c;
          if (t < 0.5) {
            const lt = t / 0.5;
            c = stops[0].map((v, idx) => Math.round(v + (stops[1][idx] - v) * lt));
          } else {
            const lt = (t - 0.5) / 0.5;
            c = stops[1].map((v, idx) => Math.round(v + (stops[2][idx] - v) * lt));
          }
          pdf.setFillColor(c[0], c[1], c[2]);
          pdf.rect(x + segW * i, y, segW + 0.15, h, "F");
        }
      };

      // ── Add one page to PDF ─────────────────────────────────────────────
      const addPage = (canvas, tabName, isFirst, pageNum, totalPages) => {
        if (!isFirst) pdf.addPage();

        const filterParts = buildFilterParts();
        const filterH     = filterParts.length ? 8 : 0;
        const topOffset   = HDR + filterH;
        const margin      = 2;
        const availW      = pageW - margin * 2;
        const availH      = pageH - topOffset - FTR - margin;
        const aspect      = canvas.width / canvas.height;
        const img         = canvas.toDataURL("image/jpeg", 0.98);

        // Background
        pdf.setFillColor(13, 17, 23);
        pdf.rect(0, 0, pageW, pageH, "F");

        // Chart screenshot
        let w, h, x, y;
        if (aspect > availW / availH) {
          w = availW; h = availW / aspect; x = margin; y = topOffset + margin;
        } else {
          h = availH; w = availH * aspect;
          x = margin + (availW - w) / 2; y = topOffset + margin;
        }
        pdf.addImage(img, "JPEG", x, y, w, h);

        // ── Header strip ───────────────────────────────────────────────
        pdf.setFillColor(18, 21, 31);
        pdf.rect(0, 0, pageW, HDR, "F");

        // Tenant logo — top-left corner badge, out of the way of centered text
        // if (tenantLogoRef.current) {
        //   try { pdf.addImage(tenantLogoRef.current, "PNG", 5, 4, 0, 10); } catch {}
        // }
        // Tenant logo — top-left corner badge, out of the way of centered text
        if (tenantLogoB64) {
          try { pdf.addImage(tenantLogoB64, "PNG", 5, 4, 0, 10); } catch {}
        }

        // Dashboard name — centered, bold, teal (row 1)
        pdf.setFont("helvetica", "bold");
        pdf.setFontSize(13);
        pdf.setTextColor(31, 168, 201);
        pdf.text(dashboardTitleRef.current || "Dashboard", pageW / 2, 10, { align: "center" });

        // Tab name — centered, muted, directly beneath (row 2)
        if (tabName) {
          pdf.setFont("helvetica", "normal");
          pdf.setFontSize(9);
          pdf.setTextColor(148, 163, 184);
          pdf.text(tabName, pageW / 2, 16.5, { align: "center" });
        }

        // Gradient accent line closing off the header
        drawGradientBar(0, HDR - 0.7, pageW, 0.7);

        // ── Filter strip — pill-style chips ──────────────────────────────
        if (filterParts.length) {
          pdf.setFillColor(15, 20, 30);
          pdf.rect(0, HDR, pageW, filterH, "F");

          pdf.setFont("helvetica", "normal");
          pdf.setFontSize(7);

          let chipX = 6;
          const chipY = HDR + 1.7;
          const chipH = 4.8;
          const maxX  = pageW - 6;

          for (const part of filterParts) {
            const textW = pdf.getTextWidth(part);
            const chipW = textW + 6;
            if (chipX + chipW > maxX) break; // simple overflow guard
            pdf.setFillColor(20, 45, 58);
            pdf.setDrawColor(31, 168, 201);
            pdf.setLineWidth(0.15);
            pdf.roundedRect(chipX, chipY, chipW, chipH, 1.4, 1.4, "FD");
            pdf.setTextColor(103, 197, 216);
            pdf.text(part, chipX + 3, chipY + 3.4);
            chipX += chipW + 3;
          }

          pdf.setDrawColor(31, 50, 70);
          pdf.setLineWidth(0.2);
          pdf.line(0, HDR + filterH, pageW, HDR + filterH);
        }

        // ── Footer strip ────────────────────────────────────────────────
        const footerY = pageH - FTR;

        // Gradient accent line above footer
        drawGradientBar(0, footerY, pageW, 0.6);

        pdf.setFillColor(18, 21, 31);
        pdf.rect(0, footerY + 0.6, pageW, FTR - 0.6, "F");

        let footerLogoDrawn = false;
        if (speegileLogoB64) {
          try { pdf.addImage(speegileLogoB64, "PNG", 6, footerY + 3, 0, 6); footerLogoDrawn = true; }
          catch { footerLogoDrawn = false; }
        }
        if (!footerLogoDrawn) {
          pdf.setFont("helvetica", "bold"); pdf.setFontSize(7);
          pdf.setTextColor(31, 168, 201);
          pdf.text("Speegile Analytics", 6, footerY + 7);
        }

        pdf.setFont("helvetica", "normal"); pdf.setFontSize(7.5);
        pdf.setTextColor(148, 163, 184);
        pdf.text(`Downloaded: ${downloadDate}`, pageW / 2, footerY + 7, { align: "center" });

        pdf.setFont("helvetica", "bold"); pdf.setFontSize(7.5);
        pdf.setTextColor(31, 168, 201);
        pdf.text(`Page ${pageNum} of ${totalPages}`, pageW - 8, footerY + 7, { align: "right" });
      };




      // ── Build tab list ──────────────────────────────────────────────────
      const currentSections = sectionsRef.current;
      const tabSection      = currentSections?.find(s => s.type === "tabs");
      const topLevelTabs    = tabSection?.tabs || [];
      const totalPages      = topLevelTabs.length === 0 ? 1 :
        topLevelTabs.reduce((acc, tab) =>
          acc + ((tab.nestedTabsSection?.tabs?.length || 0) > 1
            ? tab.nestedTabsSection.tabs.length : 1), 0);

      
      // ── Switch tab and apply only its scoped filters ──────────────────
      const switchAndWait = (ti, ni, tabName, pageNum) =>
        new Promise(resolve => {
          const tab = topLevelTabs[ti];

          // Apply filters scoped to this top-level tab
          applyTabScopedFilters(tab?.id);

          setPdfProgress({ current: pageNum, total: totalPages, tabName });
          pdfResolveRef.current = resolve;
          setPdfTabIdx(ti);
          setPdfNestedTabIdx(ni !== null && ni !== undefined ? ni : null);
        });



      // ── Loop through all tabs and capture ───────────────────────────────
      let isFirst = true, pagesDone = 0;

      if (topLevelTabs.length === 0) {
        setPdfProgress({ current: 0, total: 1, tabName: "Dashboard" });
        await new Promise(r => setTimeout(r, 8000));
        addPage(await capture(), "Dashboard", true, 1, 1);
      } else {
        for (let ti = 0; ti < topLevelTabs.length; ti++) {
          const topTab     = topLevelTabs[ti];
          const nestedTabs = topTab.nestedTabsSection?.tabs || [];

          if (nestedTabs.length <= 1) {
            const label = nestedTabs.length === 1
              ? `${topTab.name}  ›  ${nestedTabs[0].name}`
              : topTab.name;
            await switchAndWait(ti, null, label, pagesDone + 1);
            addPage(await capture(), label, isFirst, pagesDone + 1, totalPages);
            isFirst = false; pagesDone++;
          } else {
            for (let ni = 0; ni < nestedTabs.length; ni++) {
              const label = `${topTab.name}  ›  ${nestedTabs[ni].name}`;
              await switchAndWait(ti, ni, label, pagesDone + 1);
              addPage(await capture(), label, isFirst, pagesDone + 1, totalPages);
              isFirst = false; pagesDone++;
            }
          }
        }
      }

      setPdfTabIdx(null); setPdfNestedTabIdx(null); setPdfProgress(null);
      setActiveFilters(snapshotFilters);   // ← ADD: restore user's original filters
      pdf.save("speegile_dashboard.pdf");

    } catch (err) {
      console.error("PDF generation failed:", err);
    } finally {
      isPdfLoadingRef.current = false;
      setIsPdfLoading(false);
      setPdfTabIdx(null); setPdfNestedTabIdx(null); setPdfProgress(null);
    }
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  downloadRef.current = downloadDashboardPDF;

  // ── Register PDF handler with parent ──────────────────────
  useEffect(() => {
    if (onPdfReady) onPdfReady(() => () => downloadRef.current?.());
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  // ── Load dashboard data ───────────────────────────────────
  useEffect(() => {
    if (!dashboardNumericId) return;
    setLoading(true);
    setError(null);
    setActiveFilters({});
    setDateFrom(null);
    setDateTo(null);
    setHasTimeFilter(false);
    setTimeFilterId(null);
    setSections(null);
    setCrossFilters({});
    setDataDateRange({ min: null, max: null });

    Promise.all([
      api.get("/dashboard-charts", { params: { dashboardId: dashboardNumericId } }),
      api.get("/dashboard-layout",  { params: { dashboardId: dashboardNumericId } }).catch(() => null),
      api.get("/filter-options",    { params: { dashboardId: dashboardNumericId } }).catch(() => null),
      api.get("/dashboard-cross-filter-scope", { params: { dashboardId: dashboardNumericId } }).catch(() => null),
    ]).then(([cR, lR, fR, scR]) => {
      if (cR.data.success) setCharts(cR.data.charts.filter(c => c.viz_type !== "filter_box"));
      console.log("Loaded chart IDs:", cR.data.charts.map(c => c.slice_id)); // ← ADD
      if (lR?.data?.success) { const p = parseSupersetLayout(lR.data.layout); setSections(p); }
      // if (fR?.data?.success) setFilterDefs(fR.data.filters || []);
      if (fR?.data?.success) {
        setFilterDefs(fR.data.filters || []);
        console.log("📋 ALL FILTERS:", JSON.stringify(fR.data.filters, null, 2)); // ADD
        const timeFilt = (fR.data.filters || []).find(f => f.filterType === "filter_time");
        setHasTimeFilter(!!timeFilt);
        setTimeFilterId(timeFilt?.id || null);
        console.log("⏱ timeFilt:", JSON.stringify(timeFilt)); // ADD
      }
      setCrossFiltersEnabled(scR?.data?.enabled || false);
      setCrossFilterScopeMap(scR?.data?.scope   || {});

      console.log("crossFiltersEnabled:", scR?.data?.enabled);
      console.log("crossFilterScopeMap:", scR?.data?.scope);

    }).catch(() => setError("Failed to load dashboard."))
      .finally(() => setLoading(false));
  }, [dashboardNumericId]);

  // ── Early returns ─────────────────────────────────────────
  if (loading) return (
    <div style={{ display: "flex", alignItems: "center", justifyContent: "center", padding: "64px 0" }}>
      <Loader2 size={20} style={{ color: "#1FA8C9", animation: "spin .9s linear infinite" }} />
      <span style={{ marginLeft: 10, color: "#64748b", fontSize: 14 }}>Loading dashboard…</span>
      <style>{`@keyframes spin{from{transform:rotate(0)}to{transform:rotate(360deg)}}`}</style>
    </div>
  );
  if (error)          return <div style={{ textAlign: "center", padding: "64px 0", color: "#f87171",  fontSize: 13 }}>⚠ {error}</div>;
  if (!charts.length) return <div style={{ textAlign: "center", padding: "64px 0", color: "#374151", fontSize: 13 }}>No charts found.</div>;

  const chartMap = Object.fromEntries(charts.map(c => [c.slice_id, c]));

  // ── Card props ────────────────────────────────────────────
  const cardProps = (chart, chartHeightPx = 320) => {


    // const applicableCrossFilters = Object.fromEntries(
    //   Object.entries(crossFilters).filter(([, f]) => {
    //     // if (!f.chartsInScope) return true;
    //         if (!f.chartsInScope || f.chartsInScope.length === 0) return false;  // ← skip if no scope defined (means filter is meant for tables only)
    //     return f.chartsInScope.map(Number).includes(Number(chart.slice_id));
    //   })
    // );

//     const loadedChartIds = new Set(charts.map(c => Number(c.slice_id)));

// const applicableCrossFilters = Object.fromEntries(
//   Object.entries(crossFilters).filter(([, f]) => {
//     if (Number(f.sourceChartId) === Number(chart.slice_id)) return false;
//     if (!f.chartsInScope || f.chartsInScope.length === 0) return false;

//     const scope = f.chartsInScope.map(Number);
//     const anyOnThisDashboard = scope.some(id => loadedChartIds.has(id));

//     // Stale IDs — apply to all charts except source
//     if (!anyOnThisDashboard) return true;

//     // Valid scope — respect it
//     return scope.includes(Number(chart.slice_id));
//   })
// );
console.log("scopeMap at render:", crossFilterScopeMap, "enabled:", crossFiltersEnabled);

// const applicableCrossFilters = Object.fromEntries(
//   Object.entries(crossFilters).filter(([, f]) => {
//     // Never filter the emitter chart itself
//     if (Number(f.sourceChartId) === Number(chart.slice_id)) return false;

//     const sourceId = Number(f.sourceChartId);
//     const targetId = Number(chart.slice_id);

//     // If cross-filters are disabled on this dashboard, apply nothing
//     if (!crossFiltersEnabled) return false;

//     // Check the scope map fetched from Superset metadata
//     if (crossFilterScopeMap.hasOwnProperty(sourceId)) {
//       // Explicit scope found — only apply if this chart is in the list
//       // const allowedTargets = crossFilterScopeMap[sourceId];
//       // return allowedTargets.includes(targetId);
//       return crossFilterScopeMap[sourceId].includes(targetId);
//     }

//     // Source chart has no entry in scope map at all
//     // → Your rule: no explicit scope = filter nobody
//     return false;
//   })
// );

const applicableCrossFilters = Object.fromEntries(
  Object.entries(crossFilters).filter(([, f]) => {
    if (Number(f.sourceChartId) === Number(chart.slice_id)) return false;
    if (!crossFiltersEnabled) return false;
    const sourceId = Number(f.sourceChartId);
    const targetId = Number(chart.slice_id);
    if (crossFilterScopeMap.hasOwnProperty(sourceId)) {
      return crossFilterScopeMap[sourceId].includes(targetId);
    }
    return false;
  })
);


// REPLACE the entire applicableCrossFilters block with this simple version:
// const applicableCrossFilters = Object.fromEntries(
//   Object.entries(crossFilters).filter(([, f]) => {
//     // Never send filter back to source chart
//     if (Number(f.sourceChartId) === Number(chart.slice_id)) return false;

//     // No scope defined in Superset = don't filter this chart
//     if (!f.chartsInScope || f.chartsInScope.length === 0) return false;

//     // Use exactly what Superset configured — no fallback logic
//     return f.chartsInScope.map(Number).includes(Number(chart.slice_id));
//   })
// );



    if (Object.keys(crossFilters).length > 0) {
  console.log(`Chart ${chart.slice_id}: crossFilters=${JSON.stringify(crossFilters)}, applicable=${JSON.stringify(applicableCrossFilters)}`);
}
    return {
      sliceId:             chart.slice_id,
      title:               chart.slice_name,
      vizType:             chart.viz_type,
      xAxis:               chart.x_axis,
      height:              (chart.viz_type || "").toLowerCase().includes("big_number") ? BIGNUM_HEIGHT : chartHeightPx,
      activeFilters,
      // dateFrom:            dateFrom || null,
      // dateTo:              dateTo   || null,
      dateFrom: hasTimeFilter ? (dateFrom || null) : null,
      dateTo:   hasTimeFilter ? (dateTo   || null) : null,
      timeFilterId: hasTimeFilter ? timeFilterId : null,
      crossFilters:        applicableCrossFilters,
      onCrossFilter:       handleCrossFilter,
      onDrillDown:         handleFilterChange,
      metrics:             chart.metrics             || [],
      groupby:             chart.groupby             || [],
      groupbyRows:         chart.groupby_rows        || [],
      groupbyColumns:      chart.groupby_cols        || [],
      columnOrder:           chart.column_order           || [],   // ← ADD
      showCellBars:        chart.show_cell_bars       || false,   // ← ADD
      conditionalFormatting: chart.conditional_formatting || [],
      zoomable:            chart.zoomable            || false,
      fontColor:           chart.font_color          || null,
      conditionalColors:   chart.conditional_colors  || [],
      crossFilterScope:    chart.cross_filter_scope  ?? null,
      percentageThreshold: chart.percentage_threshold || 0,
      otherThreshold:      chart.other_threshold      || 0,
      onDateRangeDetected: handleDateRangeDetected,
    };
  };

  // ── Render rows ───────────────────────────────────────────
  const renderRows = (rows) => rows.map((row, rIdx) => {
    const totalCols = row.reduce((sum, item) => sum + (item.width || 6), 0);
    const gridCols  = Math.min(Math.max(totalCols, 1), 12);
    return (
      <div key={rIdx} style={{ marginBottom: 20 }}>
        <DashboardGrid columns={gridCols} gap={12}>
          {row.map((item, cIdx) => {
            if (item.type === "markdown") return (
              <div key={cIdx} style={{ gridColumn: isMobile ? "span 1" : `span ${item.width}`, height: unitsToPx(item.heightUnits) }}>
                <MarkdownBlock code={item.code} />
              </div>
            );
            if (item.type === "header") return (
              <div key={cIdx} style={{ gridColumn: "span 12", padding: "4px 0" }}>
                <h2 style={{ fontSize: 16, fontWeight: 600, color: "#cbd5e1", margin: 0 }}>{item.text}</h2>
              </div>
            );
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

  // ── Render with layout ────────────────────────────────────
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
          onTabChange={(tabId) => {
            // Clear cross-filters on tab switch (click-based filters reset per tab)
            // Panel filters (activeFilters) persist across tabs
            setCrossFilters({});
            setActiveTabId(tabId);
          }}
          pdfTabIdx={pdfTabIdx}
          pdfNestedTabIdx={pdfNestedTabIdx}
          dateFrom={hasTimeFilter ? dateFrom : null}
          dateTo={hasTimeFilter ? dateTo : null}
          // setDateFrom={hasTimeFilter ? setDateFrom : () => {}}
          // setDateTo={hasTimeFilter ? setDateTo : () => {}}
          setDateFrom={hasTimeFilter ? (val) => { console.log("📅 tab dateFrom:", val); setDateFrom(val); } : () => {}}
          setDateTo={hasTimeFilter ? (val) => { console.log("📅 tab dateTo:", val); setDateTo(val); } : () => {}}
          dataDateRange={dataDateRange}
          hasTimeFilter={hasTimeFilter}
        />
      );
    return null;
  });

  const renderFallback = () => (
    <div style={{ display: "grid", gridTemplateColumns: isMobile ? "1fr" : "repeat(auto-fill,minmax(min(100%,480px),1fr))", gap: 12 }}>
      {charts.map(chart => <ChartCard key={chart.slice_id} {...cardProps(chart, 320)} />)}
    </div>
  );

  // ── Render ────────────────────────────────────────────────
  // return (
  //   <div style={{ background: "#0d1117", minHeight: "100vh", padding: isMobile ? "10px" : "16px", position: "relative" }}>
  //     <PdfProgressOverlay progress={pdfProgress} />
  //     <CrossFilterPills crossFilters={crossFilters} onClear={clearCrossFilter} onClearAll={clearAllCrossFilters} />
  //     <FilterPanel
  //       filterDefs={filterDefs.filter(fd => {
  //         if (!fd.tabsInScope || fd.tabsInScope.length === 0) return true;
  //         if (!activeTabId) return true;
  //         return fd.tabsInScope.includes(activeTabId);
  //       })}
  //       activeFilters={activeFilters}
  //       dateFrom={dateFrom}
  //       dateTo={dateTo}
  //       onFilterChange={handleFilterChange}
  //       onDateFromChange={setDateFrom}
  //       onDateToChange={setDateTo}
  //       onReset={handleReset}
  //     />
  //     <ActivePills
  //       activeFilters={activeFilters}
  //       dateFrom={dateFrom}
  //       dateTo={dateTo}
  //       onRemove={(col, val) => handleFilterChange(col, val)}
  //       onRemoveDate={() => { setDateFrom(""); setDateTo(""); }}
  //     />

  //     <div ref={dashboardContentRef}>
  //       {sections ? renderWithLayout() : renderFallback()}
  //     </div>
  //   </div>
  // );
  return (
    <div style={{ background: "#0d1117", minHeight: "100vh", padding: isMobile ? "10px" : "16px", position: "relative" }}>
    <PdfProgressOverlay progress={pdfProgress} />
        {/* <CrossFilterPills crossFilters={crossFilters} onClear={clearCrossFilter} onClearAll={clearAllCrossFilters} /> */}

        <CrossFilterPills
          crossFilters={crossFilters}
          onClear={clearCrossFilter}
          onClearAll={clearAllCrossFilters}
          crossFilterScopeMap={crossFilterScopeMap}
          crossFiltersEnabled={crossFiltersEnabled}
        />
        
    <FilterPanel
      filterDefs={filterDefs.filter(fd => {
        if (!fd.tabsInScope || fd.tabsInScope.length === 0) return true;
        if (!activeTabId) return true;
        return fd.tabsInScope.includes(activeTabId);
      })}
      activeFilters={activeFilters}
      dateFrom={hasTimeFilter ? dateFrom : null}
      dateTo={hasTimeFilter ? dateTo : null}
      // onDateFromChange={hasTimeFilter ? setDateFrom : undefined}
      // onDateToChange={hasTimeFilter ? setDateTo : undefined}
      onDateFromChange={hasTimeFilter ? (val) => { console.log("📅 dateFrom changing to:", val); setDateFrom(val); } : undefined}
      onDateToChange={hasTimeFilter ? (val) => { console.log("📅 dateTo changing to:", val); setDateTo(val); } : undefined}
      onFilterChange={handleFilterChange}
      // onDateFromChange={setDateFrom}
      // onDateToChange={setDateTo}
      onReset={handleReset}
    />

    
    <ActivePills
      activeFilters={activeFilters}
      dateFrom={hasTimeFilter ? dateFrom : null}
      dateTo={hasTimeFilter ? dateTo : null}
      onRemoveDate={() => { setDateFrom(null); setDateTo(null); }}
      onRemove={(col, val) => handleFilterChange(col, val)}
      // onRemoveDate={() => { setDateFrom(""); setDateTo(""); }}
    />

    {/* ── Show DateRangePicker for dashboards WITHOUT tabs ── */}
    {/*
    {hasTimeFilter && sections && !sections.some(s => s.type === "tabs") && (
      <div style={{
        background: "#12151f",
        border: "1px solid rgba(255,255,255,0.07)",
        borderRadius: 10,
        marginBottom: 14,
        padding: "10px 14px",
        display: "flex",
        alignItems: "center",
        gap: 8
      }}>

      -- DateRangePicker — always visible, right aligned --

      <div style={{
        display:        "flex",
        justifyContent: "flex-end",
        marginBottom:   14,
      }}></div>
      <DateRangePicker
        dateFrom={dateFrom}
        dateTo={dateTo}
        onFromChange={setDateFrom}
        onToChange={setDateTo}
        onClear={() => { setDateFrom(null); setDateTo(null); }}
        dataDateRange={dataDateRange}
      />
    </div>
    )}
    */}

    <div ref={dashboardContentRef}>
      {sections ? renderWithLayout() : renderFallback()}
    </div>
  </div>
);
}
