import React, { useState, useEffect, useCallback, useRef } from "react";
import api from "./api";
import ChartCard from "./ChartCard";
import { Loader2, SlidersHorizontal, RotateCcw, X, ChevronDown, Zap,Check } from "lucide-react";
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
    <div style={{
      position: "fixed", inset: 0, zIndex: 9999,
      background: "rgba(0,0,0,0.82)",
      display: "flex", alignItems: "center", justifyContent: "center",
    }}>
      <style>{`
        @keyframes pdf-spin    { to { transform: rotate(360deg); } }
        @keyframes pdf-shimmer { 0%{background-position:200% 0} 100%{background-position:-200% 0} }
      `}</style>
      <div style={{
        background: "#1a1d26",
        border: "1px solid rgba(31,168,201,0.25)",
        borderRadius: 16, padding: "36px 44px",
        width: 400, display: "flex",
        flexDirection: "column", alignItems: "center", gap: 22,
        boxShadow: "0 24px 60px rgba(0,0,0,0.6)",
      }}>
        <div style={{ position: "relative", width: 56, height: 56 }}>
          <div style={{ position: "absolute", inset: 0, borderRadius: "50%", border: "3px solid rgba(31,168,201,0.12)" }} />
          <div style={{ position: "absolute", inset: 0, borderRadius: "50%", border: "3px solid transparent", borderTopColor: "#1FA8C9", animation: "pdf-spin 1s linear infinite" }} />
          <div style={{ position: "absolute", inset: 0, display: "flex", alignItems: "center", justifyContent: "center", fontSize: 22 }}>📄</div>
        </div>
        <div style={{ textAlign: "center" }}>
          <div style={{ fontSize: 17, fontWeight: 700, color: "#e2e8f0", marginBottom: 8 }}>Generating PDF</div>
          <div style={{ fontSize: 12, color: "#64748b" }}>
            Processing: <span style={{ color: "#1FA8C9", fontWeight: 600 }}>{progress.tabName}</span>
          </div>
        </div>
        <div style={{ width: "100%" }}>
          <div style={{ width: "100%", height: 8, background: "rgba(255,255,255,0.06)", borderRadius: 99, overflow: "hidden" }}>
            <div style={{
              width: `${pct}%`, height: "100%", borderRadius: 99,
              background: "linear-gradient(90deg,#1FA8C9 0%,#A868B7 60%,#1FA8C9 100%)",
              backgroundSize: "200% 100%",
              animation: "pdf-shimmer 1.5s linear infinite",
              transition: "width 0.6s ease",
            }} />
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
  const containerStyle = {
    background: "#1e2129", border: "1px solid rgba(255,255,255,0.065)",
    borderRadius: 10, padding: "20px 22px", height: "100%",
    boxSizing: "border-box", overflowY: "auto", position: "relative",
  };
  const topBar = (
    <div style={{ position: "absolute", top: 0, left: 0, right: 0, height: 3,
      background: "linear-gradient(90deg,#1FA8C9,#454E7C,#A868B7)", opacity: 0.75 }} />
  );
  if (hasHtml) {
    return (
      <div style={containerStyle}>
        {topBar}
        <style>{`
          .md-html-block { font-size: 13px; color: #94a3b8; line-height: 1.7; }
          .md-html-block p  { margin: 0 0 8px; }
          .md-html-block b, .md-html-block strong { color: #cbd5e1; font-weight: 600; }
          .md-html-block h1 { font-size: 16px; color: #f1f5f9; font-weight: 700; margin: 0 0 12px; }
          .md-html-block h2 { font-size: 14px; color: #e2e8f0; font-weight: 700; margin: 0 0 10px; }
          .md-html-block h3 { font-size: 12px; color: #1FA8C9; font-weight: 700; margin: 12px 0 4px; text-transform: uppercase; }
          .md-html-block center { display: block; text-align: center; }
          .md-html-block a  { color: #1FA8C9; }
        `}</style>
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
        if (line.trim() === "") return <div key={i} style={{ height: 10 }} />;
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
function CrossFilterPills({ crossFilters, onClear, onClearAll }) {
  const entries = Object.entries(crossFilters).filter(([, f]) => f.value);
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

// ── Tab group ───────────────────────────────────────────────
function TabGroup({
  tabs = [],
  chartMap,
  cardProps,
  isMobile,
  renderRows,
  onTabChange,
  pdfTabIdx,
  pdfNestedTabIdx,
  dateFrom,
  dateTo,
  setDateFrom,
  setDateTo,
}) {
  const [activeIdx, setActiveIdx] = useState(0);

  useEffect(() => {
    if (tabs.length > 0 && onTabChange) onTabChange(tabs[0].id);
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  const displayIdx = (pdfTabIdx !== null && pdfTabIdx !== undefined)
    ? Math.min(pdfTabIdx, tabs.length - 1)
    : activeIdx;

  const activeTab = tabs[displayIdx];
  const hasContent = activeTab?.rows?.length > 0 || activeTab?.nestedTabsSection != null;

  return (
    <div style={{ marginBottom: 12 }}>
      <div style={{
        display: "flex",
        alignItems: "center",
        borderBottom: "1px solid rgba(255,255,255,0.07)",
        background: "#12151f",
        minHeight: 42,
      }}>
        {tabs.length > 0 && (
          <div style={{
            flex: 1,
            display: "flex",
            alignItems: "center",
            overflowX: "auto",
            overflowY: "hidden",
            scrollbarWidth: "none",
            msOverflowStyle: "none",
            gap: 2,
            padding: "0 8px",
            minWidth: 0,
          }}>
            {tabs.map((tab, i) => (
              <button
                key={tab.id}
                onClick={() => {
                  setActiveIdx(i);
                  if (onTabChange) onTabChange(tab.id);
                }}
                style={{
                  flexShrink: 0,
                  padding: "10px 18px",
                  fontSize: 13,
                  fontWeight: displayIdx === i ? 600 : 400,
                  color: displayIdx === i ? "#1FA8C9" : "#64748b",
                  background: "transparent",
                  border: "none",
                  borderBottom: displayIdx === i
                    ? "2px solid #1FA8C9"
                    : "2px solid transparent",
                  cursor: "pointer",
                  whiteSpace: "nowrap",
                  transition: "color 0.15s, border-color 0.15s",
                }}
              >
                {tab.name}
              </button>
            ))}
          </div>
        )}

        <div style={{
          marginLeft: "auto",
          flexShrink: 0,
          borderLeft: "1px solid rgba(255,255,255,0.07)",
          padding: "0 12px",
          display: "flex",
          alignItems: "center",
          gap: 8,
          height: "100%",
          minHeight: 42,
        }}>
          <DateRangePicker
            dateFrom={dateFrom}
            dateTo={dateTo}
            onFromChange={setDateFrom}
            onToChange={setDateTo}
            onClear={() => { setDateFrom(null); setDateTo(null); }}
          />
        </div>
      </div>

      {activeTab?.rows?.length > 0 && renderRows(activeTab.rows)}

      {activeTab?.nestedTabsSection && (
        <TabGroup
          tabs={activeTab.nestedTabsSection.tabs}
          chartMap={chartMap}
          cardProps={cardProps}
          isMobile={isMobile}
          renderRows={renderRows}
          onTabChange={onTabChange}
          pdfTabIdx={pdfNestedTabIdx}
          pdfNestedTabIdx={null}
          dateFrom={dateFrom}
          dateTo={dateTo}
          setDateFrom={setDateFrom}
          setDateTo={setDateTo}
        />
      )}

      {tabs.length > 0 && !hasContent && (
        <div style={{ padding: "40px 0", textAlign: "center", color: "#374151", fontSize: 13 }}>
          No charts in this tab
        </div>
      )}
    </div>
  );
}

// ══════════════════════════════════════════════════════════════
//  HORIZONTAL FILTER BAR — Replace the existing FilterPanel
//  in DashboardChartsPage.jsx with this entire block
// ══════════════════════════════════════════════════════════════
 
// ── Single dropdown filter ──────────────────────────────────
function FilterDropdown({ fd, activeFilters, dateFrom, dateTo, onFilterChange, onDateFromChange, onDateToChange }) {
  const [open,   setOpen]   = useState(false);
  const [search, setSearch] = useState("");
  const ref                 = useRef(null);
 
  // Close on outside click
  useEffect(() => {
    if (!open) return;
    const fn = (e) => { if (ref.current && !ref.current.contains(e.target)) { setOpen(false); setSearch(""); } };
    document.addEventListener("mousedown", fn);
    return () => document.removeEventListener("mousedown", fn);
  }, [open]);
 
  // Support both single value and array
  const rawVal       = activeFilters[fd.column];
  const selectedVals = Array.isArray(rawVal) ? rawVal : (rawVal ? [rawVal] : []);
  const hasSelection = fd.type === "date" ? !!dateFrom : selectedVals.length > 0;
  const selCount     = selectedVals.length;
 
  const displayed = fd.type === "select"
    ? (fd.values || []).filter(v => !search.trim() || String(v).toLowerCase().includes(search.toLowerCase()))
    : [];
 
  const handleClearAll = (e) => {
    e?.stopPropagation();
    if (fd.type === "date") {
      onDateFromChange?.(""); onDateToChange?.("");
    } else {
      // Remove all selected values one by one
      selectedVals.forEach(v => onFilterChange?.(fd.column, v));
    }
  };
 
  const handleToggle = (val) => {
    onFilterChange?.(fd.column, val);
    // Do NOT close — allow multi-select
  };
 
  const handleSelectAll = () => {
    // Add all displayed values that are not yet selected
    displayed.forEach(v => {
      if (!selectedVals.includes(v)) onFilterChange?.(fd.column, v);
    });
  };
 
  const isAllSelected = displayed.length > 0 && displayed.every(v => selectedVals.includes(v));
 
  return (
    <div ref={ref} style={{ position: "relative", flexShrink: 0 }}>
 
      {/* ── Trigger button ── */}
      <button
        onClick={() => { setOpen(p => !p); setSearch(""); }}
        style={{
          display: "flex", alignItems: "center", gap: 6,
          padding: "6px 12px", borderRadius: 8,
          fontSize: 12, fontWeight: hasSelection ? 700 : 500,
          border: `1px solid ${hasSelection
            ? "rgba(31,168,201,0.55)"
            : open ? "rgba(255,255,255,0.18)" : "rgba(255,255,255,0.09)"}`,
          background: hasSelection
            ? "rgba(31,168,201,0.13)"
            : open ? "rgba(255,255,255,0.07)" : "rgba(255,255,255,0.03)",
          color:      hasSelection ? "#1FA8C9" : "#94a3b8",
          cursor:     "pointer", outline: "none",
          whiteSpace: "nowrap", userSelect: "none",
          transition: "all .15s",
        }}
      >
        <span>{fd.name}</span>
 
        {/* Count badge */}
        {selCount > 0 && (
          <span style={{
            fontSize: 9, background: "#1FA8C9", color: "#fff",
            borderRadius: 8, padding: "1px 6px", fontWeight: 700,
            lineHeight: 1.5, flexShrink: 0,
          }}>
            {selCount}
          </span>
        )}
 
        {/* Clear all × or chevron */}
        {hasSelection ? (
          <X
            size={11}
            onClick={handleClearAll}
            style={{ color: "#1FA8C9", cursor: "pointer", flexShrink: 0 }}
          />
        ) : (
          <ChevronDown size={11} style={{
            color:      open ? "#94a3b8" : "#475569",
            transform:  open ? "rotate(180deg)" : "rotate(0deg)",
            transition: "transform .15s", flexShrink: 0,
          }} />
        )}
      </button>
 
      {/* ── Dropdown panel ── */}
      {open && (
        <div style={{
          position:     "absolute",
          top:          "calc(100% + 6px)",
          left:         0,
          minWidth:     240,
          maxWidth:     380,
          background:   "#181b24",
          border:       "1px solid rgba(255,255,255,0.1)",
          borderRadius: 10,
          boxShadow:    "0 16px 48px rgba(0,0,0,0.65)",
          zIndex:       500,
          overflow:     "hidden",
        }}>
 
          {/* Panel header */}
          <div style={{
            display: "flex", alignItems: "center", justifyContent: "space-between",
            padding: "9px 14px 8px",
            borderBottom: "1px solid rgba(255,255,255,0.06)",
          }}>
            <div style={{ display: "flex", alignItems: "center", gap: 7 }}>
              <span style={{ fontSize: 11, fontWeight: 700, color: "#cbd5e1", textTransform: "uppercase", letterSpacing: "0.07em" }}>
                {fd.name}
              </span>
              {selCount > 0 && (
                <span style={{ fontSize: 10, color: "#1FA8C9", fontWeight: 600 }}>
                  {selCount} selected
                </span>
              )}
            </div>
            <div style={{ display: "flex", gap: 10 }}>
              {/* Select all / Deselect all */}
              {fd.type === "select" && (
                <button
                  onClick={isAllSelected ? handleClearAll : handleSelectAll}
                  style={{ fontSize: 10, color: "#64748b", background: "none", border: "none", cursor: "pointer", padding: 0 }}
                  onMouseEnter={e => e.currentTarget.style.color = "#1FA8C9"}
                  onMouseLeave={e => e.currentTarget.style.color = "#64748b"}
                >
                  {isAllSelected ? "Deselect all" : "Select all"}
                </button>
              )}
              {hasSelection && (
                <button
                  onClick={handleClearAll}
                  style={{ fontSize: 10, color: "#64748b", background: "none", border: "none", cursor: "pointer", padding: 0 }}
                  onMouseEnter={e => e.currentTarget.style.color = "#f87171"}
                  onMouseLeave={e => e.currentTarget.style.color = "#64748b"}
                >
                  Clear
                </button>
              )}
            </div>
          </div>
 
          {/* ── Date filter ── */}
          {fd.type === "date" && (
            <div style={{ padding: "12px 14px", display: "flex", flexDirection: "column", gap: 10 }}>
              {[["From", dateFrom, onDateFromChange], ["To", dateTo, onDateToChange]].map(([label, val, setter]) => (
                <div key={label}>
                  <p style={{ fontSize: 10, color: "#475569", marginBottom: 5, fontWeight: 600, textTransform: "uppercase", letterSpacing: "0.06em" }}>{label}</p>
                  <input type="date" value={val} onChange={e => setter?.(e.target.value)}
                    style={{ background: "#0d1117", border: "1px solid #2d3748", borderRadius: 6, padding: "6px 10px", fontSize: 11, color: "#94a3b8", width: "100%", outline: "none", cursor: "pointer" }} />
                </div>
              ))}
            </div>
          )}
 
          {/* ── Select filter — multi-select ── */}
          {fd.type === "select" && (
            <>
              {/* Search */}
              {fd.values.length > 8 && (
                <div style={{ padding: "8px 12px 6px", borderBottom: "1px solid rgba(255,255,255,0.05)" }}>
                  <input
                    autoFocus
                    placeholder={`Search ${fd.name.toLowerCase()}…`}
                    value={search}
                    onChange={e => setSearch(e.target.value)}
                    style={{
                      width: "100%", background: "rgba(255,255,255,0.05)",
                      border: "1px solid rgba(255,255,255,0.09)",
                      borderRadius: 6, padding: "5px 10px",
                      fontSize: 11, color: "#e2e8f0", outline: "none",
                    }}
                  />
                </div>
              )}
 
              {/* Selected values shown at top (when some selected and search is empty) */}
              {selCount > 0 && !search && (
                <div style={{
                  padding: "8px 12px 6px",
                  borderBottom: "1px solid rgba(255,255,255,0.05)",
                  display: "flex", flexWrap: "wrap", gap: 4,
                }}>
                  {selectedVals.map(v => (
                    <span key={v} style={{
                      display: "flex", alignItems: "center", gap: 3,
                      padding: "3px 8px", borderRadius: 14, fontSize: 10,
                      fontWeight: 700,
                      background: "rgba(31,168,201,0.2)",
                      color: "#1FA8C9",
                      border: "1px solid rgba(31,168,201,0.4)",
                    }}>
                      {v}
                      <X
                        size={9}
                        style={{ cursor: "pointer", opacity: 0.7 }}
                        onClick={() => handleToggle(v)}
                      />
                    </span>
                  ))}
                </div>
              )}
 
              {/* All options */}
              <div style={{
                padding: "8px 12px 10px",
                maxHeight: 200,
                overflowY: "auto",
                scrollbarWidth: "thin",
                scrollbarColor: "#2d3748 transparent",
                display: "flex",
                flexWrap: "wrap",
                gap: 5,
              }}>
                {displayed.length === 0 && (
                  <span style={{ fontSize: 11, color: "#374151", padding: "4px 2px" }}>No results</span>
                )}
 
                {displayed.map(val => {
                  const active = selectedVals.includes(val);
                  return (
                    <button
                      key={val}
                      onClick={() => handleToggle(val)}
                      style={{
                        display: "flex", alignItems: "center", gap: 4,
                        padding: "4px 10px", borderRadius: 16, fontSize: 11,
                        fontWeight: 600, cursor: "pointer",
                        border: `1px solid ${active ? "#1FA8C9" : "rgba(31,168,201,0.2)"}`,
                        background: active ? "#1FA8C9" : "rgba(31,168,201,0.07)",
                        color: active ? "#fff" : "#5ba8b9",
                        outline: "none", transition: "all .12s ease",
                      }}
                    >
                      {active && <Check size={9} />}
                      {val}
                    </button>
                  );
                })}
              </div>
 
              {/* Footer */}
              <div style={{
                padding: "5px 14px 8px",
                fontSize: 10, color: "#374151",
                borderTop: "1px solid rgba(255,255,255,0.04)",
                display: "flex", justifyContent: "space-between",
              }}>
                <span>
                  {fd.values.length} option{fd.values.length !== 1 ? "s" : ""}
                  {search ? ` · ${displayed.length} matching` : ""}
                </span>
                {selCount > 0 && (
                  <span style={{ color: "#1FA8C9", fontWeight: 600 }}>{selCount} selected</span>
                )}
              </div>
            </>
          )}
        </div>
      )}
    </div>
  );
}



// ── Horizontal filter panel ─────────────────────────────────
// Replace the existing FilterPanel function with this one
function FilterPanel({ filterDefs, activeFilters, dateFrom, dateTo, onFilterChange, onDateFromChange, onDateToChange, onReset }) {
  if (!filterDefs?.length) return null;
 
  const activeCount = Object.values(activeFilters).reduce((acc, v) => {
    if (Array.isArray(v)) return acc + v.length;
    return acc + (v ? 1 : 0);
  }, 0) + (dateFrom ? 1 : 0);
 
  const hasActive = activeCount > 0;
 
  return (
    <div style={{
      background:   "#12151f",
      border:       "1px solid rgba(255,255,255,0.07)",
      borderRadius: 10,
      marginBottom: 14,
      padding:      "10px 14px",
    }}>
      <div style={{ display: "flex", alignItems: "center", flexWrap: "wrap", gap: 8 }}>
 
        {/* Label */}
        <div style={{ display: "flex", alignItems: "center", gap: 7, flexShrink: 0 }}>
          <SlidersHorizontal size={13} style={{ color: "#475569" }} />
          <span style={{ fontSize: 11, fontWeight: 700, color: "#475569", letterSpacing: "0.09em", textTransform: "uppercase" }}>
            Filters
          </span>
          {hasActive && (
            <span style={{ fontSize: 9, background: "#1FA8C9", color: "#fff", borderRadius: 8, padding: "1px 6px", fontWeight: 700 }}>
              {activeCount}
            </span>
          )}
        </div>
 
        {/* Divider */}
        <div style={{ width: 1, height: 18, background: "rgba(255,255,255,0.08)", flexShrink: 0 }} />
 
        {/* Dropdowns */}
        {filterDefs.map(fd => (
          <FilterDropdown
            key={fd.id}
            fd={fd}
            activeFilters={activeFilters}
            dateFrom={dateFrom}
            dateTo={dateTo}
            onFilterChange={onFilterChange}
            onDateFromChange={onDateFromChange}
            onDateToChange={onDateToChange}
          />
        ))}
 
        {/* Reset */}
        {hasActive && (
          <>
            <div style={{ width: 1, height: 18, background: "rgba(255,255,255,0.08)", flexShrink: 0 }} />
            <button
              onClick={onReset}
              style={{
                display: "flex", alignItems: "center", gap: 5,
                padding: "5px 11px", borderRadius: 7,
                fontSize: 11, fontWeight: 600,
                border: "1px solid rgba(239,68,68,0.28)",
                color: "#f87171", background: "rgba(239,68,68,0.06)",
                cursor: "pointer", flexShrink: 0, outline: "none", transition: "all .15s",
              }}
              onMouseEnter={e => { e.currentTarget.style.background = "rgba(239,68,68,0.12)"; e.currentTarget.style.borderColor = "rgba(239,68,68,0.5)"; }}
              onMouseLeave={e => { e.currentTarget.style.background = "rgba(239,68,68,0.06)"; e.currentTarget.style.borderColor = "rgba(239,68,68,0.28)"; }}
            >
              <RotateCcw size={10} /> Reset
            </button>
          </>
        )}
      </div>
    </div>
  );
}



// const FLabel = ({ children }) => <p style={{ fontSize: 10, color: "#475569", textTransform: "uppercase", letterSpacing: "0.08em", marginBottom: 7, fontWeight: 700 }}>{children}</p>;
// const FDate  = ({ value, onChange }) => <input type="date" value={value} onChange={onChange} style={{ background: "#0d1117", border: "1px solid #2d3748", borderRadius: 7, padding: "5px 9px", fontSize: 11, color: "#94a3b8", width: 132, outline: "none", cursor: "pointer" }} />;
// function FResetBtn({ onClick }) {
//   const [hov, setHov] = useState(false);
//   return (
//     <button onClick={onClick} onMouseEnter={() => setHov(true)} onMouseLeave={() => setHov(false)}
//       style={{ display: "flex", alignItems: "center", gap: 5, padding: "6px 13px", borderRadius: 7, fontSize: 11, fontWeight: 600, border: `1px solid ${hov ? "#475569" : "#2d3748"}`, color: hov ? "#94a3b8" : "#64748b", background: "transparent", cursor: "pointer", transition: "all .15s" }}>
//       <RotateCcw size={11} /> Reset
//     </button>
//   );
// }

// function ActivePills({ activeFilters, dateFrom, dateTo, onRemove, onRemoveDate }) {
//   const entries = Object.entries(activeFilters).filter(([, v]) => v);
//   if (!entries.length && !dateFrom) return null;
//   return (
//     <div style={{ display: "flex", flexWrap: "wrap", gap: 6, marginBottom: 14, alignItems: "center" }}>
//       <span style={{ fontSize: 9, color: "#374151", fontWeight: 700, letterSpacing: "0.09em", textTransform: "uppercase" }}>Active:</span>
//       {entries.map(([col, val]) => (
//         <span key={col} style={{ display: "flex", alignItems: "center", gap: 5, fontSize: 11, background: "rgba(31,168,201,0.12)", color: "#67c5d8", border: "1px solid rgba(31,168,201,0.22)", padding: "3px 8px 3px 10px", borderRadius: 16 }}>
//           <span style={{ color: "#4a5568", fontSize: 9 }}>{col}:</span>&nbsp;{val}
//           <button onClick={() => onRemove(col)} style={{ background: "none", border: "none", color: "#64748b", cursor: "pointer", padding: 0, display: "flex", alignItems: "center" }}><X size={10} /></button>
//         </span>
//       ))}
//       {dateFrom && dateTo && (
//         <span style={{ display: "flex", alignItems: "center", gap: 5, fontSize: 11, background: "rgba(139,92,246,0.12)", color: "#a78bfa", border: "1px solid rgba(139,92,246,0.22)", padding: "3px 8px 3px 10px", borderRadius: 16 }}>
//           {dateFrom} → {dateTo}
//           <button onClick={onRemoveDate} style={{ background: "none", border: "none", color: "#64748b", cursor: "pointer", padding: 0, display: "flex", alignItems: "center" }}><X size={10} /></button>
//         </span>
//       )}
//     </div>
//   );
// }



function ActivePills({ activeFilters, dateFrom, dateTo, onRemove, onRemoveDate }) {
  // Build flat list of {col, val} pairs from multi-select arrays
  const pills = [];
  for (const [col, val] of Object.entries(activeFilters)) {
    if (!val) continue;
    const vals = Array.isArray(val) ? val : [val];
    vals.forEach(v => pills.push({ col, val: v }));
  }
 
  if (!pills.length && !dateFrom) return null;
 
  const removeOne = (col, val) => {
    // Re-use handleFilterChange logic: toggle the value off
    // Parent passes onRemove(col, val) so it can update the array
    onRemove(col, val);
  };
 
  return (
    <div style={{ display: "flex", flexWrap: "wrap", gap: 6, marginBottom: 14, alignItems: "center" }}>
      <span style={{ fontSize: 9, color: "#374151", fontWeight: 700, letterSpacing: "0.09em", textTransform: "uppercase" }}>
        Active:
      </span>
 
      {pills.map(({ col, val }) => (
        <span key={`${col}:${val}`} style={{
          display: "flex", alignItems: "center", gap: 5, fontSize: 11,
          background: "rgba(31,168,201,0.12)", color: "#67c5d8",
          border: "1px solid rgba(31,168,201,0.22)", padding: "3px 8px 3px 10px", borderRadius: 16,
        }}>
          <span style={{ color: "#4a5568", fontSize: 9 }}>{col}:</span>&nbsp;{val}
          <button
            onClick={() => removeOne(col, val)}
            style={{ background: "none", border: "none", color: "#64748b", cursor: "pointer", padding: 0, display: "flex", alignItems: "center" }}
          >
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

// ----------------------------------------------------------------
// ── Date Range Picker ─────────────────────────────────────────
// ----------------------------------------------------------------

function DateRangePicker({ dateFrom, dateTo, onFromChange, onToChange, onClear }) {

  // ── Local draft state — doesn't trigger filter until Search clicked ──
  const [draftFrom, setDraftFrom] = useState(dateFrom || "");
  const [draftTo,   setDraftTo]   = useState(dateTo   || "");

  // Sync draft if parent clears the dates (e.g. ✕ Clear clicked)
  useEffect(() => {
    setDraftFrom(dateFrom || "");
    setDraftTo(dateTo     || "");
  }, [dateFrom, dateTo]);

  const hasDate    = dateFrom || dateTo;
  const hasDraft   = draftFrom || draftTo;
  const isDirty    = draftFrom !== (dateFrom || "")
                  || draftTo   !== (dateTo   || "");

  // ── Apply filter — called only when Search is clicked ────────────
  const handleSearch = () => {
    onFromChange(draftFrom || null);
    onToChange(draftTo     || null);
  };

  // ── Clear both draft and applied filter ──────────────────────────
  const handleClear = () => {
    setDraftFrom("");
    setDraftTo("");
    onClear();
  };

  return (
    <div style={{
      display:    "flex",
      alignItems: "center",
      gap:        8,
    }}>

      {/* Label */}
      <span style={{ fontSize: 12, color: "#64748b", whiteSpace: "nowrap" }}>
        📅 Date
      </span>

      {/* Start Date */}
      <input
        type="date"
        value={draftFrom}
        max={draftTo || undefined}
        onChange={e => setDraftFrom(e.target.value)}
        style={{
          background:  "#12151f",
          border:      `1px solid ${draftFrom ? "#1FA8C9" : "rgba(255,255,255,0.1)"}`,
          borderRadius: 6,
          padding:     "4px 8px",
          color:       draftFrom ? "#e2e8f0" : "#64748b",
          fontSize:    11,
          cursor:      "pointer",
          outline:     "none",
          colorScheme: "dark",
        }}
      />

      <span style={{ color: "#64748b", fontSize: 11 }}>→</span>

      {/* End Date */}
      <input
        type="date"
        value={draftTo}
        min={draftFrom || undefined}
        onChange={e => setDraftTo(e.target.value)}
        style={{
          background:  "#12151f",
          border:      `1px solid ${draftTo ? "#1FA8C9" : "rgba(255,255,255,0.1)"}`,
          borderRadius: 6,
          padding:     "4px 8px",
          color:       draftTo ? "#e2e8f0" : "#64748b",
          fontSize:    11,
          cursor:      "pointer",
          outline:     "none",
          colorScheme: "dark",
        }}
      />

      {/* Search button — active only when both dates selected */}
      <button
        onClick={handleSearch}
        disabled={!draftFrom || !draftTo}
        title={!draftFrom || !draftTo ? "Select both dates first" : "Apply date filter"}
        style={{
          display:      "flex",
          alignItems:   "center",
          gap:          4,
          background:   (draftFrom && draftTo)
                          ? "rgba(31,168,201,0.15)"
                          : "rgba(255,255,255,0.03)",
          border:       `1px solid ${(draftFrom && draftTo)
                          ? "rgba(31,168,201,0.4)"
                          : "rgba(255,255,255,0.08)"}`,
          borderRadius: 6,
          padding:      "4px 12px",
          color:        (draftFrom && draftTo) ? "#1FA8C9" : "#374151",
          fontSize:     11,
          fontWeight:   600,
          cursor:       (draftFrom && draftTo) ? "pointer" : "not-allowed",
          whiteSpace:   "nowrap",
          transition:   "all 0.15s",
        }}
        onMouseEnter={e => {
          if (draftFrom && draftTo)
            e.currentTarget.style.background = "rgba(31,168,201,0.25)";
        }}
        onMouseLeave={e => {
          if (draftFrom && draftTo)
            e.currentTarget.style.background = "rgba(31,168,201,0.15)";
        }}
      >
        🔍 Search
      </button>

      {/* Clear button — only when filter is actively applied */}
      {hasDate && (
        <button
          onClick={handleClear}
          title="Clear date filter"
          style={{
            background:   "rgba(248,113,113,0.1)",
            border:       "1px solid rgba(248,113,113,0.3)",
            borderRadius: 6,
            padding:      "4px 8px",
            color:        "#f87171",
            fontSize:     11,
            cursor:       "pointer",
            whiteSpace:   "nowrap",
          }}
        >
          ✕
        </button>
      )}

    </div>
  );
}





// ══════════════════════════════════════════════════════════════
//  MAIN COMPONENT
// ══════════════════════════════════════════════════════════════
export default function DashboardChartsPage({ dashboardNumericId, onPdfReady }) {
  const [charts,        setCharts]        = useState([]);
  const [sections,      setSections]      = useState(null);
  const [filterDefs,    setFilterDefs]    = useState([]);
  const [activeFilters, setActiveFilters] = useState({});
  const [loading,       setLoading]       = useState(true);
  const [error,         setError]         = useState(null);
  const [crossFilters,  setCrossFilters]  = useState({});

  // Date filter state
  const [dateFrom, setDateFrom] = useState(null);
  const [dateTo,   setDateTo]   = useState(null);

  // scoping for active tab and its charts — reset on tab change to avoid showing wrong pills/charts during loading
  const [activeTabId, setActiveTabId] = useState(null);
  // const [activeTabChartIds, setActiveTabChartIds] = useState(new Set());


  // ── PDF state ─────────────────────────────────────────────
  const [isPdfLoading,    setIsPdfLoading]    = useState(false);
  const [pdfTabIdx,       setPdfTabIdx]       = useState(null);
  const [pdfNestedTabIdx, setPdfNestedTabIdx] = useState(null);
  const [pdfProgress,     setPdfProgress]     = useState(null);

  const dashboardContentRef = useRef(null);
  const pdfResolveRef       = useRef(null);
  const isPdfLoadingRef     = useRef(false);  // guard — no re-renders on change
  const sectionsRef         = useRef(null);   // always-current sections without deps
  const downloadRef         = useRef(null);   // stable wrapper ref for parent

  const windowWidth = useWindowWidth();
  const isMobile    = windowWidth < 768;

  // Keep sectionsRef in sync
  useEffect(() => { sectionsRef.current = sections; }, [sections]);

  // const handleFilterChange = useCallback((col, val) => setActiveFilters(prev => ({ ...prev, [col]: prev[col] === val ? null : val })), []);
  const handleFilterChange = useCallback((col, val) => {
    setActiveFilters(prev => {
      const current = Array.isArray(prev[col]) ? prev[col] : (prev[col] ? [prev[col]] : []);
      const exists   = current.includes(val);
      const updated  = exists ? current.filter(v => v !== val) : [...current, val];
      if (updated.length === 0) {
        const next = { ...prev }; delete next[col]; return next;
      }
      return { ...prev, [col]: updated };
    });
  }, []);

  const handleReset        = useCallback(() => { setActiveFilters({}); setDateFrom(""); setDateTo(""); }, []);
  const handleCrossFilter  = useCallback((column, value, sourceChartId, sourceChartTitle, fromTable = false, chartsInScope = null) => {
    setCrossFilters(prev => {
      if (!value) { const next = { ...prev }; delete next[column]; return next; }
      return { ...prev, [column]: { value, sourceChartId, sourceChartTitle, fromTable, chartsInScope, } };
    });
  }, []);
  const clearCrossFilter     = useCallback((col) => setCrossFilters(prev => { const n = { ...prev }; delete n[col]; return n; }), []);
  const clearAllCrossFilters = useCallback(() => setCrossFilters({}), []);

  // ── After React renders new tab state → wait 3s → resolve ──
  useEffect(() => {
    if (pdfResolveRef.current) {
      const resolve = pdfResolveRef.current;
      pdfResolveRef.current = null;
      setTimeout(resolve, 3000);
    }
  }, [pdfTabIdx, pdfNestedTabIdx]);

  //  PDF download — EMPTY deps, created once, never recreated
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
      const HDR   = 16;

      const drawPage = (tabName) => {
        pdf.setFillColor(13, 17, 23);  pdf.rect(0, 0, pageW, pageH, "F");
        pdf.setFillColor(18, 21, 31);  pdf.rect(0, 0, pageW, HDR, "F");
        pdf.setDrawColor(45, 55, 72);  pdf.setLineWidth(0.4);  pdf.line(0, HDR, pageW, HDR);
        pdf.setFont("helvetica", "bold");  pdf.setFontSize(13);
        pdf.setTextColor(255, 255, 255);   pdf.text("Speegile", 8, 10.5);
        const sw = pdf.getStringUnitWidth("Speegile") * 13 * 0.352778;
        pdf.setTextColor(31, 168, 201);    pdf.text(" Analytics", 8 + sw, 10.5);
        if (tabName) {
          pdf.setFont("helvetica", "normal"); pdf.setFontSize(10);
          pdf.setTextColor(203, 213, 225);
          pdf.text(tabName, pageW - 8, 10.5, { align: "right" });
        }
      };

      const capture = () => html2canvas(dashboardContentRef.current, {
        scale: 1.5, useCORS: true, allowTaint: true,
        backgroundColor: "#0d1117", logging: false, imageTimeout: 0,
        onclone: (doc) => { doc.querySelectorAll("svg").forEach(s => { s.style.overflow = "visible"; }); },
      });

      const addPage = (canvas, tabName, isFirst) => {
        if (!isFirst) pdf.addPage();
        drawPage(tabName);
        const margin = 3, availW = pageW - margin * 2, availH = pageH - HDR - margin * 2;
        const aspect = canvas.width / canvas.height;
        const img    = canvas.toDataURL("image/jpeg", 0.9);
        let w, h, x, y;
        if (aspect > availW / availH) { w = availW; h = availW / aspect; x = margin; y = HDR + margin + (availH - h) / 2; }
        else                           { h = availH; w = availH * aspect; x = margin + (availW - w) / 2; y = HDR + margin; }
        pdf.addImage(img, "JPEG", x, y, w, h);
      };

      // Read from ref — no stale closure issues
      const currentSections = sectionsRef.current;
      const tabSection   = currentSections?.find(s => s.type === "tabs");
      const topLevelTabs = tabSection?.tabs || [];
      const totalPages   = topLevelTabs.length === 0 ? 1 :
        topLevelTabs.reduce((acc, tab) => acc + ((tab.nestedTabsSection?.tabs?.length || 0) > 1 ? tab.nestedTabsSection.tabs.length : 1), 0);

      const switchAndWait = (ti, ni, tabName, pageNum) => new Promise(resolve => {
        setPdfProgress({ current: pageNum, total: totalPages, tabName });
        pdfResolveRef.current = resolve;
        setPdfTabIdx(ti);
        setPdfNestedTabIdx(ni);
      });

      let isFirst = true, pagesDone = 0;

      if (topLevelTabs.length === 0) {
        setPdfProgress({ current: 0, total: 1, tabName: "Dashboard" });
        await new Promise(r => setTimeout(r, 3000));
        addPage(await capture(), "Dashboard", true);
      } else {
        for (let ti = 0; ti < topLevelTabs.length; ti++) {
          const topTab     = topLevelTabs[ti];
          const nestedTabs = topTab.nestedTabsSection?.tabs || [];
          if (nestedTabs.length <= 1) {
            const label = nestedTabs.length === 1 ? `${topTab.name}  ›  ${nestedTabs[0].name}` : topTab.name;
            await switchAndWait(ti, null, label, pagesDone + 1);
            addPage(await capture(), label, isFirst);
            isFirst = false; pagesDone++;
          } else {
            for (let ni = 0; ni < nestedTabs.length; ni++) {
              const label = `${topTab.name}  ›  ${nestedTabs[ni].name}`;
              await switchAndWait(ti, ni, label, pagesDone + 1);
              addPage(await capture(), label, isFirst);
              isFirst = false; pagesDone++;
            }
          }
        }
      }

      setPdfTabIdx(null); setPdfNestedTabIdx(null); setPdfProgress(null);
      pdf.save("speegile_dashboard.pdf");

    } catch (err) {
      console.error("PDF generation failed:", err);
    } finally {
      isPdfLoadingRef.current = false;
      setIsPdfLoading(false);
      setPdfTabIdx(null); setPdfNestedTabIdx(null); setPdfProgress(null);
    }
  }, []); // ← EMPTY — function created once, never recreated, no loop possible

  // Always keep ref current
  downloadRef.current = downloadDashboardPDF;

  // ── Register with parent ONCE on mount — stable wrapper via ref ──
useEffect(() => {
  if (onPdfReady) {
    onPdfReady(() => () => downloadRef.current?.());  // ← double-wrap
  }
}, []); // eslint-disable-line react-hooks/exhaustive-deps

  // ── Load dashboard data ───────────────────────────────────
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

  // ── Early returns (after all hooks) ──────────────────────
  if (loading) return (
    <div style={{ display: "flex", alignItems: "center", justifyContent: "center", padding: "64px 0" }}>
      <Loader2 size={20} style={{ color: "#1FA8C9", animation: "spin .9s linear infinite" }} />
      <span style={{ marginLeft: 10, color: "#64748b", fontSize: 14 }}>Loading dashboard…</span>
      <style>{`@keyframes spin{from{transform:rotate(0)}to{transform:rotate(360deg)}}`}</style>
    </div>
  );
  if (error)         return <div style={{ textAlign: "center", padding: "64px 0", color: "#f87171",  fontSize: 13 }}>⚠ {error}</div>;
  if (!charts.length) return <div style={{ textAlign: "center", padding: "64px 0", color: "#374151", fontSize: 13 }}>No charts found.</div>;

  const chartMap = Object.fromEntries(charts.map(c => [c.slice_id, c]));

  // const cardProps = (chart, chartHeightPx = 320) => ({
    
  //   sliceId:           chart.slice_id,
  //   title:             chart.slice_name,
  //   vizType:           chart.viz_type,
  //   xAxis:             chart.x_axis,
  //   height: (chart.viz_type || "").toLowerCase().includes("big_number") ? BIGNUM_HEIGHT : chartHeightPx,
  //   activeFilters, dateFrom: dateFrom || null, dateTo: dateTo || null,
  //   crossFilters,  onCrossFilter: handleCrossFilter, onDrillDown: handleFilterChange,
  //   metrics:           chart.metrics            || [],
  //   groupby:           chart.groupby            || [],
  //   groupbyRows:       chart.groupby_rows       || [],
  //   groupbyColumns:    chart.groupby_cols       || [],
  //   zoomable:          chart.zoomable           || false,
  //   fontColor:         chart.font_color         || null,
  //   conditionalColors: chart.conditional_colors || [],  // ← ADD
  // });


  const cardProps = (chart, chartHeightPx = 320) => {

  // ── Only pass cross-filters that are scoped to affect this chart ──
  const applicableCrossFilters = Object.fromEntries(
    Object.entries(crossFilters).filter(([, f]) => {
      if (!f.chartsInScope) return true;          // no scope = affects all
      return f.chartsInScope.includes(chart.slice_id);  // ← respect scoping
    })
  );

  return {
    sliceId:           chart.slice_id,
    title:             chart.slice_name,
    vizType:           chart.viz_type,
    xAxis:             chart.x_axis,
    height:            (chart.viz_type || "").toLowerCase().includes("big_number")
                         ? BIGNUM_HEIGHT : chartHeightPx,
    activeFilters,
    dateFrom:          dateFrom || null,
    dateTo:            dateTo   || null,
    crossFilters:      applicableCrossFilters,     // ← scoped, not full
    onCrossFilter:     handleCrossFilter,
    onDrillDown:       handleFilterChange,
    metrics:           chart.metrics       || [],
    groupby:           chart.groupby       || [],
    groupbyRows:       chart.groupby_rows  || [],
    groupbyColumns:    chart.groupby_cols  || [],
    zoomable:          chart.zoomable      || false,
    fontColor:         chart.font_color    || null,
    conditionalColors: chart.conditional_colors || [],
    crossFilterScope:  chart.cross_filter_scope || null,  // ← ADD
  };
};

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



  // Helper to extract chart IDs from a tab's rows:
// const getChartIdsFromRows = (rows = []) => {
//   const ids = new Set();
//   rows.forEach(row => row.forEach(item => {
//     if (item.chartId) ids.add(item.chartId);
//   }));
//   return ids;
// };

  const renderWithLayout = () => sections.map((section, sIdx) => {
    if (section.type === "rows")
      return <React.Fragment key={sIdx}>{renderRows(section.rows)}</React.Fragment>;
    if (section.type === "tabs")
      return (
        // <TabGroup
        //   key={sIdx}
        //   tabs={section.tabs}
        //   chartMap={chartMap} cardProps={cardProps}
        //   isMobile={isMobile} renderRows={renderRows}
        //   // onTabChange={() => setCrossFilters({})}

        //   onTabChange={(tabId, tabRows) => {
        //     setCrossFilters({});
        //     setActiveTabId(tabId);
        //     // setActiveTabChartIds(getChartIdsFromRows(tabRows));
        //     setActiveFilters(prev => {
        //       const inScope = new Set(
        //         filterDefs
        //           .filter(fd => !fd.tabsInScope?.length || fd.tabsInScope.includes(tabId))
        //           .map(fd => fd.column)
        //       );
        //       return Object.fromEntries(Object.entries(prev).filter(([col]) => inScope.has(col)));
        //     });
        //   }}
          
        //             // onTabChange={(tabId) => {
        //   //   setCrossFilters({});
        //   //   setActiveTabId(tabId);
        //   //   // Also clear filters that go out of scope
        //   //   setActiveFilters(prev => {
        //   //     const inScope = new Set(
        //   //       filterDefs
        //   //         .filter(fd => !fd.tabsInScope?.length || fd.tabsInScope.includes(tabId))
        //   //         .map(fd => fd.column)
        //   //     );
        //   //     return Object.fromEntries(Object.entries(prev).filter(([col]) => inScope.has(col)));
        //   //   });
        //   // }}

        //   pdfTabIdx={pdfTabIdx}
        //   pdfNestedTabIdx={pdfNestedTabIdx}
        // />

        <TabGroup
            key={sIdx}
            tabs={section.tabs}
            chartMap={chartMap}
            cardProps={cardProps}
            isMobile={isMobile}
            renderRows={renderRows}
            onTabChange={(tabId, tabRows) => {
              setCrossFilters({});
              setActiveTabId(tabId);
              setActiveFilters(prev => {
                const inScope = new Set(
                  filterDefs
                    .filter(fd => !fd.tabsInScope?.length || fd.tabsInScope.includes(tabId))
                    .map(fd => fd.column)
                );
                return Object.fromEntries(Object.entries(prev).filter(([col]) => inScope.has(col)));
              });
            }}
            pdfTabIdx={pdfTabIdx}
            pdfNestedTabIdx={pdfNestedTabIdx}
            dateFrom={dateFrom}
            dateTo={dateTo}
            setDateFrom={setDateFrom}
            setDateTo={setDateTo}
          />
      );
    return null;
  });

  const renderFallback = () => (
    <div style={{ display: "grid", gridTemplateColumns: isMobile ? "1fr" : "repeat(auto-fill,minmax(min(100%,480px),1fr))", gap: 12 }}>
      {charts.map(chart => <ChartCard key={chart.slice_id} {...cardProps(chart, 320)} />)}
    </div>
  );

  return (
    <div style={{ background: "#0d1117", minHeight: "100vh", padding: isMobile ? "10px" : "16px", position: "relative" }}>

      {/* PDF progress overlay */}
      <PdfProgressOverlay progress={pdfProgress} />

      <CrossFilterPills crossFilters={crossFilters} onClear={clearCrossFilter} onClearAll={clearAllCrossFilters} />

      <FilterPanel
          filterDefs={filterDefs.filter(fd => {
            if (!fd.tabsInScope || fd.tabsInScope.length === 0) return true;
            if (!activeTabId) return true;
            return fd.tabsInScope.includes(activeTabId);
          })}
          activeFilters={activeFilters}
          dateFrom={dateFrom}
          dateTo={dateTo}
          onFilterChange={handleFilterChange}
          onDateFromChange={setDateFrom}
          onDateToChange={setDateTo}
          onReset={handleReset}
        />
      <ActivePills
        activeFilters={activeFilters} dateFrom={dateFrom} dateTo={dateTo}
        // onRemove={col => setActiveFilters(p => ({ ...p, [col]: null }))}
        onRemove={(col, val) => handleFilterChange(col, val)}
        onRemoveDate={() => { setDateFrom(""); setDateTo(""); }}
      />

      {/* Charts — captured for PDF */}
      <div ref={dashboardContentRef}>
        {sections ? renderWithLayout() : renderFallback()}
      </div>

      {/* Charts */}
      {/* <div >
        {sections ? renderWithLayout() : renderFallback()}
      </div> */}

    </div>
  );
}
