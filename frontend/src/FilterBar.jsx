import React, { useState, useEffect } from "react";
import api from "./api";
import { SlidersHorizontal, RotateCcw, ChevronDown } from "lucide-react";

export default function FilterBar({
  dashboardId,
  activeFilters = {},
  dateFrom = "",
  dateTo = "",
  onFilterChange,
  onDateFromChange,
  onDateToChange,
  onReset,
}) {
  const [filterDefs, setFilterDefs] = useState([]);
  const [open,       setOpen]       = useState(false);

  useEffect(() => {
    if (!dashboardId) return;
    api
      .get("/filter-options", { params: { dashboardId } })
      .then((res) => {
        if (res.data.success) setFilterDefs(res.data.filters || []);
      })
      .catch(console.error);
  }, [dashboardId]);

  if (!filterDefs.length) return null;

  const hasActive = Object.values(activeFilters).some(Boolean) || !!dateFrom;

  return (
    <div
      style={{
        background: "#12151f",
        border: "1px solid rgba(255,255,255,0.07)",
        borderRadius: 10,
        marginBottom: 14,
        overflow: "hidden",
      }}
    >
      {/* ── Header ── */}
      <div
        onClick={() => setOpen((p) => !p)}
        style={{
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          padding: "10px 16px",
          cursor: "pointer",
          borderBottom: open ? "1px solid rgba(255,255,255,0.06)" : "none",
          userSelect: "none",
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
          <SlidersHorizontal size={13} style={{ color: "#64748b" }} />
          <span
            style={{
              fontSize: 11,
              fontWeight: 700,
              color: "#64748b",
              letterSpacing: "0.09em",
              textTransform: "uppercase",
            }}
          >
            Filters
          </span>
          {hasActive && (
            <span
              style={{
                fontSize: 9,
                background: "#1FA8C9",
                color: "#fff",
                borderRadius: 8,
                padding: "1px 6px",
                fontWeight: 700,
              }}
            >
              ACTIVE
            </span>
          )}
        </div>
        <ChevronDown
          size={14}
          style={{
            color: "#374151",
            transition: "transform .2s",
            transform: open ? "rotate(180deg)" : "rotate(0deg)",
          }}
        />
      </div>

      {/* ── Controls ── */}
      {open && (
        <div
          style={{
            padding: "14px 16px",
            display: "flex",
            flexDirection: "column",
            gap: 16,
          }}
        >
          {filterDefs.map((fd) => {

            // ── Date filter ──────────────────────────────────
            if (fd.type === "date")
              return (
                <div key={fd.id}>
                  <Label>{fd.name}</Label>
                  <div style={{ display: "flex", alignItems: "center", gap: 7 }}>
                    <DateInput
                      value={dateFrom}
                      onChange={(e) => onDateFromChange(e.target.value)}
                    />
                    <span style={{ fontSize: 11, color: "#2d3748" }}>→</span>
                    <DateInput
                      value={dateTo}
                      onChange={(e) => onDateToChange(e.target.value)}
                    />
                  </div>
                </div>
              );

            // ── Select filter (pill buttons) ─────────────────
            if (fd.type === "select")
              return (
                <div key={fd.id}>
                  <Label>{fd.name}</Label>

                  {/*
                   * Fixed-height scroll container.
                   * ~4 rows of pills ≈ 132px:
                   *   each pill row ≈ 28px (pill height 26px + gap 5px) × 4 = 112px
                   *   + a bit of breathing room = 132px
                   */}
                  <div
                    style={{
                      maxHeight: 132,
                      overflowY: "auto",
                      overflowX: "hidden",
                      paddingRight: 4,           // room for scrollbar
                      paddingBottom: 4,

                      // Custom thin scrollbar
                      scrollbarWidth: "thin",
                      scrollbarColor: "#2d3748 transparent",
                    }}
                  >
                    {/* Webkit scrollbar styling */}
                    <style>{`
                      .filter-pill-scroll::-webkit-scrollbar {
                        width: 4px;
                      }
                      .filter-pill-scroll::-webkit-scrollbar-track {
                        background: transparent;
                      }
                      .filter-pill-scroll::-webkit-scrollbar-thumb {
                        background: #2d3748;
                        border-radius: 4px;
                      }
                      .filter-pill-scroll::-webkit-scrollbar-thumb:hover {
                        background: #374151;
                      }
                    `}</style>

                    <div
                      className="filter-pill-scroll"
                      style={{
                        display: "flex",
                        flexWrap: "wrap",
                        gap: 5,
                        maxHeight: 132,
                        overflowY: "auto",
                        overflowX: "hidden",
                        paddingRight: 4,
                        scrollbarWidth: "thin",
                        scrollbarColor: "#2d3748 transparent",
                      }}
                    >
                      {fd.values.map((val) => {
                        const active = activeFilters[fd.column] === val;
                        return (
                          <button
                            key={val}
                            onClick={() =>
                              onFilterChange && onFilterChange(fd.column, val)
                            }
                            style={{
                              padding: "4px 11px",
                              borderRadius: 16,
                              fontSize: 11,
                              fontWeight: 600,
                              cursor: "pointer",
                              border: "1px solid",
                              outline: "none",
                              flexShrink: 0,
                              transition: "all .15s ease",
                              background: active
                                ? "#1FA8C9"
                                : "rgba(31,168,201,0.08)",
                              color:      active ? "#fff" : "#5ba8b9",
                              borderColor: active
                                ? "#1FA8C9"
                                : "rgba(31,168,201,0.22)",
                            }}
                          >
                            {val}
                          </button>
                        );
                      })}
                    </div>
                  </div>

                  {/* Scroll hint — only shown when list is long */}
                  {fd.values.length > 20 && (
                    <p style={{
                      fontSize: 9,
                      color: "#374151",
                      marginTop: 5,
                      letterSpacing: "0.06em",
                    }}>
                      {fd.values.length} options · scroll to see more
                    </p>
                  )}
                </div>
              );

            return null;
          })}

          {/* ── Reset button ── */}
          <div>
            <ResetBtn onClick={onReset} />
          </div>
        </div>
      )}
    </div>
  );
}

// ─── Helper components ────────────────────────────────────────
function Label({ children }) {
  return (
    <p
      style={{
        fontSize: 10,
        color: "#475569",
        textTransform: "uppercase",
        letterSpacing: "0.08em",
        marginBottom: 7,
        fontWeight: 700,
      }}
    >
      {children}
    </p>
  );
}

function DateInput({ value, onChange }) {
  return (
    <input
      type="date"
      value={value}
      onChange={onChange}
      style={{
        background: "#0d1117",
        border: "1px solid #2d3748",
        borderRadius: 7,
        padding: "5px 9px",
        fontSize: 11,
        color: "#94a3b8",
        width: 132,
        outline: "none",
        cursor: "pointer",
      }}
    />
  );
}

function ResetBtn({ onClick }) {
  const [hover, setHover] = useState(false);
  return (
    <button
      onClick={onClick}
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
      style={{
        display: "flex",
        alignItems: "center",
        gap: 5,
        padding: "6px 13px",
        borderRadius: 7,
        fontSize: 11,
        fontWeight: 600,
        border: `1px solid ${hover ? "#475569" : "#2d3748"}`,
        color:      hover ? "#94a3b8" : "#64748b",
        background: "transparent",
        cursor: "pointer",
        transition: "all .15s",
      }}
    >
      <RotateCcw size={11} />
      Reset
    </button>
  );
}