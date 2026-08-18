import React, { useState, useEffect, useRef } from "react";
import ReactECharts from "echarts-for-react";
import api from "./api";
import PivotTable from "./PivotTable";

const COLORS = [
  "#1FA8C9","#454E7C","#FF7F44","#66C4DA","#E04355",
  "#FCC700","#A868B7","#3CCCCB","#A38F79","#8FD3E4",
  "#D3B0C7","#5AC189","#3498DB","#E67E22","#16A085",
  "#8E44AD","#27AE60","#E74C3C","#F39C12","#2C3E50",
];

const ID_COL_PATTERN = /pincode|zip|postal|pin_code|order_id|invoice|phone|mobile|id$/i;


function useChartHeight(defaultHeight) {
  const [height, setHeight] = useState(defaultHeight);
  useEffect(() => {
    const update = () => {
      const h = window.innerHeight;
      if (h < 420)      setHeight(Math.max(160, Math.floor(h * 0.55)));
      else if (h < 600) setHeight(Math.max(200, Math.floor(h * 0.60)));
      else              setHeight(defaultHeight);
    };
    update();
    window.addEventListener("resize", update);
    window.addEventListener("orientationchange", update);
    return () => {
      window.removeEventListener("resize", update);
      window.removeEventListener("orientationchange", update);
    };
  }, [defaultHeight]);
  return height;
}

function buildFilterPayload(crossFilters, ownSliceId, isTable = false) {
  return Object.entries(crossFilters)
    .filter(([, f]) => f.sourceChartId !== ownSliceId && f.value != null && f.value !== "")
    .filter(([, f]) => isTable || !f.fromTable)
    .map(([col, f]) => ({
      col,
      op:  "IN",
      val: [f.value],
    }));
}

const getChartType = (vt = "") => {
  const v = vt.toLowerCase();
  if (v.includes("table") || v.includes("pivot")) return "table";
  if (v.includes("pie"))                           return "pie";
  if (v.includes("line"))                          return "line";
  if (v.includes("area"))                          return "area";
  if (v.includes("bar") || v.includes("column"))   return "bar";
  if (v.includes("mixed"))                         return "mixed";
  if (v.includes("big_number"))                    return "bignum";
  if (v.includes("treemap"))                       return "treemap";
  if (v.includes("scatter"))                       return "scatter";
  if (v.includes("funnel"))                        return "funnel";
  if (v.includes("heatmap"))                       return "heatmap";
  return "bar";
};

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

// Indian-numbering abbreviation, used everywhere numbers are shown across
// the app (bar/line/pie labels, tooltips, axis labels, BigNumber cards):
//   0 – 999            → plain number
//   1,000 – 99,999     → "K"  (÷1,000)
//   1,00,000 – 99,99,999  → "L"  (÷1,00,000)  — Lakh
//   1,00,00,000+       → "Cr" (÷1,00,00,000)  — Crore
// No "M"/"B" abbreviations are ever used.
const fmtIndianScale = (n) => {
  const abs = Math.abs(n);
  if (abs === 0) return "0";
  if (abs < 5000) return parseFloat(n.toFixed(2)).toString();
  if (abs < 1e5)  return si3(n, 1e3, "K");
  if (abs < 1e7)  return si3(n, 1e5, "L");
  return si3(n, 1e7, "Cr");
};

const fmtNum = (v, colName = "") => {
  const n = Number(v);
  if (isNaN(n)) return String(v ?? "");
  if (isTimestampMs(n)) return fmtDateMs(n);

  if (colName && ID_COL_PATTERN.test(colName)) {
    return Number.isInteger(n) ? String(n) : n.toFixed(2);
  }

  return fmtIndianScale(n);
};

const fmtAxisLabel = (v) => {
  if (v == null) return "";
  const n = Number(v);
  if (isTimestampMs(n)) return fmtDateMs(n);
  const s = String(v);
  if (s.match(/^\d{4}-\d{2}-\d{2}/) || s.includes("T00:00:00")) {
    try {
      const d = new Date(v);
      if (!isNaN(d.getTime()))
        return d.toLocaleDateString("en-IN", { month: "short", year: "2-digit" });
    } catch { /**/ }
  }
  if (/^\d{4}-Q\d$/.test(s)) return s;
  return s.length > 16 ? s.slice(0, 15) + "…" : s;
};


// const PCT_KEYWORDS = /change|pct|percent|%|ratio|rate|growth|nullif|case when/i;
// const isRatioValue = (n, label = "") =>
//   Math.abs(n) > 0 && Math.abs(n) < 2 && PCT_KEYWORDS.test(label);
// const fmtBigNum = (rawVal, label = "") => {
//   const n = Number(rawVal);
//   if (isNaN(n)) return String(rawVal ?? "");
//   if (isTimestampMs(n)) return fmtDateMs(n);
//   if (isRatioValue(n, label)) {
//     const pct = n * 100, abs = Math.abs(pct);
//     return (abs >= 10 ? pct.toFixed(1) : pct.toFixed(2)).replace(/\.?0+$/, "") + "%";
//   }
//   return fmtIndianScale(n);
// };


// const PCT_KEYWORDS =
//   /change|pct|percent|%|percentage|ratio|rate|growth|margin|share|nullif|case when/i;

// const isPercentageMetric = (label = "") =>
//   PCT_KEYWORDS.test(String(label));

// const isRatioValue = (n, label = "") =>
//   isPercentageMetric(label) && Number.isFinite(n);

// const fmtPercentage = (n) => {
//   // If the value is between -1 and 1, treat it as a ratio.
//   // Example: 0.1234 -> 12.34%
//   //
//   // If the value is already greater than 1 or less than -1,
//   // treat it as an already-percentage value.
//   // Example: 12.34 -> 12.34%

//   const pct = Math.abs(n) <= 1 ? n * 100 : n;

//   return `${pct.toFixed(2)}%`;
// };

// const fmtBigNum = (rawVal, label = "") => {
//   const n = Number(rawVal);

//   if (isNaN(n)) return String(rawVal ?? "");

//   if (isTimestampMs(n)) return fmtDateMs(n);

//   // Percentage metrics
//   if (isPercentageMetric(label)) {
//     return fmtPercentage(n);
//   }

//   // Normal numbers
//   return fmtIndianScale(n);
// };


const PCT_KEYWORDS =
  /change|pct|percent|percentage|%|ratio|rate|growth|margin|share|nullif|case\s+when/i;


/**
 * Detect whether a metric represents a percentage.
 *
 * We check the metric label AND chart title because Superset
 * may return a metric column name that doesn't contain "%".
 */
const isPercentageMetric = (label = "") => {
  return PCT_KEYWORDS.test(String(label));
};


/**
 * Format percentage values.
 *
 * Supports both common backend representations:
 *
 * 0.611  -> 61.10%
 * 0.4567 -> 45.67%
 * 61.1   -> 61.10%
 * -5.25  -> -5.25%
 */
const fmtPercentage = (n) => {
  if (!Number.isFinite(n)) return "";

  const percentage = Math.abs(n) <= 1
    ? n * 100
    : n;

  return `${percentage.toFixed(2)}%`;
};


/**
 * Main Big Number formatter.
 */
const fmtBigNum = (rawVal, label = "") => {
  const n = Number(rawVal);

  if (!Number.isFinite(n)) {
    return String(rawVal ?? "");
  }

  if (isTimestampMs(n)) {
    return fmtDateMs(n);
  }

  // Percentage metric
  if (isPercentageMetric(label)) {
    return fmtPercentage(n);
  }

  // Normal number
  return fmtIndianScale(n);
};





