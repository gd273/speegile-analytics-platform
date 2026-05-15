import { useState, useEffect } from "react";

/**
 * DashboardGrid
 *
 * Wraps chart cards in a CSS grid that:
 *   - Desktop  (≥1024px)        → uses the column count from Superset layout
 *   - Tablet   (600–1023px)     → max 2 columns
 *   - Mobile portrait (<600px)  → 1 column
 *   - Mobile landscape (<768px h<500px) → 1 column, tighter gap
 *
 * Props
 *   children   – <ChartCard> nodes
 *   columns    – desired column count from Superset layout (default 2)
 *   gap        – grid gap in px (default 14)
 */
export default function DashboardGrid({ children, columns = 2, gap = 14 }) {
  const [cols, setCols] = useState(columns);
  const [gapPx, setGapPx] = useState(gap);

  useEffect(() => {
    const update = () => {
      const w = window.innerWidth;
      const h = window.innerHeight;
      const isSmallLandscape = w < 900 && h < 500;   // phone on its side

      if (isSmallLandscape) {
        setCols(1);
        setGapPx(8);
      } else if (w < 600) {
        setCols(1);
        setGapPx(10);
      } else if (w < 1024) {
        setCols(Math.min(columns, 2));
        setGapPx(12);
      } else {
        setCols(columns);
        setGapPx(gap);
      }
    };

    update();
    window.addEventListener("resize", update);
    window.addEventListener("orientationchange", update);
    return () => {
      window.removeEventListener("resize", update);
      window.removeEventListener("orientationchange", update);
    };
  }, [columns, gap]);

  return (
    <div
      style={{
        display: "grid",
        gridTemplateColumns: `repeat(${cols}, minmax(0, 1fr))`,
        /*                                      ↑
         * minmax(0, 1fr) is the key difference from minmax(auto, 1fr).
         * "auto" lets the cell grow to its content's intrinsic width,
         * which breaks the grid when a chart has a wide canvas or table.
         * "0" forces the cell to honour the fr allocation strictly.
         */
        gap: `${gapPx}px`,
        width: "100%",
        boxSizing: "border-box",
      }}
    >
      {children}
    </div>
  );
}