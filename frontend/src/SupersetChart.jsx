
import React, { useEffect, useState, useRef } from "react";
import axios from "axios";
import { embedDashboard } from "@superset-ui/embedded-sdk";
import { jwtDecode } from "jwt-decode"; // ✅ correct import

const SupersetChart = ({ dashboardId, chartTitle }) => {
  const containerRef = useRef(null);
  const [status, setStatus] = useState("initial");
  const [errorMessage, setErrorMessage] = useState("");

  const BACKEND_URL = "http://localhost:5000/api/guest-token";
  const SUPERSET_DOMAIN = "http://localhost:8088";

  console.log("SupersetChart Component Rendered. Dashboard ID:", dashboardId);

  // 🔹 Validate JWT expiration + log details
  const validateToken = (token) => {
    try {
      const decoded = jwtDecode(token);
      const now = Date.now() / 1000;

      console.log("🔎 [TOKEN DECODED]");
      console.log(" - Expiration (exp):", decoded.exp);
      console.log(" - Expiration (human):", new Date(decoded.exp * 1000));
      console.log(" - Resources:", decoded.resources || "N/A");
      // console.log(" - Roles:", decoded.user?.roles || "N/A");
      console.log(" - Full decoded token:", decoded);

      if (decoded.exp && decoded.exp < now) {
        console.error("[TOKEN ERROR] Guest token expired at:", decoded.exp);
        return false;
      }
      console.log("[TOKEN OK] Guest token is valid until:", decoded.exp);
      return true;
    } catch (err) {
      console.error("[TOKEN ERROR] Invalid token:", err.message);
      return false;
    }
  };

  useEffect(() => {
    console.log("\n--- useEffect Hook Fired ---");
    console.log("Current dashboardId state:", dashboardId);

    if (!dashboardId) {
      console.log("No dashboardId provided. Exiting useEffect.");
      return;
    }

    console.log("Target Superset Domain:", SUPERSET_DOMAIN);
    console.log("Target Backend URL:", BACKEND_URL);

    const loadDashboard = async () => {
      try {
        console.log(`[PROCESS] Starting loadDashboard for ID: ${dashboardId}`);
        setStatus("loading");
        setErrorMessage("");

        // Clear old content
        if (containerRef.current) {
          containerRef.current.innerHTML = "";
        }

        console.log(`[API CALL] Requesting guest token from: ${BACKEND_URL}`);
        const apiStartTime = Date.now();
        const response = await axios.get(BACKEND_URL, {
          params: { dashboardId },
          timeout: 10000,
          withCredentials: true, // ADD THIS LINE
        });
        const apiEndTime = Date.now();

        console.log(`[API RESPONSE] Received in ${apiEndTime - apiStartTime}ms`);
        console.log("API Response Status:", response.status);
        console.log("API Response Data:", response.data);

        const { guestToken } = response.data;

        if (!guestToken || !validateToken(guestToken)) {
          throw new Error("Invalid or expired guestToken returned by backend");
        }

        console.log(
          `[TOKEN INFO] Guest token snippet: ${guestToken.substring(0, 30)}...`
        );
        // 🔹 Embed Superset dashboard
        const embedStartTime = Date.now();
        await embedDashboard({
          id: dashboardId.toString(),
          supersetDomain: SUPERSET_DOMAIN,
          mountPoint: containerRef.current,
          fetchGuestToken: async () => {
            console.log("[SDK CALL] fetchGuestToken executed.");
            return guestToken;
          },
          dashboardUiConfig: {
            hideTitle: true,
            hideTab: true,
            hideChartControls: true,
            filters: {
              expanded: true,
              visible: true,
            },
          },
          debug: true,
        });
        const embedEndTime = Date.now();

        // console.log(
        //   `[SUCCESS] Dashboard embedded in ${embedEndTime - embedStartTime}ms.`
        // );
        setStatus("success");
      } catch (err) {
        console.error("[ERROR BLOCK] Embedding failed:", err);
        let message = "Unknown error occurred";
        if (err.response) {
  // Check if it's an authentication error
          if (err.response.status === 401) {
            message = "Authentication required. Please log in again.";
            // Optionally, trigger a re-login by reloading the page
            setTimeout(() => window.location.reload(), 2000);
          } else {
            message = `Backend error: ${err.response.status} - ${
              err.response.data?.error || err.response.statusText
            }`;
          }
        }

        setErrorMessage(message);
        setStatus("error");
        console.log(`[STATUS CHANGE] Error message: ${message}`);
      }
    };

    loadDashboard();

    // 🔹 Cleanup (copy ref to avoid warning)
    const container = containerRef.current;
    return () => {
      if (container) {
        container.innerHTML = "";
      }
    };
  }, [dashboardId]);

  useEffect(() => {
  if (containerRef.current) {
    const parent = containerRef.current.parentElement;
    const size = parent?.getBoundingClientRect();
    if (size) {
      console.log("📐 Parent size:", size.width, "x", size.height);
    }
  }
}, []);

  return (
  <div className="bg-white p-4 rounded-xl shadow-lg mb-8 border border-gray-200">
    {/* ... (title and status) */}

    <div
      ref={containerRef}
      style={{
        width: "100%",
        overflow: "auto", // Allow this section to scroll if needed
        position: "relative",
        borderRadius: "8px",
      }}
    />
  </div>
);
};

export default SupersetChart;

