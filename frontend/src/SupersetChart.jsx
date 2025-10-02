
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
      console.log(" - Roles:", decoded.user?.roles || "N/A");
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
              expanded: false,
              visible: false,
            },
          },
          debug: true,
        });
        const embedEndTime = Date.now();

        console.log(
          `[SUCCESS] Dashboard embedded in ${embedEndTime - embedStartTime}ms.`
        );
        setStatus("success");
      } catch (err) {
        console.error("[ERROR BLOCK] Embedding failed:", err);

        let message = "Unknown error occurred";
        if (err.response) {
          message = `Backend error: ${err.response.status} - ${
            err.response.data?.error || err.response.statusText
          }`;
        } else if (err.request) {
          message =
            "Network error: Unable to reach backend server (check CORS/server status).";
        } else if (err.message) {
          message = err.message;
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

  return (
    <div className="bg-white p-4 rounded-xl shadow-lg mb-8 border border-gray-200">
      <h2 className="text-2xl font-bold text-gray-800 mb-3">{chartTitle}</h2>

      {status === "loading" && (
        <div className="flex items-center justify-center p-8">
          <div className="text-blue-600">Loading chart...</div>
        </div>
      )}

      {status === "error" && (
        <div className="bg-red-50 border border-red-200 rounded p-4">
          <h3 className="text-red-800 font-semibold">Error Loading Chart</h3>
          <p className="text-red-600 mt-2">{errorMessage}</p>
          <div className="mt-3">
            <button
              onClick={() => window.location.reload()}
              className="px-4 py-2 bg-red-600 text-white rounded hover:bg-red-700 mr-2"
            >
              Retry
            </button>
            <a
              href={`${SUPERSET_DOMAIN}/dashboard/${dashboardId}`}
              target="_blank"
              rel="noopener noreferrer"
              className="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700"
            >
              View in Superset
            </a>
          </div>
        </div>
      )}

      <div
        ref={containerRef}
        style={{
          minHeight: "400px",
          width: "100%",
          border: status === "loading" ? "1px dashed #ccc" : "none",
          borderRadius: "8px",
        }}
      />
    </div>
  );
};

export default SupersetChart;

// import React, { useEffect, useState, useRef } from "react";
// import axios from "axios";
// import { embedDashboard } from "@superset-ui/embedded-sdk";

// const SupersetChart = ({ dashboardId, chartTitle }) => {
//   const containerRef = useRef(null);
//   const [status, setStatus] = useState("loading");
//   const [errorMessage, setErrorMessage] = useState("");

//   const BACKEND_URL = "http://localhost:5000/api/guest-token";
//   const SUPERSET_DOMAIN = "http://localhost:8088";

//   useEffect(() => {
//     if (!dashboardId) return;
    
//     console.log("SupersetChart useEffect running for dashboardId:", dashboardId);
    
//     const loadDashboard = async () => {
//       try {
//         setStatus("loading");
//         setErrorMessage("");

//         // Clear any previous embedded content
//         if (containerRef.current) {
//           containerRef.current.innerHTML = '';
//         }

//         console.log("Requesting guest token for dashboard:", dashboardId);
        
//         // 1. Fetch Guest Token from Flask backend
//         const response = await axios.get(BACKEND_URL, {
//           params: { dashboardId },
//           timeout: 10000,
//         });
        
//         const { guestToken } = response.data;
        
//         if (!guestToken) {
//           throw new Error("No guestToken returned by backend");
//         }

//         console.log("Guest token received, embedding dashboard...");

//         // 2. Embed dashboard using official SDK (should work with Superset 4.0+)
//         await embedDashboard({
//           id: dashboardId.toString(),
//           supersetDomain: SUPERSET_DOMAIN,
//           mountPoint: containerRef.current,
//           fetchGuestToken: () => Promise.resolve(guestToken),
//           dashboardUiConfig: {
//             hideTitle: true,
//             hideTab: true,
//             hideChartControls: true,
//             filters: {
//               expanded: false,
//               visible: false
//             }
//           },
//           debug: false,
//         });

//         console.log("Dashboard embedded successfully");
//         setStatus("success");
//       } catch (err) {
//         console.error("Embedding failed:", err);
        
//         let message = "Unknown error occurred";
//         if (err.response) {
//           message = `Backend error: ${err.response.status} - ${err.response.data?.error || err.response.statusText}`;
//         } else if (err.request) {
//           message = "Network error: Unable to reach backend server";
//         } else if (err.message) {
//           message = err.message;
//         }
        
//         setErrorMessage(message);
//         setStatus("error");
//       }
//     };

//     loadDashboard();

//     // Cleanup function
//     return () => {
//       if (containerRef.current) {
//         containerRef.current.innerHTML = '';
//       }
//     };
//   }, [dashboardId]);

//   return (
//     <div className="bg-white p-4 rounded-xl shadow-lg mb-8 border border-gray-200">
//       <h2 className="text-2xl font-bold text-gray-800 mb-3">{chartTitle}</h2>
      
//       {status === "loading" && (
//         <div className="flex items-center justify-center p-8">
//           <div className="text-blue-600">Loading chart...</div>
//         </div>
//       )}
      
//       {status === "error" && (
//         <div className="bg-red-50 border border-red-200 rounded p-4">
//           <h3 className="text-red-800 font-semibold">Error Loading Chart</h3>
//           <p className="text-red-600 mt-2">{errorMessage}</p>
//           <div className="mt-3">
//             <button 
//               onClick={() => window.location.reload()} 
//               className="px-4 py-2 bg-red-600 text-white rounded hover:bg-red-700 mr-2"
//             >
//               Retry
//             </button>
//             <a 
//               href={`${SUPERSET_DOMAIN}/dashboard/${dashboardId}`}
//               target="_blank"
//               rel="noopener noreferrer"
//               className="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700"
//             >
//               View in Superset
//             </a>
//           </div>
//         </div>
//       )}
      
//       <div 
//         ref={containerRef} 
//         style={{ 
//           minHeight: "400px",
//           width: "100%",
//           border: status === "loading" ? "1px dashed #ccc" : "none",
//           borderRadius: "8px"
//         }} 
//       />
//     </div>
//   );
// };

// export default SupersetChart;



// import React, { useEffect, useState, useRef } from "react";
// import axios from "axios";
// import { embedDashboard } from "@superset-ui/embedded-sdk";
// import jwtDecode from "jwt-decode";

// const isTokenExpired = (token) => {
//   try {
//     const decoded = jwtDecode(token);
//     if (!decoded.exp) return false; // no expiry claim
//     const now = Math.floor(Date.now() / 1000);
//     return decoded.exp < now;
//   } catch (e) {
//     return true; // invalid token
//   }
// };

// fetchGuestToken: async () => {
//   if (isTokenExpired(guestToken)) {
//     console.error("[TOKEN ERROR] Guest token expired.");
//     throw new Error("Expired guest token");
//   }
//   return guestToken;
// }

// const validateToken = (token) => {
//   try {
//     const decoded = jwtDecode(token);
//     console.log("[TOKEN DECODED]", decoded);

//     // Check expiry
//     if (decoded.exp && decoded.exp < Math.floor(Date.now() / 1000)) {
//       console.error("[TOKEN ERROR] Token expired at:", new Date(decoded.exp * 1000));
//       return false;
//     }

//     // Check roles and resources
//     if (!decoded.resources || decoded.resources.length === 0) {
//       console.error("[TOKEN ERROR] No resources in token.");
//       return false;
//     }

//     return true;
//   } catch (e) {
//     console.error("[TOKEN ERROR] Failed to decode JWT:", e);
//     return false;
//   }
// };

// const SupersetChart = ({ dashboardId, chartTitle }) => {
//   const containerRef = useRef(null);
//   const [status, setStatus] = useState("initial"); // Changed initial state for clearer logging
//   const [errorMessage, setErrorMessage] = useState("");

//   const BACKEND_URL = "http://localhost:5000/api/guest-token";
//   const SUPERSET_DOMAIN = "http://localhost:8088";

//   // --- COMPONENT INITIALIZATION DEBUG ---
//   console.log("SupersetChart Component Rendered. Dashboard ID:", dashboardId);

//   useEffect(() => {
//     // --- USE EFFECT START DEBUG ---
//     console.log("\n--- useEffect Hook Fired ---");
//     console.log("Current dashboardId state:", dashboardId);
    
//     if (!dashboardId) {
//         console.log("No dashboardId provided. Exiting useEffect.");
//         return;
//     }
    
//     // Initial status set and constant logging
//     console.log("Target Superset Domain:", SUPERSET_DOMAIN);
//     console.log("Target Backend URL:", BACKEND_URL);

//     const loadDashboard = async () => {
//       try {
//         console.log(`[PROCESS] Starting loadDashboard for ID: ${dashboardId}`);
//         setStatus("loading");
//         setErrorMessage("");

//         // Clear any previous embedded content
//         if (containerRef.current) {
//           console.log("[PROCESS] Clearing previous content in container.");
//           containerRef.current.innerHTML = '';
//         }

//         console.log(`[API CALL] Requesting guest token from: ${BACKEND_URL}`);
        
//         // 1. Fetch Guest Token from Flask backend
//         const apiStartTime = Date.now();
//         const response = await axios.get(BACKEND_URL, {
//           params: { dashboardId },
//           timeout: 10000,
//         });
//         const apiEndTime = Date.now();
        
//         console.log(`[API RESPONSE] Received response in ${apiEndTime - apiStartTime}ms.`);
//         console.log("API Response Status:", response.status);
//         console.log("API Response Data:", response.data);
        
//         const { guestToken } = response.data;
        
//         if (!guestToken) {
//           console.error("[ERROR] Validation failed: guestToken is missing in the response.");
//           throw new Error("No guestToken returned by backend");
//         }
        
//         // Show a snippet of the token
//         console.log(`[TOKEN INFO] Guest token received. Snippet: ${guestToken.substring(0, 30)}...`);

//         // 2. Embed dashboard using official SDK
//         console.log("[PROCESS] Starting Superset embedDashboard SDK call...");
//         console.log("SDK Config (ID/Domain):", dashboardId, SUPERSET_DOMAIN);
        
//         const embedStartTime = Date.now();
//         await embedDashboard({
//           id: dashboardId.toString(),
//           supersetDomain: SUPERSET_DOMAIN,
//           mountPoint: containerRef.current,
//           // The SDK will call this function to get the token
//           fetchGuestToken: () => {
//              console.log("[SDK CALL] fetchGuestToken function executed by embedded-sdk.");
//             //  return Promise.resolve(guestToken);
//               if (!guestToken || typeof guestToken !== "string") {
//                 console.error("[TOKEN ERROR] Guest token missing or invalid format:", guestToken);
//                 throw new Error("Invalid guest token");
//               }
// // Optional: check if it looks like a JWT (3 dot-separated parts)
//               if (guestToken.split(".").length !== 3) {
//                 console.error("[TOKEN ERROR] Guest token is not a proper JWT.");
//                 throw new Error("Malformed guest token");
//               }

//               console.log("[TOKEN OK] Returning token to SDK. Snippet:", guestToken.substring(0, 25) + "...");
//               return guestToken;
//           },
//           dashboardUiConfig: {
//             hideTitle: true,
//             hideTab: true,
//             hideChartControls: true,
//             filters: {
//               expanded: false,
//               visible: false
//             }
//           },
//           debug: true, // IMPORTANT: Enable internal SDK logging
//         });
//         const embedEndTime = Date.now();

//         console.log(`[SUCCESS] Dashboard embedded successfully in ${embedEndTime - embedStartTime}ms.`);
//         setStatus("success");
//       } catch (err) {
//         // --- CATCH BLOCK DEBUG ---
//         console.error("\n[ERROR BLOCK] Embedding process failed. Details:", err);
        
//         let message = "Unknown error occurred";
//         if (err.response) {
//           // Backend responded with an error status (e.g., 400, 500)
//           console.error(`[ERROR TYPE] Backend Error (Status ${err.response.status})`);
//           message = `Backend error: ${err.response.status} - ${err.response.data?.error || err.response.statusText}`;
//         } else if (err.request) {
//           // Request was made but no response was received (Network error, CORS issue, timeout)
//           console.error("[ERROR TYPE] Network/Request Error (Backend offline or timeout)");
//           message = "Network error: Unable to reach backend server (check CORS/server status).";
//         } else if (err.message) {
//           // Other errors (e.g., throw new Error("No guestToken returned..."))
//           console.error(`[ERROR TYPE] Client/Generic Error: ${err.message}`);
//           message = err.message;
//         }
        
//         setErrorMessage(message);
//         setStatus("error");
//         console.log(`[STATUS CHANGE] Set status to 'error' with message: ${message}`);
//       }
//     };

//     loadDashboard();

//     // Cleanup function
//     return () => {
//       console.log("[CLEANUP] Component unmounting or dashboardId changing. Clearing container.");
//       if (containerRef.current) {
//         containerRef.current.innerHTML = '';
//       }
//     };
//   }, [dashboardId]);

//   return (
//     <div className="bg-white p-4 rounded-xl shadow-lg mb-8 border border-gray-200">
//       <h2 className="text-2xl font-bold text-gray-800 mb-3">{chartTitle}</h2>
      
//       {status === "loading" && (
//         <div className="flex items-center justify-center p-8">
//           <div className="text-blue-600">Loading chart...</div>
//         </div>
//       )}
      
//       {status === "error" && (
//         <div className="bg-red-50 border border-red-200 rounded p-4">
//           <h3 className="text-red-800 font-semibold">Error Loading Chart</h3>
//           <p className="text-red-600 mt-2">{errorMessage}</p>
//           <div className="mt-3">
//             <button 
//               onClick={() => window.location.reload()} 
//               className="px-4 py-2 bg-red-600 text-white rounded hover:bg-red-700 mr-2"
//             >
//               Retry
//             </button>
//             <a 
//               href={`${SUPERSET_DOMAIN}/dashboard/${dashboardId}`}
//               target="_blank"
//               rel="noopener noreferrer"
//               className="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700"
//             >
//               View in Superset
//             </a>
//           </div>
//         </div>
//       )}
      
//       {/* Container where Superset iframe will be mounted */}
//       <div 
//         ref={containerRef} 
//         style={{ 
//           minHeight: "400px",
//           width: "100%",
//           border: status === "loading" ? "1px dashed #ccc" : "none",
//           borderRadius: "8px"
//         }} 
//       />
//     </div>
//   );
// };

// export default SupersetChart;


