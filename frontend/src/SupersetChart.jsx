
import React, { useEffect, useState, useRef } from "react";
import { embedDashboard } from "@superset-ui/embedded-sdk";
import { jwtDecode } from "jwt-decode";
import api from "./api";

const SupersetChart = ({ dashboardId, chartTitle }) => {
  const containerRef = useRef(null);
  const [status, setStatus] = useState("initial");
  const [errorMessage, setErrorMessage] = useState("");

  const SUPERSET_DOMAIN = process.env.REACT_APP_SUPERSET_BASE_URL;


  // 🔹 Validate JWT expiration + log details
  const validateToken = (token) => {
    try {
      const decoded = jwtDecode(token);
      const now = Date.now() / 1000;
      if (decoded.exp && decoded.exp < now) {
        return false;
      }
      return true;
    } catch (err) {
      return false;
    }
  };

  useEffect(() => {

    if (!dashboardId) {
      return;
    }

    const loadDashboard = async () => {
      try {
        setStatus("loading");
        setErrorMessage("");

        // Clear old content
        if (containerRef.current) {
          containerRef.current.innerHTML = "";
        }

        const response = await api.get("/guest-token", {
          params: { dashboardId },
          timeout: 10000,
        });


        const { guestToken } = response.data;

        if (!guestToken || !validateToken(guestToken)) {
          throw new Error("Invalid or expired guestToken returned by backend");
        }

        await embedDashboard({
          id: dashboardId.toString(),
          supersetDomain: SUPERSET_DOMAIN,
          mountPoint: containerRef.current,
          fetchGuestToken: async () => guestToken,
          dashboardUiConfig: {
            hideTitle: true,
            hideTab: true,
            hideChartControls: true,
            filters: {expanded: true,visible: true},
          },
          debug: true,
        });
        setStatus("success");
      } catch (err) {
        let message = "Unknown error occurred";
        if (err.response) {
          if (err.response.status === 401) {
            message = "Authentication required. Please log in again.";
            setTimeout(() => window.location.reload(), 2000);
          } else {
            const backendMsg = err.response.data?.error || err.response.statusText;
            message = `Backend error: ${err.response.status} — ${backendMsg}`;
          }
        } else if (err.request) {
          message = "Network error: unable to reach backend. Check backend URL and CORS.";
        } else {
          message = err.message || message;
        }

        setErrorMessage(message);
        setStatus("error");
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

  return (
  <div className="bg-white rounded-md shadow-lg mb-4 border border-gray-200 overflow-hidden">
    <div
      ref={containerRef}
      style={{
        width: "100%",
        height: "75vh",
        position: "relative",
      }}
    />
  </div>
);
};

export default SupersetChart;

