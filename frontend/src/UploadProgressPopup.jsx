// UploadProgressPopup.jsx
// Persistent popup — lives in App root, survives page navigation.
// Shows upload progress, live timer, and total time taken when done.

import { useState, useEffect, useRef } from "react";
import api from "./api";

const UploadProgressPopup = () => {

  const [popupStatus, setPopupStatus] = useState(null);
  const intervalRef                   = useRef(null); // polling interval
  const timerRef                      = useRef(null); // countdown timer interval
  const startTimeRef                  = useRef(null); // when upload started
  const [elapsedSeconds, setElapsed]  = useState(0);  // live timer value
  const [totalTime, setTotalTime]     = useState(null); // final time when done


  // ─────────────────────────────────────────────────────
  //  FORMAT SECONDS → "1m 23s" or "45s"
  // ─────────────────────────────────────────────────────
  const formatTime = (seconds) => {
    if (seconds < 60) return `${seconds}s`;
    const m = Math.floor(seconds / 60);
    const s = seconds % 60;
    return s === 0 ? `${m}m` : `${m}m ${s}s`;
  };


  // ─────────────────────────────────────────────────────
  //  START TIMER — counts up every second
  // ─────────────────────────────────────────────────────
  const startTimer = () => {
    startTimeRef.current = Date.now();
    setElapsed(0);
    setTotalTime(null);

    if (timerRef.current) clearInterval(timerRef.current);

    timerRef.current = setInterval(() => {
      const elapsed = Math.floor((Date.now() - startTimeRef.current) / 1000);
      setElapsed(elapsed);
    }, 1000);
  };


  // ─────────────────────────────────────────────────────
  //  STOP TIMER — saves total time
  // ─────────────────────────────────────────────────────
  const stopTimer = () => {
    if (timerRef.current) {
      clearInterval(timerRef.current);
      timerRef.current = null;
    }
    if (startTimeRef.current) {
      const total = Math.floor((Date.now() - startTimeRef.current) / 1000);
      setTotalTime(total);
    }
  };


  // ─────────────────────────────────────────────────────
  //  ON MOUNT — resume polling if upload was in progress
  //  (handles page refresh during upload)
  // ─────────────────────────────────────────────────────
  useEffect(() => {
    const savedLoadId   = localStorage.getItem("active_load_id");
    const savedStart    = localStorage.getItem("upload_start_time");

    if (savedLoadId) {
      // Restore elapsed time from saved start
      if (savedStart) {
        startTimeRef.current = parseInt(savedStart);
        const elapsed = Math.floor((Date.now() - startTimeRef.current) / 1000);
        setElapsed(elapsed);

        // Resume live timer
        timerRef.current = setInterval(() => {
          const e = Math.floor((Date.now() - startTimeRef.current) / 1000);
          setElapsed(e);
        }, 1000);
      }

      startPolling(parseInt(savedLoadId));
    }

    return () => {
      if (intervalRef.current) clearInterval(intervalRef.current);
      if (timerRef.current)    clearInterval(timerRef.current);
    };
  }, []);


  // ─────────────────────────────────────────────────────
  //  LISTEN FOR NEW UPLOAD from UploadExcel component
  // ─────────────────────────────────────────────────────
  useEffect(() => {
    const handleNewUpload = (e) => {
      const { loadId } = e.detail;

      // Save to localStorage so popup survives page navigation
      localStorage.setItem("active_load_id",    loadId);
      localStorage.setItem("upload_start_time", Date.now().toString());

      setPopupStatus({
        status:  "Queued",
        percent: 5,
        message: "File received, starting processing...",
        load_id: loadId,
      });

      startTimer();
      startPolling(loadId);
    };

    window.addEventListener("upload_started", handleNewUpload);
    return () => window.removeEventListener("upload_started", handleNewUpload);
  }, []);


  // ─────────────────────────────────────────────────────
  //  POLLING — /api/upload-status/<loadId> every 3s
  // ─────────────────────────────────────────────────────
  const startPolling = (loadId) => {
    if (intervalRef.current) clearInterval(intervalRef.current);

    intervalRef.current = setInterval(async () => {
      try {
        const res = await api.get(`/upload-status/${loadId}`);
        setPopupStatus(res.data);

        if (res.data.status === "Pass" || res.data.status === "Fail") {
          // Stop polling and timer when done
          clearInterval(intervalRef.current);
          intervalRef.current = null;
          localStorage.removeItem("active_load_id");
          localStorage.removeItem("upload_start_time");
          stopTimer();

          // Notify UploadExcel to update its inline message
          window.dispatchEvent(new CustomEvent("upload_complete", {
            detail: {
              status:  res.data.status,
              message: res.data.message,
            }
          }));
        }

      } catch (err) {
        console.error("Polling error:", err);
      }
    }, 3000);
  };


  // ─────────────────────────────────────────────────────
  //  CLOSE POPUP manually
  // ─────────────────────────────────────────────────────
  const handleClose = () => {
    if (intervalRef.current) clearInterval(intervalRef.current);
    if (timerRef.current)    clearInterval(timerRef.current);
    localStorage.removeItem("active_load_id");
    localStorage.removeItem("upload_start_time");
    setPopupStatus(null);
    setElapsed(0);
    setTotalTime(null);
  };


  // ─────────────────────────────────────────────────────
  //  DON'T RENDER if no active upload
  // ─────────────────────────────────────────────────────
  if (!popupStatus) return null;

  const isDone   = popupStatus.status === "Pass";
  const isFailed = popupStatus.status === "Fail";
  const isActive = !isDone && !isFailed;


  // ─────────────────────────────────────────────────────
  //  RENDER
  // ─────────────────────────────────────────────────────
  return (
    <div style={{
      position:      "fixed",
      bottom:        24,
      right:         24,
      width:         300,
      maxHeight:     420,
      display:       "flex",
      flexDirection: "column",
      background:    "#1a1d26",
      border:        `1px solid ${
        isDone   ? "rgba(34,197,94,0.4)"   :
        isFailed ? "rgba(248,113,113,0.4)" :
                   "rgba(31,168,201,0.3)"
      }`,
      borderRadius:  12,
      padding:       "16px 20px",
      zIndex:        9999,
      boxShadow:     "0 8px 32px rgba(0,0,0,0.5)",
    }}>

      {/* ── Scrollbar style for error message ── */}
      <style>{`
        .error-scroll::-webkit-scrollbar { width: 4px; }
        .error-scroll::-webkit-scrollbar-track {
          background: rgba(255,255,255,0.04); border-radius: 99px;
        }
        .error-scroll::-webkit-scrollbar-thumb {
          background: rgba(248,113,113,0.4); border-radius: 99px;
        }
      `}</style>

      {/* ── Header: title + close button ── */}
      <div style={{
        display:        "flex",
        justifyContent: "space-between",
        alignItems:     "center",
        marginBottom:   10,
      }}>
        <span style={{
          fontSize:   12,
          fontWeight: 700,
          color:      isDone   ? "#22c55e" :
                      isFailed ? "#f87171" :
                                 "#1FA8C9",
        }}>
          {isDone   ? "✅ Upload Complete"  :
           isFailed ? "❌ Upload Failed"    :
                      "⚙️  Processing Upload"}
        </span>

        {/* X button — always visible */}
        <button
          onClick={handleClose}
          style={{
            background: "none",
            border:     "none",
            color:      "#64748b",
            cursor:     "pointer",
            fontSize:   16,
            lineHeight: 1,
            padding:    "0 0 0 8px",
          }}
        >
          ✕
        </button>
      </div>

      {/* ── Status message ── */}
      <p style={{
        color:        "#e2e8f0",
        fontSize:     13,
        marginBottom: 10,
        lineHeight:   1.5,
      }}>
        {isDone
          ? "Data uploaded! Your dashboards are ready."
          : popupStatus.message}
      </p>

      {/* ── Progress bar — hidden on Fail ── */}
      {!isFailed && (
        <div style={{
          background:   "rgba(255,255,255,0.06)",
          borderRadius: 99,
          height:       6,
          overflow:     "hidden",
          marginBottom: 6,
        }}>
          <div style={{
            width:        `${popupStatus.percent}%`,
            height:       "100%",
            borderRadius: 99,
            background:   isDone
              ? "#22c55e"
              : "linear-gradient(90deg,#1FA8C9,#A868B7)",
            transition:   "width 0.6s ease",
          }} />
        </div>
      )}

      {/* ── Percent + Timer row ── */}
      {!isFailed && (
        <div style={{
          display:        "flex",
          justifyContent: "space-between",
          alignItems:     "center",
          fontSize:       10,
          color:          "#475569",
          marginBottom:   10,
        }}>
          {/* Left: percent */}
          <span style={{
            color:      isDone ? "#22c55e" : "#1FA8C9",
            fontWeight: 700,
          }}>
            {popupStatus.percent}%
          </span>

          {/* Right: live timer OR total time when done */}
          <span style={{ color: "#64748b" }}>
            {isDone && totalTime !== null
              ? `Completed in ${formatTime(totalTime)}`  // ← total time when done
              : isActive
              ? `⏱ ${formatTime(elapsedSeconds)}`         // ← live countdown while running
              : null
            }
          </span>
        </div>
      )}

      {/* ── Error: scrollable message area ── */}
      {isFailed && (
        <>
          <div
            className="error-scroll"
            style={{
              maxHeight:    120,
              overflowY:    "auto",
              paddingRight: 4,
              marginBottom: 8,
            }}
          >
            <p style={{
              color:      "#f87171",
              fontSize:   12,
              lineHeight: 1.6,
              margin:     0,
              wordBreak:  "break-word",
            }}>
              {popupStatus.message || "Processing failed. Please contact support."}
            </p>
          </div>

          {/* Timer for failed uploads */}
          {totalTime !== null && (
            <p style={{
              color:        "#475569",
              fontSize:     10,
              marginBottom: 8,
            }}>
              Failed after {formatTime(totalTime)} · Load ID: {popupStatus.load_id}
            </p>
          )}
        </>
      )}

      {/* Load ID (shown for pass) */}
      {isDone && (
        <p style={{
          color:        "#374151",
          fontSize:     10,
          marginBottom: 10,
        }}>
          Load ID: {popupStatus.load_id}
        </p>
      )}

      {/* ── Pass: refresh button ── */}
      {isDone && (
        <button
          onClick={() => window.location.reload()}
          style={{
            width:        "100%",
            padding:      "8px",
            borderRadius: 8,
            background:   "rgba(34,197,94,0.15)",
            border:       "1px solid rgba(34,197,94,0.4)",
            color:        "#22c55e",
            fontSize:     12,
            fontWeight:   600,
            cursor:       "pointer",
          }}
        >
          Refresh Dashboard
        </button>
      )}

    </div>
  );
};

export default UploadProgressPopup;