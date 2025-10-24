
import React, { useEffect, useState, useRef } from "react";
import axios from "axios";
import { embedDashboard } from "@superset-ui/embedded-sdk";
import { jwtDecode } from "jwt-decode";

const SupersetChart = ({ dashboardId, chartTitle }) => {
  const containerRef = useRef(null);
  const [status, setStatus] = useState("initial");
  const [errorMessage, setErrorMessage] = useState("");

  const BACKEND_URL = "http://localhost:5000/api/guest-token";
  const SUPERSET_DOMAIN = "http://localhost:8088";


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

        const apiStartTime = Date.now();
        const response = await axios.get(BACKEND_URL, {
          params: { dashboardId },
          timeout: 10000,
          withCredentials: true,
        });
        const apiEndTime = Date.now();


        const { guestToken } = response.data;

        if (!guestToken || !validateToken(guestToken)) {
          throw new Error("Invalid or expired guestToken returned by backend");
        }

        const embedStartTime = Date.now();
        await embedDashboard({
          id: dashboardId.toString(),
          supersetDomain: SUPERSET_DOMAIN,
          mountPoint: containerRef.current,
          fetchGuestToken: async () => {
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
        setStatus("success");
      } catch (err) {
        let message = "Unknown error occurred";
        if (err.response) {
          if (err.response.status === 401) {
            message = "Authentication required. Please log in again.";
            setTimeout(() => window.location.reload(), 2000);
          } else {
            message = `Backend error: ${err.response.status} - ${
              err.response.data?.error || err.response.statusText
            }`;
          }
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
  <div className="bg-white p-2 rounded-md shadow-lg mb-4 border border-gray-200">
    <div
      ref={containerRef}
      style={{
        width: "auto",
        overflow: "auto",
        position: "relative",
        borderRadius: "4px",
      }}
    />
  </div>
);
};

export default SupersetChart;

