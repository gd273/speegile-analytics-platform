import React, { useState, useEffect } from "react";
import api from "./api";
import Highcharts from "highcharts";
import HighchartsReact from "highcharts-react-official";
// import HighchartsTreemap from "highcharts/modules/treemap";

// HighchartsTreemap(Highcharts);

const HighchartsTreemap = require("highcharts/modules/treemap");
if (typeof HighchartsTreemap === "function") {
  HighchartsTreemap(Highcharts);
} else if (HighchartsTreemap.default) {
  HighchartsTreemap.default(Highcharts);
}

export default function TreemapFilter({
  sliceId,        // chart ID from Superset
  title,          // "Category" or "Brand"
  nameKey,        // column name e.g. "CategoryName"
  valueKey,       // metric column e.g. "SUM(qty)"
  activeValue,    // currently selected value
  onSelect,       // callback(column, value)
}) {
  const [data,    setData]    = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!sliceId) return;

    const load = async () => {
      setLoading(true);
      try {
        const res = await api.get("/chart-data", {
          params: { sliceId }
        });
        if (res.data.success && res.data.data?.length > 0) {
          setData(res.data.data);
        }
      } catch (e) {
        console.error("Treemap load failed", e);
      } finally {
        setLoading(false);
      }
    };

    load();
  }, [sliceId]);

  // ── Build Highcharts treemap options ────────────────────
  const buildOptions = () => {
    const seriesData = data.map((row, i) => {
      const name  = String(row[nameKey]  || "Unknown");
      const value = Number(row[valueKey] || 0);

      return {
        id:    `item-${i}`,
        name,
        value,
        // ✅ Highlight selected item
        color: activeValue === name
          ? "#f59e0b"           // orange = selected
          : undefined,          // use default colors
      };
    });

    return {
      chart: {
        backgroundColor: "transparent",
        height:          180,
        margin:          [0, 0, 0, 0],
        spacing:         [0, 0, 0, 0],
        animation:       { duration: 400 }
      },
      title:   { text: null },
      credits: { enabled: false },
      legend:  { enabled: false },
      tooltip: {
        backgroundColor: "#0f172a",
        borderColor:     "#334155",
        borderRadius:    8,
        style:           { color:"#94a3b8", fontSize:"11px" },
        formatter: function() {
          return `<span style="color:#64748b">${this.key}</span><br/>
                  <b style="color:#94a3b8">
                    ${new Intl.NumberFormat("en-IN").format(Math.round(this.point.value))}
                  </b>`;
        }
      },
      series: [{
        type:             "treemap",
        layoutAlgorithm:  "squarified",
        animationLimit:   1000,
        dataLabels: {
          enabled: true,
          style: {
            fontSize:    "11px",
            fontWeight:  "500",
            color:       "#ffffff",
            textOutline: "none"
          }
        },
        levels: [{
          level:          1,
          borderWidth:    2,
          borderColor:    "#0f1117",
          colorByPoint:   true,
        }],
        point: {
          events: {
            // ✅ Click = select/deselect filter
            click: function() {
              const clickedName = this.name;
              if (activeValue === clickedName) {
                onSelect(nameKey, null);       // deselect
              } else {
                onSelect(nameKey, clickedName); // select
              }
            }
          }
        },
        cursor: "pointer",
        data:   seriesData
      }]
    };
  };

  return (
    <div style={{
      background:   "#1a1f2e",
      border:       `1px solid ${activeValue ? "#f59e0b" : "#1e293b"}`,
      borderRadius: 12,
      padding:      14,
      position:     "relative",
      overflow:     "hidden",
      transition:   "border-color .2s"
    }}>
      {/* Accent line */}
      <div style={{
        position:   "absolute",
        top:0, left:0, right:0,
        height:     2,
        background: activeValue
          ? "linear-gradient(90deg,#f59e0b,#fbbf24)"
          : "linear-gradient(90deg,#3b82f6,#8b5cf6,#06b6d4)",
        opacity: .8
      }}/>

      {/* Header */}
      <div style={{ display:"flex", alignItems:"center",
                    justifyContent:"space-between", marginBottom:10 }}>
        <h3 style={{ fontSize:12, fontWeight:500, color:"#94a3b8" }}>
          {title}
        </h3>

        {/* Show selected value + clear button */}
        {activeValue && (
          <span style={{
            fontSize:11, background:"rgba(245,158,11,.15)",
            color:"#fbbf24", border:"1px solid rgba(245,158,11,.3)",
            padding:"2px 8px", borderRadius:10,
            display:"flex", alignItems:"center", gap:6
          }}>
            {activeValue}
            <button
              onClick={() => onSelect(nameKey, null)}
              style={{ background:"none", border:"none",
                       color:"#fbbf24", cursor:"pointer",
                       fontWeight:"bold", fontSize:13 }}
            >×</button>
          </span>
        )}
      </div>

      {/* Chart */}
      {loading ? (
        <div style={{ height:180, display:"flex", alignItems:"center",
                      justifyContent:"center", color:"#334155", fontSize:12 }}>
          Loading...
        </div>
      ) : data.length === 0 ? (
        <div style={{ height:180, display:"flex", alignItems:"center",
                      justifyContent:"center", color:"#334155", fontSize:12 }}>
          No data
        </div>
      ) : (
        <HighchartsReact
          highcharts={Highcharts}
          options={buildOptions()}
        />
      )}
    </div>
  );
}