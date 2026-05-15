import { useState, useEffect } from "react";

const SMALL_SCREEN_WIDTH = 768;

export default function OrientationWarning() {
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    const check = () => {
      const isSmall    = window.innerWidth < SMALL_SCREEN_WIDTH;
      const isPortrait = window.innerHeight > window.innerWidth;
      setVisible(isSmall && isPortrait);
    };

    check();
    window.addEventListener("resize", check);
    window.addEventListener("orientationchange", check);
    return () => {
      window.removeEventListener("resize", check);
      window.removeEventListener("orientationchange", check);
    };
  }, []);

  if (!visible) return null;

  return (
    <div style={styles.overlay}>
      <div style={styles.card}>
        <div style={styles.iconWrap}>
          <PhoneRotateIcon />
        </div>
        <p style={styles.heading}>Rotate your device</p>
        <p style={styles.sub}>
          This dashboard is best viewed in landscape mode. Please rotate your phone horizontally for the full experience.
        </p>
      </div>
    </div>
  );
}

// ── Inline phone-rotate SVG ───────────────────────────────────
function PhoneRotateIcon() {
  return (
    <svg width="56" height="56" viewBox="0 0 56 56" fill="none" xmlns="http://www.w3.org/2000/svg">
      {/* Phone in portrait */}
      <rect x="10" y="8" width="16" height="26" rx="3" stroke="#1FA8C9" strokeWidth="2" fill="none" />
      <circle cx="18" cy="30" r="1.5" fill="#1FA8C9" />

      {/* Arrow curving from portrait to landscape */}
      <path
        d="M28 18 C34 12, 44 14, 46 20"
        stroke="#1FA8C9" strokeWidth="2" strokeLinecap="round" fill="none"
        strokeDasharray="3 2"
      />
      <polygon points="46,16 46,24 50,20" fill="#1FA8C9" />

      {/* Phone in landscape */}
      <rect x="32" y="26" width="18" height="11" rx="3"
        stroke="#1FA8C9" strokeWidth="2" fill="none"
        transform="rotate(0 32 26)" />
      <circle cx="34.5" cy="31.5" r="1.5" fill="#1FA8C9" />

      {/* Animated rotation ring */}
      <circle cx="28" cy="28" r="25" stroke="rgba(31,168,201,0.15)" strokeWidth="1.5" fill="none" />
    </svg>
  );
}

// ── Styles ────────────────────────────────────────────────────
const styles = {
  overlay: {
    position:       "fixed",
    inset:          0,
    zIndex:         9999,
    display:        "flex",
    alignItems:     "center",
    justifyContent: "center",
    background:     "rgba(10, 12, 18, 0.82)",
    backdropFilter: "blur(6px)",
    WebkitBackdropFilter: "blur(6px)",
    padding:        "24px",
    animation:      "owFadeIn 0.25s ease",
  },
  card: {
    background:   "#1e2129",
    border:       "1px solid rgba(31,168,201,0.35)",
    borderRadius: "16px",
    padding:      "32px 28px 28px",
    maxWidth:     "320px",
    width:        "100%",
    textAlign:    "center",
    boxShadow:    "0 24px 64px rgba(0,0,0,0.6), 0 0 0 1px rgba(31,168,201,0.1)",
    animation:    "owSlideUp 0.3s cubic-bezier(0.34,1.56,0.64,1)",
  },
  iconWrap: {
    display:        "flex",
    alignItems:     "center",
    justifyContent: "center",
    width:          "80px",
    height:         "80px",
    borderRadius:   "50%",
    background:     "rgba(31,168,201,0.08)",
    border:         "1px solid rgba(31,168,201,0.2)",
    margin:         "0 auto 20px",
    animation:      "owPulse 2.2s ease-in-out infinite",
  },
  heading: {
    fontSize:     "17px",
    fontWeight:   "600",
    color:        "#e2e8f0",
    margin:       "0 0 10px",
    letterSpacing: "-0.2px",
  },
  sub: {
    fontSize:   "13px",
    color:      "#64748b",
    lineHeight: "1.6",
    margin:     0,
  },
};

// ── Keyframe injection ────────────────────────────────────────
if (typeof document !== "undefined") {
  const id = "__ow_keyframes__";
  if (!document.getElementById(id)) {
    const style = document.createElement("style");
    style.id = id;
    style.textContent = `
      @keyframes owFadeIn   { from { opacity: 0 }               to { opacity: 1 } }
      @keyframes owSlideUp  { from { transform: translateY(24px) scale(0.95); opacity: 0 }
                              to   { transform: translateY(0)    scale(1);    opacity: 1 } }
      @keyframes owPulse    { 0%,100% { box-shadow: 0 0 0 0   rgba(31,168,201,0.25) }
                              50%     { box-shadow: 0 0 0 10px rgba(31,168,201,0)    } }
    `;
    document.head.appendChild(style);
  }
}