const SQL_EXPR = /SUM\s*\(CASE WHEN|NULLIF\s*\(|CASE WHEN/i;
const cleanMetricLabel = (label = "") => {
  const l = label.trim();
  if (!l) return "";
  if (SQL_EXPR.test(l)) {
    if (/change|growth/i.test(l))    return "% Change";
    if (/ratio|rate/i.test(l))       return "Rate";
    if (/quantity|qty/i.test(l))     return "Qty Change";
    if (/net|amount|sales/i.test(l)) return "Net Sales Change";
    return "Calculated Metric";
  }
  return l.length > 42 ? l.slice(0, 40) + "…" : l;
};

const extractMetricLabels = (metrics = []) =>
  (metrics || []).map(m => {
    if (!m) return null;
    if (typeof m === "string") return m;
    if (m.label) return m.label;
    if (m.expressionType === "SIMPLE" && m.aggregate && m.column?.column_name)
      return `${m.aggregate}(${m.column.column_name})`;
    if (m.sqlExpression) return m.label || m.sqlExpression;
    return null;
  }).filter(Boolean);

function looksLikeDimension(v) {
  if (v === null || v === undefined) return false;
  if (typeof v === "string") return true;
  const n = Number(v);
  if (isNaN(n)) return true;
  if (isTimestampMs(n)) return true;
  const abs = Math.abs(n);
  if (abs <= 100000) return true;
  if (Number.isInteger(n) && abs >= 190001 && abs <= 209912) return true;
  return false;
}

const normalise = (s) => String(s ?? "").toLowerCase().replace(/\s+/g, "").replace(/[()]/g, "");

const detectXKey = (rows, xAxisProp, metricLabels, groupbyProp) => {
  if (!rows?.length) return "__seq__";
  const cols = Object.keys(rows[0]);

  let xAxisStr = xAxisProp;
  if (xAxisProp && typeof xAxisProp === "object") {
    xAxisStr = (
      xAxisProp.column_name ||
      xAxisProp.label       ||
      xAxisProp.name        ||
      ""
    );
  }
  xAxisStr = xAxisStr ? String(xAxisStr) : "";

  if (xAxisStr && cols.includes(xAxisStr) && looksLikeDimension(rows[0][xAxisStr]))
    return xAxisStr;

  if (cols.includes("__timestamp")) return "__timestamp";

  if (xAxisStr) {
    const lower = xAxisStr.toLowerCase();
    const ci    = cols.find(c => c.toLowerCase() === lower);
    if (ci && looksLikeDimension(rows[0][ci])) return ci;
  }

  const metricSet = new Set(metricLabels);

  const gb0    = Array.isArray(groupbyProp) ? groupbyProp[0] : null;
  const gbName = typeof gb0 === "string"
    ? gb0
    : gb0?.column_name || gb0?.column?.column_name;
  if (gbName && cols.includes(gbName) && looksLikeDimension(rows[0][gbName]))
    return gbName;

  const nonMetric = cols.filter(k => !metricSet.has(k));

  const dateNameCol = nonMetric.find(k =>
    !k.includes(" ") &&
    /date|time|month|quarter|year|period|day|week/i.test(k)
  );
  if (dateNameCol) return dateNameCol;

  const tsValueCol = nonMetric.find(k => isTimestampMs(rows[0][k]));
  if (tsValueCol) return tsValueCol;

  const strCol = nonMetric.find(k => typeof rows[0][k] === "string");
  if (strCol) return strCol;

  const dimCol = nonMetric.find(k => looksLikeDimension(rows[0][k]));
  if (dimCol) return dimCol;

  return cols.find(k => looksLikeDimension(rows[0][k])) ?? "__seq__";
};

const detectSeriesKeys = (rows, xKey, metricLabels) => {
  if (!rows?.length) return [];
  const cols     = Object.keys(rows[0]);
  const excluded = new Set([xKey, "__timestamp", "__seq__"]);
  if (metricLabels.length) {
    const exact = metricLabels.filter(m => cols.includes(m));
    if (exact.length === metricLabels.length) return exact;
    const fuzzy = metricLabels.map(m => {
      if (cols.includes(m)) return m;
      const norm = normalise(m);
      return cols.find(c => !excluded.has(c) && normalise(c) === norm) ?? null;
    }).filter(Boolean);
    if (fuzzy.length) return fuzzy;
  }
  return cols.filter(k => {
    if (excluded.has(k)) return false;
    return rows.some(r => {
      const v = r[k];
      if (v === null || v === undefined || v === "") return false;
      if (isNaN(Number(v))) return false;
      if (isTimestampMs(Number(v))) return false;
      return true;
    });
  });
};

const Skeleton = ({ height }) => (
  <div style={{ height, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 14 }}>
    <div style={{ display: "flex", alignItems: "flex-end", gap: 3, height: 64 }}>
      {[35, 62, 48, 80, 55, 38, 70, 44, 60, 42].map((h, i) => (
        <div key={i} style={{ width: 9, height: `${h}%`, borderRadius: "2px 2px 0 0",
          background: i % 3 === 0 ? "#1FA8C9" : i % 3 === 1 ? "#454E7C" : "#3CCCCB",
          animation: `skbar 0.9s ${i * 0.07}s ease-in-out infinite alternate`, opacity: 0.45 }} />
      ))}
    </div>
    <span style={{ fontSize: 11, color: "#4a5568", letterSpacing: "0.06em" }}>Loading analytics...</span>
    <style>{`@keyframes skbar{from{opacity:.12;transform:scaleY(.3)}to{opacity:.7;transform:scaleY(1)}}`}</style>
  </div>
);

const darkTooltip = {
  backgroundColor: "#12151f", borderColor: "rgba(255,255,255,0.08)", borderWidth: 1,
  textStyle: { color: "#e2e8f0", fontSize: 11, fontFamily: "inherit" },
  extraCssText: "box-shadow:0 12px 40px rgba(0,0,0,0.7);border-radius:8px;padding:10px 14px;",
};

// Single-series hover tooltip — shows ONLY the item under the cursor,
// not every series at that x-position. Used by both bar and line charts
// so hovering one bar/point never dumps a long stacked list of every
// category's value.
const singleItemTooltip = {
  trigger: "item", ...darkTooltip,
  formatter: (p) =>
    `<div style="color:#64748b;font-size:10px;margin-bottom:4px;font-weight:600">${p.name}</div>
     <div style="display:flex;align-items:center;gap:6px">
       <span style="display:inline-block;width:8px;height:8px;border-radius:50%;background:${p.color}"></span>
       <span style="color:#94a3b8;font-size:10px;flex:1">${p.seriesName}</span>
       <span style="color:#e2e8f0;font-weight:600;padding-left:12px">${fmtNum(p.value)}</span>
     </div>`,
};

const axisX = (cats) => ({
  type: "category", data: cats,
  axisLine: { lineStyle: { color: "#2d3748" } }, axisTick: { show: false },
  axisLabel: {
  color:      "#8b9ab0",
  fontSize:   11,
  fontFamily: "inherit",
  interval: 0,
  formatter: function(val) {
    if (!val) return val;
    const d = new Date(val);
    if (!isNaN(d.getTime())) {
      const mon = d.toLocaleDateString("en-IN", { month: "short" });
      const yr  = String(d.getFullYear()).slice(2);
      return `${mon}-${yr}`;
    }
    return val;
  },
},
  splitLine: { show: false },
});


const axisY = () => ({
  type: "value", axisLine: { show: false }, axisTick: { show: false },
  axisLabel: { color: "#8b9ab0", fontSize: 10, fontFamily: "inherit", formatter: fmtNum },
  splitLine: { lineStyle: { color: "rgba(255,255,255,0.05)", type: "dashed" } },
});
const scrollLegend = (keys) => ({
  type: "scroll", orient: "horizontal", bottom: 6,
  left: "center",
  pageIconColor: "#8b9ab0", pageIconInactiveColor: "#2d3748",
  pageTextStyle: { color: "#8b9ab0", fontSize: 12 },
  textStyle: { color: "#8b9ab0", fontSize: 13, fontFamily: "inherit" },
  icon: "circle", itemHeight: 10, itemGap: 16, show: keys.length >= 1,
});

    function buildOption({ 
      type, data, keys, xKey, selectedValue, 
      initialKeys = [], zoomable = false,
      percentageThreshold = 0,
      otherThreshold      = 0,
      seriesColors        = {},
      seriesTypesProp     = null,
    }) {

    const getColor = (key, fallbackIndex) => {
      if (seriesColors[key]) return seriesColors[key];
      if (initialKeys.length > 0) {
        const origIdx = initialKeys.indexOf(key);
        if (origIdx >= 0) return COLORS[origIdx % COLORS.length];
      }
      return COLORS[fallbackIndex % COLORS.length];
    };

  const cats = xKey === "__seq__"
    ? data.map((_, i) => String(i + 1))
    : data.map(r => fmtAxisLabel(r[xKey]));

  const base = {
    backgroundColor: "transparent", animation: true,
    color: keys.map((k, i) => getColor(k, i)),
    animationDuration: 550, animationEasing: "cubicOut",
    legend: scrollLegend(keys),
    // ── Multi-series "axis" tooltip (shows every series stacked at once) ──
    // Kept here for chart types that still want it (mixed, treemap, funnel, etc).
    // Bar and line charts explicitly override this below with singleItemTooltip
    // so hovering shows only the one bar/point under the cursor.
    tooltip: {
      trigger: "axis", ...darkTooltip,
      axisPointer: { lineStyle: { color: "rgba(255,255,255,0.08)" } },
      formatter(params) {
        const label = params[0]?.axisValue ?? "";
        let html = `<div style="color:#64748b;font-size:10px;margin-bottom:5px;font-weight:600">${label}</div>`;
        params.forEach(p => {
          html += `<div style="display:flex;align-items:center;gap:6px;margin:2px 0">
            <span style="display:inline-block;width:8px;height:8px;border-radius:50%;background:${p.color}"></span>
            <span style="color:#94a3b8;font-size:10px;flex:1">${p.seriesName}</span>
            <span style="color:#e2e8f0;font-weight:600;padding-left:12px">${fmtNum(p.value)}</span>
          </div>`;
        });
        return html;
      },
    },
    grid: { left: 12, right: 40, top: 36, bottom: 72, containLabel: true },
  };

  const sData = k => data.map(r => {
    const v = r[k];
    return (v === null || v === undefined) ? null : Number(v) || 0;
  });
  const dimmedColor = (baseColor, catLabel) => {
    if (!selectedValue) return baseColor;
    return catLabel === selectedValue ? baseColor : baseColor + "44";
  };

    if (type === "heatmap") {
        const cols    = Object.keys(data[0]);
        const numCols = cols.filter(k =>
          data.some(r => r[k] !== null && r[k] !== undefined && !isNaN(Number(r[k])))
        );
        const dimCols = cols.filter(k => !numCols.includes(k));

        const xCol   = dimCols[0] || cols[0];
        const yCol   = dimCols[1] || cols[1];
        const valCol = numCols[0] || cols[2];

        const xVals = [...new Set(data.map(r => String(r[xCol] ?? "")))];
        const yVals = [...new Set(data.map(r => String(r[yCol] ?? "")))];

        const heatData = data.map(r => [
          xVals.indexOf(String(r[xCol] ?? "")),
          yVals.indexOf(String(r[yCol] ?? "")),
          Number(r[valCol]) || 0,
        ]);

        const allValues = heatData.map(d => d[2]);
        const minVal    = Math.min(...allValues);
        const maxVal    = Math.max(...allValues);

        return {
          backgroundColor: "transparent",
          animation: true,
          tooltip: {
            ...darkTooltip,
            formatter: (p) =>
              `<div style="color:#64748b;font-size:10px;margin-bottom:4px">
                ${xVals[p.data[0]]} · ${yVals[p.data[1]]}
              </div>
              <span style="color:#e2e8f0;font-weight:700;font-size:14px">
                ${fmtNum(p.data[2])}
              </span>`,
          },
          grid: { left: 80, right: 60, top: 70, bottom: 70, containLabel: false },
          xAxis: {
              type: "category",
              data: xVals,
              axisLine:  { lineStyle: { color: "#2d3748" } },
              axisTick:  { show: false },
              axisLabel: {
                color:      "#e2e8f0",
                fontSize:   14,
                fontWeight: "bold",
                fontFamily: "inherit",
              },
              splitArea: { show: true, areaStyle: {
                color: ["rgba(255,255,255,0.02)", "rgba(255,255,255,0.0)"]
              }},
            },
          yAxis: {
              type: "category",
              data: yVals,
              axisLine:  { lineStyle: { color: "#2d3748" } },
              axisTick:  { show: false },
              axisLabel: {
                color:      "#e2e8f0",
                fontSize:   14,
                fontWeight: "bold",
                fontFamily: "inherit",
              },
              splitArea: { show: true, areaStyle: {
                color: ["rgba(255,255,255,0.02)", "rgba(255,255,255,0.0)"]
              }},
            },
            
          visualMap: {
            min:          minVal,
            max:          maxVal,
            calculable:   true,
            orient:       "horizontal",
            left:         "center",
            top:          8,
            textGap:    20,
            inRange: {
              color: [
                "#7f0000",
                "#c62828",
                "#e53935",
                "#ef6c00",
                "#f9a825",
                "#f9f000",
              ],
            },
            textStyle:    { color: "#8b9ab0", fontSize: 25, fontFamily: "inherit", fontWeight: "600", padding:  [6, 0, 0, 0], },
            itemWidth:    14,
            itemHeight:   120,
          },
          series: [{
            type:       "heatmap",
            data:       heatData,
            label: {
                show:       true,
                fontSize:   14,
                fontWeight: "bold",
                color:      "#ffffff",
                textShadowColor:   "#000000",
                textShadowBlur:    8,
                textShadowOffsetX: 0,
                textShadowOffsetY: 0,
                formatter: function(params) {
                  var v = params.data[2];
                  if (v === null || v === undefined) return "";
                  return String(v);
                },
              },
            emphasis: {
              itemStyle: {
                shadowBlur:  10,
                shadowColor: "rgba(0, 0, 0, 0.5)",
              },
            },
          }],
        };
      }


      if (type === "pie") {
  const numKey = keys.find(k => data.some(r => !isNaN(Number(r[k])) && r[k] != null)) || keys[0];
  const total  = data.reduce((s, r) => s + (Number(r[numKey]) || 0), 0);

  let finalData;
  if (otherThreshold > 0) {
    const mainSlices  = [];
    const otherSlices = [];

    data.forEach((r, i) => {
      const name  = String(r[xKey] ?? "");
      const val   = Number(r[numKey]) || 0;
      const pct   = total > 0 ? (val / total) * 100 : 0;
      const color = COLORS[i % COLORS.length];
      if (pct < otherThreshold) {
        otherSlices.push({ name, value: val, color });
      } else {
        mainSlices.push({ name, value: val, color });
      }
    });

    finalData = mainSlices.map(s => ({
      name:  s.name,
      value: s.value,
      itemStyle: {
        color:       selectedValue && s.name !== selectedValue ? s.color + "44" : s.color,
        borderWidth: s.name === selectedValue ? 2 : 0,
        borderColor: "#1FA8C9",
      },
    }));

    if (otherSlices.length > 0) {
      const otherVal = otherSlices.reduce((sum, s) => sum + s.value, 0);
      finalData.push({
        name:  `Other (${otherSlices.length})`,
        value: otherVal,
        itemStyle: { color: "#4a5568" },
      });
    }

  } else {
    finalData = data.map((r, i) => {
      const name  = String(r[xKey] ?? "");
      const color = COLORS[i % COLORS.length];
      return {
        name,
        value: Number(r[numKey]) || 0,
        itemStyle: {
          color:       selectedValue && name !== selectedValue ? color + "44" : color,
          borderWidth: name === selectedValue ? 2 : 0,
          borderColor: "#1FA8C9",
        },
      };
    });
  }

  return {
    ...base,
    legend: {
      ...scrollLegend(finalData.map(r => r.name)),
      bottom: 2,
      selector: [
        { type: "all",     title: "All"  },
        { type: "inverse", title: "Inv"  }
      ],
      selectorPosition: "end",
      selectorLabel: {
        fontSize:        10,
        padding:         [3, 8],
        borderRadius:    4,
        color:           "#8b9ab0",
        borderColor:     "rgba(255,255,255,0.18)",
        backgroundColor: "rgba(255,255,255,0.04)",
      },
      selectorItemGap: 6,
    },
    tooltip: {
      trigger: "item", ...darkTooltip,
      formatter: p =>
        `<div style="color:#94a3b8;font-size:11px;font-weight:600;margin-bottom:4px">${p.name}</div>
         <span style="color:${p.color};font-size:14px;font-weight:700">${fmtNum(p.value)}</span>
         <span style="color:#64748b;font-size:10px"> · ${p.percent.toFixed(1)}%</span>`,
    },
    graphic: [{
      type: "text", left: "center", top: "center",
      style: {
        text: `Total\n${fmtNum(total)}`,
        textAlign:  "center", fontSize: 11,
        fill:       "#94a3b8", lineHeight: 20,
        fontWeight: "600", fontFamily: "inherit"
      },
    }],
    series: [{
      type:      "pie",
      radius:    ["40%", "70%"],
      center:    ["50%", "46%"],
      padAngle:  2,
      itemStyle: { borderRadius: 4, borderWidth: 0 },
      label: {
        show:     true,
        color:    "#8b9ab0",
        fontSize: 10,
        fontFamily: "inherit",
        overflow: "truncate",
        width:    80,
        formatter: p => {
          if (percentageThreshold > 0 && p.percent < percentageThreshold) return "";
          return `${p.name}\n${fmtNum(p.value)}`;
        },
      },
      labelLine: { lineStyle: { color: "#334155" } },
      emphasis:  {
        scale: true, scaleSize: 5,
        itemStyle: { shadowBlur: 20, shadowColor: "rgba(0,0,0,0.6)" }
      },
      data: finalData,
    }],
  };
}


  if (type === "bar") {
    const sortedKeys = [...keys].sort((a, b) =>
      String(a).localeCompare(String(b), undefined, { numeric: true, sensitivity: "base" })
    );

    const isGrouped  = keys.length > 1;
    const showLabels = data.length <= 1150;
    const labelRotate = data.length > 35 ? 45 : 0; 
    return {
      ...base,
      // ← Overrides base's multi-series "axis" tooltip. Hovering a single
      // bar now shows only that bar's series/value, not every series
      // stacked at that x-position.
      tooltip: singleItemTooltip,
       legend: {
          ...scrollLegend(sortedKeys),
          selector: [
            { type: "all",     title: "All" },
            { type: "inverse", title: "Inv" }
          ],
          selectorPosition: "end",
          selectorLabel: {
            fontSize: 10,
            padding:  [3, 8],
            borderRadius:     4,
            color:            "#8b9ab0",
            borderColor:      "rgba(255,255,255,0.18)",
            backgroundColor:  "rgba(255,255,255,0.04)",
          },
          selectorItemGap: 6,
        }, 

    ...(zoomable ? {
      grid: { left: 12, right: 40, top: 36, bottom: 110, containLabel: true },
      dataZoom: [
        {
          type:            "slider",
          xAxisIndex:      [0],
          bottom:          36,
          height:          22,
          borderColor:     "rgba(255,255,255,0.08)",
          backgroundColor: "rgba(255,255,255,0.03)",
          fillerColor:     "rgba(31,168,201,0.18)",
          handleStyle:     { color: "#1FA8C9", borderColor: "#1FA8C9" },
          moveHandleStyle: { color: "#1FA8C9" },
          textStyle:       { color: "#64748b", fontSize: 10 },
          dataBackground: {
            lineStyle: { color: "#1FA8C9", opacity: 0.25 },
            areaStyle: { color: "#1FA8C9", opacity: 0.08 },
          },
          selectedDataBackground: {
            lineStyle: { color: "#1FA8C9", opacity: 0.6 },
            areaStyle: { color: "#1FA8C9", opacity: 0.2 },
          },
        },
        {
          type:       "inside",
          xAxisIndex: [0],
        },
      ],
    } : {}),

      xAxis: axisX(cats), yAxis: axisY(),
      series: sortedKeys.map((k, i) => ({
        type: "bar", name: k,
        itemStyle: { color: getColor(k, i) }, 
        barCategoryGap: isGrouped ? "20%" : "30%",
        barGap: isGrouped ? "5%" : "30%",
        ...(isGrouped ? {} : { barMaxWidth: 48 }),
        data: sData(k).map((val, ci) => ({
          value: val,
          itemStyle: { color: dimmedColor(getColor(k, i), cats[ci]), borderRadius: [4, 4, 0, 0] },
        })),
        label: { 
          show: showLabels, 
          position: "top",
          color: "#94a3b8", 
          distance: 8,
          fontSize: 9, 
          fontFamily: "inherit", 
          fontWeight: "600", 
          formatter: p => fmtNum(p.value), 
          rotate: labelRotate, 
        },
        emphasis: { focus: "series" },
      })),
    };
  }


// if (type === "mixed") {
//   const showLabels = true;

//   const seriesWithMag = keys.map(k => {
//     const avg = data.reduce((s, r) => s + (Math.abs(Number(r[k])) || 0), 0) / (data.length || 1);
//     return { key: k, avg };
//   }).sort((a, b) => b.avg - a.avg);

//   const leftKey  = seriesWithMag[0]?.key ?? keys[0];
//   const rightKey = seriesWithMag[1]?.key ?? keys[1];

//   const axisYLeft = () => ({
//     type: "value",
//     axisLine:  { show: false },
//     axisTick:  { show: false },
//     axisLabel: { color: "#8b9ab0", fontSize: 10, fontFamily: "inherit", formatter: fmtNum },
//     splitLine: { lineStyle: { color: "rgba(255,255,255,0.05)", type: "dashed" } },
//     nameTextStyle: { color: "#8b9ab0", fontSize: 9 },
//   });

//   const axisYRight = () => ({
//     type: "value",
//     axisLine:  { show: false },
//     axisTick:  { show: false },
//     axisLabel: { color: "#8b9ab0", fontSize: 10, fontFamily: "inherit", formatter: fmtNum },
//     splitLine: { show: false },
//     nameTextStyle: { color: "#8b9ab0", fontSize: 9 },
//   });

//   return {
//     ...base,
//     grid: { left: 12, right: 40, top: 36, bottom: 60, containLabel: true },
//     xAxis: axisX(cats),
//     yAxis: [axisYLeft(), axisYRight()],

//     legend: {
//       type: "scroll",
//       orient: "horizontal",
//       bottom: 4,
//       icon: "circle",
//       itemHeight: 10,
//       itemGap: 24,
//       textStyle: { color: "#8b9ab0", fontSize: 11, fontFamily: "inherit" },
//       data: [
//         { name: leftKey,  icon: "circle", itemStyle: { color: getColor(leftKey,  0) } },
//         { name: rightKey, icon: "circle", itemStyle: { color: getColor(rightKey, 1) } },
//       ],
//       formatter: (name) => {
//         if (name === leftKey)  return `${name}  ← Left`;
//         if (name === rightKey) return `${name}  Right →`;
//         return name;
//       },
//     },

//     series: [
//       {
//         type: "bar",
//         name: leftKey,
//         yAxisIndex: 0,
//         barCategoryGap: "20%",
//         barGap: "5%",
//         data: sData(leftKey).map((val) => ({
//           value: val,
//           itemStyle: { color: getColor(leftKey,  0), borderRadius: [4, 4, 0, 0] },
//         })),
//         label: {
//           show: showLabels,
//           position: "top",
//           color: "#94a3b8",
//           fontSize: 9,
//           fontFamily: "inherit",
//           fontWeight: "600",
//           formatter: p => fmtNum(p.value),
//         },
//         emphasis: { focus: "series" },
//       },
//       {
//         type: "bar",
//         name: rightKey,
//         yAxisIndex: 1,
//         barCategoryGap: "20%",
//         barGap: "5%",
//         data: sData(rightKey).map((val) => ({
//           value: val,
//           itemStyle: { color: getColor(rightKey, 1), borderRadius: [4, 4, 0, 0] },
          
//         })),
//         label: {
//           show: showLabels,
//           position: "top",
//           color: "#94a3b8",
//           fontSize: 9,
//           fontFamily: "inherit",
//           fontWeight: "600",
//           formatter: p => fmtNum(p.value),
//         },
//         emphasis: { focus: "series" },
//       },
//     ],
//   };
// }

if (type === "mixed") {
  const showLabels = true;

  const seriesWithMag = keys.map(k => {
    const avg = data.reduce((s, r) => s + (Math.abs(Number(r[k])) || 0), 0) / (data.length || 1);
    return { key: k, avg };
  }).sort((a, b) => b.avg - a.avg);

  const leftKey  = seriesWithMag[0]?.key ?? keys[0];
  const rightKey = seriesWithMag[1]?.key ?? keys[1];

  // seriesTypesProp comes straight from Superset's own Query A (seriesType)
  // and Query B (seriesTypeB) form_data controls, normalized to "bar"/"line"/"area"
  // on the backend. Falls back to bar+line if not supplied.
  const [leftType, rightType] =
    (Array.isArray(seriesTypesProp) && seriesTypesProp.length === 2)
      ? seriesTypesProp
      : ["bar", "line"];

  const axisYLeft = () => ({
    type: "value",
    axisLine:  { show: false },
    axisTick:  { show: false },
    axisLabel: { color: "#8b9ab0", fontSize: 10, fontFamily: "inherit", formatter: fmtNum },
    splitLine: { lineStyle: { color: "rgba(255,255,255,0.05)", type: "dashed" } },
    nameTextStyle: { color: "#8b9ab0", fontSize: 9 },
  });

  // const axisYRight = () => ({
  //   type: "value",
  //   axisLine:  { show: false },
  //   axisTick:  { show: false },
  //   axisLabel: { color: "#8b9ab0", fontSize: 10, fontFamily: "inherit", formatter: fmtNum },
  //   splitLine: { show: false },
  //   nameTextStyle: { color: "#8b9ab0", fontSize: 9 },
  // });

  const niceCeil = (n) => {
    if (n <= 0) return 10;
    const magnitude = Math.pow(10, Math.floor(Math.log10(n)));
    const normalized = n / magnitude;
    let niceNorm;
    if (normalized <= 1)      niceNorm = 1;
    else if (normalized <= 2) niceNorm = 2;
    else if (normalized <= 2.5) niceNorm = 2.5;
    else if (normalized <= 5) niceNorm = 5;
    else                       niceNorm = 10;
    return niceNorm * magnitude;
  };

  const rightDataMax = Math.max(...sData(rightKey).map(v => v ?? 0), 0);
  const rightAxisMax = niceCeil(rightDataMax * 1.75);

  const axisYRight = () => ({
    type: "value",
    min: 0,
    max: rightAxisMax,
    axisLine:  { show: false },
    axisTick:  { show: false },
    axisLabel: { color: "#8b9ab0", fontSize: 10, fontFamily: "inherit", formatter: fmtNum },
    splitLine: { show: false },
    nameTextStyle: { color: "#8b9ab0", fontSize: 9 },
  });

  const makeSeriesEntry = (key, axisIndex, seriesType) => {
    const color = getColor(key, axisIndex);
    const labelCfg = {
      show: showLabels,
      position: "top",
      color: "#94a3b8",
      fontSize: 9,
      fontFamily: "inherit",
      fontWeight: "600",
      formatter: p => fmtNum(p.value),
    };

    if (seriesType === "area") {
      return {
        type: "line",
        name: key,
        yAxisIndex: axisIndex,
        smooth: 0.3,
        symbol: "circle",
        symbolSize: 8,
        connectNulls: false,
        lineStyle: { color, width: 2 },
        itemStyle: { color },
        areaStyle: {
          color: {
            type: "linear", x: 0, y: 0, x2: 0, y2: 1,
            colorStops: [
              { offset: 0, color: color + "55" },
              { offset: 1, color: color + "05" },
            ],
          },
        },
        data: sData(key),
        label: labelCfg,
        emphasis: { focus: "series", scale: true },
        z: 2,
      };
    }

    if (seriesType === "line") {
      return {
        type: "line",
        name: key,
        yAxisIndex: axisIndex,
        smooth: false,
        symbol: "circle",
        symbolSize: 8,
        connectNulls: false,
        lineStyle: { color, width: 2.5 },
        itemStyle: { color },
        data: sData(key),
        label: labelCfg,
        emphasis: {
          focus: "series", scale: true,
          itemStyle: { borderWidth: 2, borderColor: "#fff" },
        },
        z: 3,
      };
    }

    // default: bar
    return {
      type: "bar",
      name: key,
      yAxisIndex: axisIndex,
      barCategoryGap: "20%",
      barGap: "5%",
      barMaxWidth: 48,
      data: sData(key).map((val) => ({
        value: val,
        itemStyle: { color, borderRadius: [4, 4, 0, 0] },
      })),
      label: labelCfg,
      emphasis: { focus: "series" },
      z: 2,
    };
  };

  return {
    ...base,
    grid: { left: 12, right: 40, top: 36, bottom: 60, containLabel: true },
    xAxis: axisX(cats),
    yAxis: [axisYLeft(), axisYRight()],

    tooltip: {
      trigger: "axis",
      ...darkTooltip,
      axisPointer: { type: "shadow" },
      formatter(params) {
        const label = params[0]?.axisValueLabel ?? params[0]?.axisValue ?? "";
        let html = `<div style="color:#64748b;font-size:10px;margin-bottom:5px;font-weight:600">${label}</div>`;
        params.forEach(p => {
          html += `<div style="display:flex;align-items:center;gap:6px;margin:2px 0">
            <span style="display:inline-block;width:8px;height:8px;border-radius:50%;background:${p.color}"></span>
            <span style="color:#94a3b8;font-size:10px;flex:1">${p.seriesName}</span>
            <span style="color:#e2e8f0;font-weight:600;padding-left:12px">${fmtNum(p.value)}</span>
          </div>`;
        });
        return html;
      },
    },

    legend: {
      type: "scroll",
      orient: "horizontal",
      bottom: 4,
      itemHeight: 10,
      itemGap: 24,
      textStyle: { color: "#8b9ab0", fontSize: 11, fontFamily: "inherit" },
      data: [
        { name: leftKey,  icon: leftType  === "bar" ? "rect" : "circle", itemStyle: { color: getColor(leftKey,  0) } },
        { name: rightKey, icon: rightType === "bar" ? "rect" : "circle", itemStyle: { color: getColor(rightKey, 1) } },
      ],
      formatter: (name) => {
        if (name === leftKey)  return `${name}  ← Left`;
        if (name === rightKey) return `${name}  Right →`;
        return name;
      },
    },

    series: [
      makeSeriesEntry(leftKey,  0, leftType),
      makeSeriesEntry(rightKey, 1, rightType),
    ],
  };
}


if (type === "line") {
  const sortedKeys = [...keys].sort((a, b) =>
    String(a).localeCompare(String(b), undefined, { numeric: true, sensitivity: "base" })
  );
  const showLabels = data.length <= 60;
  return {
    ...base,

    legend: {
  ...scrollLegend(sortedKeys),
  selector: [
    { type: "all",     title: "All" },
    { type: "inverse", title: "Inv" }
  ],
  selectorPosition: "end",
  selectorLabel: {
    fontSize: 10,
    padding:  [3, 8],
    borderRadius:     4,
    color:            "#8b9ab0",
    borderColor:      "rgba(255,255,255,0.18)",
    backgroundColor:  "rgba(255,255,255,0.04)",
  },
  selectorItemGap: 6,
},


    xAxis: axisX(cats),
    yAxis: axisY(),
    // ← Overrides base's multi-series "axis" tooltip. Hovering a single
    // point now shows only that point's series/value, not every series
    // stacked at that x-position.
    tooltip: singleItemTooltip,
    series: sortedKeys.map((k, i) => ({
      type: "line", name: k, data: sData(k), smooth: false,
      triggerLineEvent: true,
      symbol: "circle",
      symbolSize: showLabels ? 10 : 8,
      connectNulls: false,
      lineStyle: { color: getColor(k, i), width: 2.5 },
      itemStyle: { color: getColor(k, i) },
      label: {
        show: showLabels, position: "top", color: "#94a3b8",
        fontSize: 9, fontFamily: "inherit", fontWeight: "600",
        formatter: p => fmtNum(p.value),
      },
      emphasis: {
        focus: "series", scale: true,
        itemStyle: { borderWidth: 2, borderColor: "#fff" },
      },
    })),
  };
}

  if (type === "area") {
  const sortedKeys = [...keys].sort((a, b) =>
    String(a).localeCompare(String(b), undefined, { numeric: true, sensitivity: "base" })
  );
  return {
    ...base,
    legend: {
  ...scrollLegend(sortedKeys),
  selector: [
    { type: "all",     title: "All" },
    { type: "inverse", title: "Inv" }
  ],
  selectorPosition: "end",
  selectorLabel: {
    fontSize: 10,
    padding:  [3, 8],
    borderRadius:     4,
    color:            "#8b9ab0",
    borderColor:      "rgba(255,255,255,0.18)",
    backgroundColor:  "rgba(255,255,255,0.04)",
  },
  selectorItemGap: 6,
},
    xAxis: axisX(cats),
    yAxis: axisY(),
    series: sortedKeys.map((k, i) => ({
      type: "line",
      name: k,
      data: sData(k),
      smooth: 0.3,
      triggerLineEvent: true,
      symbol: "circle",
      symbolSize: 8,
      connectNulls: false,
      lineStyle: { color: getColor(k, i), width: 2 },
      itemStyle: { color: getColor(k, i) },
      areaStyle: {
        color: {
          type: "linear", x: 0, y: 0, x2: 0, y2: 1,
          colorStops: [
            { offset: 0, color: getColor(k, i) + "55" },
            { offset: 1, color: getColor(k, i) + "05" },
          ],
        },
      },
      emphasis: { focus: "series", scale: true },
    })),
  };
}

  if (type === "treemap") {
    const numKey = keys.find(k => data.some(r => !isNaN(Number(r[k])))) || keys[0];
    return {
      ...base,
      tooltip: { trigger: "item", ...darkTooltip, formatter: p => `<div style="color:#94a3b8;font-size:11px">${p.name}</div><span style="color:${p.color};font-weight:600">${fmtNum(p.value)}</span>` },
      series: [{
            type:       "treemap",
            roam:       false,
            nodeClick:  false,
            visibleMin: 300,
            breadcrumb: { show: false },
            itemStyle:  { gapWidth: 2, borderRadius: 3 },
            label: {
              show:       true,
              color:      "#ffffff",
              fontSize:   17,
              fontFamily: "inherit",
              fontWeight: "bold",
              textShadowColor:   "#000000",
              textShadowBlur:    6,
              textShadowOffsetX: 0,
              textShadowOffsetY: 0,
              formatter: function(p) {
                return p.name + "\n" + fmtNum(p.value);
              },
            },
            data: data.map((r, i) => {
              const name  = String(r[xKey] ?? "");
              const color = COLORS[i % COLORS.length];
              return {
                name,
                value: Number(r[numKey]) || 0,
                itemStyle: {
                  color: selectedValue && name !== selectedValue
                    ? color + "44"
                    : color
                },
              };
            }),
          }],
    };
  }

  if (type === "funnel") {
    const numKey = keys.find(k => data.some(r => !isNaN(Number(r[k])))) || keys[0];
    return {
      ...base,
      series: [{
        type: "funnel", left: "10%", width: "80%",
        label: { show: true, position: "inside", color: "#fff", fontSize: 11 },
        data: data.map((r, i) => ({ name: String(r[xKey] ?? ""), value: Number(r[numKey]) || 0, itemStyle: { color: COLORS[i % COLORS.length] } })),
      }],
    };
  }

  return {
    ...base, xAxis: axisX(cats), yAxis: axisY(),
    series: keys.map((k, i) => ({
      type: "bar", name: k,
      data: sData(k).map((val, ci) => ({
        value: val,
        itemStyle: { color: dimmedColor(COLORS[i % COLORS.length], cats[ci]), borderRadius: [4, 4, 0, 0] },
      })),
    })),
  };
      
}


export default function ChartCard({
  sliceId, title, vizType, xAxis, height: heightProp = 320,
  activeFilters = {}, dateFrom, dateTo,timeFilterId,
  onCrossFilter, crossFilters = {}, onDrillDown,
  metrics:        metricsProp     = [],
  groupby:        groupbyProp     = [],
  groupbyRows:    groupbyRowsProp = [],
  groupbyColumns: groupbyColsProp = [],
  columnOrder:             columnOrderProp            = [],
  showCellBars = false,
  conditionalFormatting:   conditionalFormattingProp  = [],
  zoomable = false,
  fontColor = null,
  conditionalColors  = [],
  crossFilterScope  = null,
  percentageThreshold = 0,
  seriesColors:   seriesColorsProp = {},
  otherThreshold      = 0,
  onDateRangeDetected = null,
  seriesTypes:    seriesTypesProp = null,
}) {
  const [data,         setData]         = useState([]);
  const [keys,         setKeys]         = useState([]);
  const [computedXKey, setComputedXKey] = useState("");
  const [loading,      setLoading]      = useState(true);
  const [error,        setError]        = useState(null);
  const [colnames,     setColnames]     = useState([]);
  const [initialKeys,  setInitialKeys]  = useState([]);
  const cancelRef  = useRef(false);
  const echartsRef = useRef(null);
  const cardRef    = useRef(null);

  const height = useChartHeight(heightProp);

  const isSource      = Object.values(crossFilters).some(f => f.sourceChartId === sliceId);
  const myFilter      = Object.values(crossFilters).find(f => f.sourceChartId === sliceId);
  const selectedValue = myFilter?.value ?? null;
  const isFiltered    = Object.entries(crossFilters).some(([, f]) => f.sourceChartId !== sliceId && f.value);


  useEffect(() => {
    const node = cardRef.current;
    if (!node) return;
    const ro = new ResizeObserver(() => {
      setTimeout(() => echartsRef.current?.getEchartsInstance?.()?.resize(), 60);
    });
    ro.observe(node);
    return () => ro.disconnect();
  }, []);

const chartType = getChartType(vizType);

const activeFiltersString      = JSON.stringify(activeFilters);
const crossFilterPayloadString = JSON.stringify(buildFilterPayload(crossFilters, sliceId, chartType === "table"));

  useEffect(() => {
      console.log("🔄 ChartCard useEffect fired:", { sliceId, dateFrom, dateTo, timeFilterId });
    if (!sliceId) return;
    if ((dateFrom && !dateTo) || (!dateFrom && dateTo)) return;

    cancelRef.current = false;
    setLoading(true); setError(null); setData([]); setKeys([]); setComputedXKey(""); setColnames([]);

    const crossFilterPayload = buildFilterPayload(crossFilters, sliceId, chartType === "table");

    const body = {
      sliceId,
      ...(dateFrom || dateTo ? { dateFrom, dateTo, timeFilterId } : {}),
      activeFilters: Object.entries(activeFilters)
        .filter(([, v]) => Array.isArray(v) ? v.length > 0 : (v != null && v !== ""))
        .map(([col, val]) => ({ col, op: "IN", val: Array.isArray(val) ? val : [val] })),
      crossFilters: crossFilterPayload,
    };

    console.log("🗓 Chart body:", { sliceId, dateFrom, dateTo, timeFilterId });

    api.post("/chart-data", body)
      .then(res => {
        console.log(`Chart ${sliceId} received filters:`, body.crossFilters);
        console.log(`Chart ${sliceId} rows returned:`, res.data.data?.length);
        if (cancelRef.current) return;
       
        if (res.data.success && res.data.data?.length > 0) {
            const rows         = res.data.data;
            const metricLabels = extractMetricLabels(metricsProp);
            const xk           = detectXKey(rows, xAxis, metricLabels, groupbyProp);
            const sk           = detectSeriesKeys(rows, xk, metricLabels);
            const finalKeys    = sk.length
              ? sk
              : Object.keys(rows[0]).filter(k => k !== xk && k !== "__seq__").slice(0, 8);
            setData(rows);

              if (onDateRangeDetected && rows.length > 0) {
                const xk = detectXKey(rows, xAxis, extractMetricLabels(metricsProp), groupbyProp);
                
                const dates = rows
                  .map(r => r[xk])
                  .filter(v => v != null)
                  .map(v => {
                    if (isTimestampMs(Number(v))) return new Date(Number(v));
                    const d = new Date(v);
                    return isNaN(d.getTime()) ? null : d;
                  })
                  .filter(Boolean);

                if (dates.length > 0) {
                  const minDate = new Date(Math.min(...dates.map(d => d.getTime())));
                  const maxDate = new Date(Math.max(...dates.map(d => d.getTime())));

                  const fmt = (d) => d.toISOString().split("T")[0];
                  onDateRangeDetected(fmt(minDate), fmt(maxDate));
                }
              }


            setColnames(res.data.colnames || []);
            setComputedXKey(xk);
            setKeys(finalKeys);
            if (crossFilterPayload.length === 0) {
              setInitialKeys(finalKeys);
            }
          } else {
            setData([]); setKeys([]);
          }
      })
      .catch(() => { if (!cancelRef.current) setError("Failed to load data"); })
      .finally(() => { if (!cancelRef.current) setLoading(false); });

    return () => { cancelRef.current = true; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [
    sliceId,
    dateFrom, dateTo, timeFilterId,
    activeFiltersString,
    crossFilterPayloadString,
  ]);

  const type = getChartType(vizType);
  const xKey = computedXKey || "__seq__";

  const handleChartClick = (params) => {
      console.log("CLICK →", { sliceId, type, name: params.name, col: xKey });

  console.log("ChartClick fired:", {
    chartId:    sliceId,
    type:       type,
    seriesName: params.seriesName,
    name:       params.name,
    groupby:    groupbyProp,
    keys:       keys,
    colnames:   colnames,
  });

  if (!onCrossFilter) return;

  let clickedName = "";
  let filterCol   = xKey;

  if (type === "pie" || type === "treemap" || type === "funnel") {
    clickedName = params.name;
    filterCol   = xKey;

  } else if (type === "line" || type === "area") {
    const seriesName = params.seriesName || "";

    const gb0   = Array.isArray(groupbyProp) ? groupbyProp[0] : null;
    const gbCol = gb0
      ? (typeof gb0 === "string"
          ? gb0
          : gb0?.column_name || gb0?.column?.column_name || "")
      : "";

    if (seriesName && gbCol) {
      console.log(`ChartCard ${sliceId}: using groupby prop col = "${gbCol}"`);
      clickedName = seriesName;
      filterCol   = gbCol;

    } else if (seriesName) {
      const colWithValue = data.length > 0
        ? Object.keys(data[0]).find(col =>
            !keys.includes(col) &&
            col !== xKey &&
            data.some(row => String(row[col]) === seriesName)
          )
        : null;

      if (colWithValue) {
        console.log(`ChartCard ${sliceId}: detected groupby col = "${colWithValue}" for series "${seriesName}" (data scan)`);
        clickedName = seriesName;
        filterCol   = colWithValue;

      } else {
        const dimCol = colnames.find(c =>
          c !== xKey &&
          !keys.includes(c) &&
          !/date|time|key|offset|fulldate/i.test(c)
        );

        if (dimCol) {
          console.log(`ChartCard ${sliceId}: using colnames fallback col = "${dimCol}" for series "${seriesName}"`);
          clickedName = seriesName;
          filterCol   = dimCol;

        } else {
          const metricLabel = extractMetricLabels(metricsProp)[0] || "";
          const hintCol     = metricLabel.match(/\(([^)]+)\)/)?.[1] || "";

          if (hintCol && hintCol !== seriesName) {
            console.log(`ChartCard ${sliceId}: using metric hint col = "${hintCol}" for series "${seriesName}"`);
            clickedName = seriesName;
            filterCol   = hintCol;
          } else {
            console.warn(
              `ChartCard ${sliceId}: cannot determine groupby col for series "${seriesName}". ` +
              `groupbyProp=${JSON.stringify(groupbyProp)}, ` +
              `colnames=${JSON.stringify(colnames)}, ` +
              `keys=${JSON.stringify(keys)}. ` +
              `Fix: ensure backend returns groupby in get_dashboard_charts.`
            );
            clickedName = seriesName;
            filterCol   = seriesName;
          }
        }
      }
    } else {
      clickedName = params.name || params.axisValue || "";
      filterCol   = xKey;
    }

  } else if (type === "heatmap") {
  clickedName = params.data?.[1] !== undefined
    ? String(Object.values(data[0])[1] ?? "")
    : params.name;
  filterCol   = Object.keys(data[0])[1] || xKey;
}
  
  else {
    clickedName = params.name || params.data?.name || params.axisValue || "";
    filterCol   = xKey;
  }

  if (!clickedName) return;

  const activeFilter = Object.values(crossFilters).find(f => f.sourceChartId === sliceId);
  const isSameValue  = activeFilter?.value === clickedName;


  console.log("CROSS FILTER FIRING:", {
  sliceId,
  crossFilterScope,
  filterCol,
  clickedName
})


  onCrossFilter(filterCol, isSameValue ? null : clickedName, sliceId, title, false, crossFilterScope);
};


  const renderBody = () => {
    if (loading) return <Skeleton height={height} />;
    if (error) return (
      <div style={{ display: "flex", alignItems: "center", justifyContent: "center", height, color: "#f87171", fontSize: 12 }}>
        ⚠ {error}
      </div>
    );

    if (!data.length) return (
  <div style={{ display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", height, gap: 18 }}>
    <style>{`
      @keyframes nd-r1{0%,100%{transform:scale(1);opacity:.18}50%{transform:scale(1.18);opacity:.05}}
      @keyframes nd-r2{0%,100%{transform:scale(1);opacity:.12}50%{transform:scale(1.3);opacity:.03}}
      @keyframes nd-fi{from{opacity:0;transform:translateY(7px)}to{opacity:1;transform:translateY(0)}}
    `}</style>

    <div style={{ position:"relative", width:78, height:78, display:"flex", alignItems:"center", justifyContent:"center" }}>
      <div style={{ position:"absolute", width:78, height:78, borderRadius:"50%", border:"1.5px solid #1FA8C9", animation:"nd-r2 2.6s ease-in-out infinite" }} />
      <div style={{ position:"absolute", width:56, height:56, borderRadius:"50%", border:"1.5px solid #1FA8C9", animation:"nd-r1 2.1s ease-in-out infinite 0.25s" }} />
      <div style={{ width:36, height:36, borderRadius:"50%", background:"rgba(31,168,201,0.12)", border:"1.5px solid rgba(31,168,201,0.45)", display:"flex", alignItems:"center", justifyContent:"center" }}>
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#1FA8C9" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <polygon points="22 3 2 3 10 12.46 10 19 14 21 14 12.46 22 3"/>
        </svg>
      </div>
    </div>

    <div style={{ textAlign:"center", animation:"nd-fi 0.5s ease-out 0.15s both" }}>
      <div style={{ fontSize:13, fontWeight:600, color:"#cbd5e1", marginBottom:5 }}>
        No data for current filters
      </div>
      <div style={{ fontSize:11, color:"#475569", lineHeight:1.55 }}>
        Try adjusting or clearing your filters
      </div>
    </div>
  </div>
);


if (type === "bignum") {
  const metricLabels = extractMetricLabels(metricsProp);
  const allCols = Object.keys(data[0]);

  const numericCols = allCols.filter(k =>
    !isNaN(Number(data[0][k])) &&
    !isTimestampMs(Number(data[0][k]))
  );

  const valueKey =
    metricLabels.find(m => allCols.includes(m)) ||
    numericCols[0] ||
    allCols[0] ||
    "";

  const rawVal = data[0]?.[valueKey] ?? 0;
  const n = Number(rawVal);

  // Check metric name + chart title
  const percentageLabel =
    `${String(valueKey || "")} ${String(title || "")}`;

  const isPct = isPercentageMetric(percentageLabel);

  // Format only the displayed value
  const displayVal = isPct
    ? fmtPercentage(n)
    : fmtBigNum(rawVal, valueKey);

  const subtitle = cleanMetricLabel(String(valueKey || ""));
  const isDate = isTimestampMs(n);

  const valueFontSize = isDate
    ? 22
    : Math.max(
        18,
        36 - Math.max(0, displayVal.length - 3) * 4
      );

  // KEEP YOUR EXISTING RETURN JSX BELOW THIS LINE
return (
  <div style={{
    display:        "flex",
    flexDirection:  "column",
    alignItems:     "center",
    justifyContent: "center",
    height:         "100%",
    gap:            4,
    padding:        "8px 10px",
    boxSizing:      "border-box",
    overflow:       "hidden",
  }}>
    <div style={{
      width:     "100%",
      maxWidth:  180,
      textAlign: "center",
    }}>

      <div style={{
        fontSize:      valueFontSize,
        fontWeight:    800,
        color: (() => {
          if (conditionalColors.length > 0) {
            for (const rule of conditionalColors) {
              const target = Number(rule.targetValue ?? 0);

              if (rule.operator === ">"  && n >  target)
                return rule.color;

              if (rule.operator === ">=" && n >= target)
                return rule.color;

              if (rule.operator === "<"  && n <  target)
                return rule.color;

              if (rule.operator === "<=" && n <= target)
                return rule.color;

              if (rule.operator === "==" && n === target)
                return rule.color;
            }
          }

          return fontColor || "#1FA8C9";
        })(),
        letterSpacing: isDate ? 0 : -0.5,
        lineHeight:    1.1,
        textAlign:     "center",
        whiteSpace:    "nowrap",
        width:         "100%",
      }}>
        {displayVal}
      </div>

    </div>
  </div>
);
}


    if (type === "table") {
      const metricLabels = extractMetricLabels(metricsProp);
      return (
        <PivotTable
          key={`${sliceId}-${data.length}`}
          data={data}
          height={height}
          groupbyRows={groupbyRowsProp}
          groupbyColumns={groupbyColsProp}
          metricKeys={metricLabels}
          colnames={colnames}
          crossFilterValue={selectedValue}
          title={title}
          columnOrder={columnOrderProp}
          showCellBars={showCellBars}
          conditionalFormatting={conditionalFormattingProp}
          onRowClick={(col, val) =>  {
            if (!onCrossFilter) return;
            onCrossFilter(col, val, sliceId, title, true, crossFilterScope);
          }
            
          }
        />
      );
    }

    

return (
  // <ReactECharts
  //   ref={echartsRef}
  //   option={buildOption({ type, data, keys, xKey, selectedValue, initialKeys, zoomable, percentageThreshold, otherThreshold, seriesColors: seriesColorsProp})}
  //   style={{ height, width: "100%", cursor: onCrossFilter ? "pointer" : "default" }}
  //   opts={{ renderer: "canvas" }}
  //   onEvents={{ click: handleChartClick }}
  //   notMerge
  //   lazyUpdate={false}
  // />

  <ReactECharts
    ref={echartsRef}
    option={buildOption({
      type, data, keys, xKey, selectedValue, initialKeys, zoomable,
      percentageThreshold, otherThreshold,
      seriesColors: seriesColorsProp,
      seriesTypesProp,   // ← added
    })}
    style={{ height, width: "100%", cursor: onCrossFilter ? "pointer" : "default" }}
    opts={{ renderer: "canvas" }}
    onEvents={{ click: handleChartClick }}
    notMerge
    lazyUpdate={false}
  />
);


  };

  const cardBorder = isSource
    ? "1px solid rgba(31,168,201,0.6)"
    : isFiltered ? "1px solid rgba(255,255,255,0.04)" : "1px solid rgba(255,255,255,0.065)";

  return (
    <div ref={cardRef} style={{
      background: "#1e2129",
      border: cardBorder,
      borderRadius: 10,
      padding: "14px 16px 10px",
      position: "relative",
      overflow: getChartType(vizType) === "table" ? "auto" : "hidden",
      minWidth: 0,
      minHeight: 0,
      width: "100%",
      boxSizing: "border-box",
      height: "100%",
      display: "flex",
      flexDirection: "column",
      boxShadow: isSource
        ? "0 0 0 1px rgba(31,168,201,0.3), 0 4px 24px rgba(0,0,0,0.35)"
        : "0 4px 24px rgba(0,0,0,0.35)",
      opacity: isFiltered && !isSource ? 0.85 : 1,
      transition: "opacity .2s, border .2s, box-shadow .2s",
    }}>

      <div style={{ position: "absolute", top: 0, left: 0, right: 0, height: 3, background: `linear-gradient(90deg,${COLORS[0]},${COLORS[1]},${COLORS[6]})`, opacity: 0.75 }} />

      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 10, paddingTop: 2 }}>
        <h3 style={{ fontSize: 13, fontWeight: 600, color: "#cbd5e1", flex: 1, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", margin: 0 }}>
          {title}
        </h3>
        <div style={{ display: "flex", alignItems: "center", gap: 5, flexShrink: 0, marginLeft: 8 }}>
          {isSource && (
            <span
              onClick={() => onCrossFilter && onCrossFilter(xKey, null, sliceId, title, true, crossFilterScope)}
              title="Click to clear cross-filter"
              style={{ fontSize: 9, background: "rgba(31,168,201,0.2)", color: "#1FA8C9", border: "1px solid rgba(31,168,201,0.5)", padding: "2px 7px", borderRadius: 6, cursor: "pointer", letterSpacing: "0.06em", fontWeight: 700, textTransform: "uppercase", display: "flex", alignItems: "center", gap: 4 }}>
              ✕ {selectedValue}
            </span>
          )}
          {isFiltered && !isSource && (
            <span style={{ fontSize: 9, background: "rgba(251,191,36,0.15)", color: "#fbbf24", border: "1px solid rgba(251,191,36,0.3)", padding: "2px 7px", borderRadius: 6, letterSpacing: "0.06em", fontWeight: 700, textTransform: "uppercase" }}>
              Filtered
            </span>
          )}
        </div>
      </div>

      <div style={{
        flex: 1,
        minWidth: 0,
        minHeight: 0,
        overflow: getChartType(vizType) === "table" ? "auto" : "hidden",
      }}>
        {renderBody()}
      </div>
    </div>
  );
}
