import React, { useState, useEffect, useRef, useMemo } from "react";
import api from "./api";
import SupersetChart from "./SupersetChart";
import Login from "./Login";
import UploadExcel from "./UploadExcel";
import OrientationWarning from "./Orientationwarning";
import UploadProgressPopup from "./UploadProgressPopup";


import {
  LogOut,
  Home,
  UploadCloud,
  Loader2,
  ChevronDown,
  Download,
  Menu,
  X,
} from "lucide-react";
import {
  Routes,
  Route,
  Link,
  useNavigate,
  useLocation,
  Navigate,
} from "react-router-dom";
import DashboardChartsPage from "./DashboardChartsPage";

//import html2canvas from 'html2canvas';
//import { jsPDF } from 'jspdf';
// const [isDownloading, setIsDownloading] = useState(false);

console.log(
  "DEBUG: REACT_APP_API_BASE_URL =",
  process.env.REACT_APP_API_BASE_URL,
);
console.log(
  "DEBUG: REACT_APP_SUPERSET_BASE_URL =",
  process.env.REACT_APP_SUPERSET_BASE_URL,
);

// --- Main App Wrapper ---
function App() {
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const [user, setUser] = useState(null);
  const [loading, setLoading] = useState(true);

  // Data State
  const [dashboards, setDashboards] = useState([]);
  const [selectedDashboardId, setSelectedDashboardId] = useState("");

  // --- NEW: DROPDOWN STATE ---
  const [isDropdownOpen, setIsDropdownOpen] = useState(false);
  const dropdownRef = useRef(null); // Used to detect clicks outside the menu
  const [hoveredCategory, setHoveredCategory] = useState(null);
  const flyoutTimeoutRef = useRef(null);

  // --- Logo's And Branding_Name ---
  const [logoUrl, setLogoUrl] = useState("");
  const [brandingName, setBrandingName] = useState("");
  const [defaultLogoUrl, setDefaultLogoUrl] = useState(
    "https://speegile-tenants.s3.ap-south-1.amazonaws.com/tenant-logo/SpeegileLogo.jpeg",
  ); // Fallback logo
  const [defaultBrandingName, setDefaultBrandingName] =
    useState("Speegile Analytics"); // Fallback branding name

  // upload access control state
  const [hasUploadAccess, setHasUploadAccess] = useState(false);

  //navbar state
  const [isMobileMenuOpen, setIsMobileMenuOpen] = useState(false);

  // ---------------------------

  const navigate = useNavigate();
  const location = useLocation();

  // Check Auth on Load
  useEffect(() => {
    checkAuth();
  }, []);

  useEffect(() => {
    if (isAuthenticated) {
      loadBranding();
    }
  }, [isAuthenticated]);
  // --- NEW: CLICK OUTSIDE LISTENER ---
  // If user clicks anywhere on the screen that is NOT the dropdown, close it.

  // ---------------------------------------------------------------
  // upload access control: only show upload tab if user has access
  // ---------------------------------------------------------------

  useEffect(() => {
    const checkUploadAccess = async () => {
      try {
        const response = await api.get("/upload_access"); // 👈 use api, not fetch
        setHasUploadAccess(response.data.success);
        console.log("Upload access response:", response.data);
      } catch (error) {
        console.error("Upload access check failed:", error);
        setHasUploadAccess(false);
      }
    };

    if (isAuthenticated) {
      checkUploadAccess();
    }
  }, [isAuthenticated]);

  const groupedDashboards = useMemo(() => {
    return dashboards.reduce((acc, dash) => {
      const cat = dash.category || "General";
      if (!acc[cat]) acc[cat] = [];
      acc[cat].push(dash);
      return acc;
    }, {});
  }, [dashboards]);

  useEffect(() => {
    function handleClickOutside(event) {
      if (dropdownRef.current && !dropdownRef.current.contains(event.target)) {
        setIsDropdownOpen(false);
      }
    }
    document.addEventListener("mousedown", handleClickOutside);
    return () => {
      document.removeEventListener("mousedown", handleClickOutside);
    };
  }, []);
  // -----------------------------------

  const loadBranding = async () => {
    try {
      const response = await api.get("/branding");
      const { logo_url, branding_name } = response.data;
      console.log("Calling branding API...", response.data);
      setLogoUrl(logo_url);
      setBrandingName(branding_name);
    } catch (error) {
      console.error("Failed to load branding:", error);
    }
  };

  const checkAuth = async () => {
    try {
      const response = await api.get("/check-auth");
      if (response.data.authenticated) {
        setIsAuthenticated(true);
        setUser(response.data.user);
        fetchDashboards();
        await loadBranding(); // 🔥 Load branding after auth
      } else {
        setIsAuthenticated(false);
        setUser(null);
      }
    } catch (err) {
      console.error("Auth check failed:", err);
      setIsAuthenticated(false);
      setUser(null);
    } finally {
      setLoading(false);
    }
  };

  const fetchDashboards = async () => {
    try {
      const response = await api.get("/dashboards");
      if (response.data.success) {
        const dashboardList = response.data.dashboards.map((dash) => ({
          id: dash.embedded_uuid,
          numericId: dash.id,
          title: dash.dashboard_title,
          url: dash.url,
          roles: dash.roles,
          category: dash.category || "General", // 👈 new ( Fetch the Category also )
        }));
        setDashboards(dashboardList);

        if (dashboardList.length > 0) {
          setSelectedDashboardId(dashboardList[0].id);
        }
      }
    } catch (err) {
      console.error("Failed to fetch dashboards", err);
    }
  };

  const handleLoginSuccess = async (userData) => {
    setIsAuthenticated(true);
    setUser(userData);
    fetchDashboards();
    await loadBranding(); // 👈 ADD THIS
    navigate("/dashboards");
  };

  const handleLogout = async () => {
    try {
      await api.post("/logout");
    } catch (err) {
      console.error("Logout failed:", err);
    } finally {
      setIsAuthenticated(false);
      setUser(null);
      setDashboards([]);
      navigate("/");
    }
  };

  const handleDashboardSelect = (id) => {
    setSelectedDashboardId(id);
    setIsDropdownOpen(false); // Close menu on selection
    navigate("/dashboards");
  };

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-100">
        <Loader2 className="w-8 h-8 text-blue-500 animate-spin" />
        <p className="ml-3 text-lg text-gray-700">Loading application...</p>
      </div>
    );
  }

  if (!isAuthenticated) {
    return <Login onLoginSuccess={handleLoginSuccess} />;
  }

  const isActive = (path) => location.pathname === path;

  return (
    <div className="h-screen bg-gray-100 font-sans flex flex-col overflow-hidden">
    <OrientationWarning />
      {/* --- NAV BAR --- */}
      <nav className="w-full bg-white shadow-md border-b border-gray-200 relative z-50">
        {/* ── DESKTOP NAV (md and above) ─────────────────────── */}
        <div className="hidden lg:flex items-center justify-between p-4">
          {/* Left: Logo + Dropdowns */}
          <div className="flex items-center gap-8">
            <div className="flex-shrink-0">
              <img
                src={logoUrl || defaultLogoUrl}
                alt="Company Logo"
                className="w-32 h-auto object-contain"
                onError={(e) => {
                  e.target.onerror = null;
                  e.target.src = defaultLogoUrl;
                }}
              />
            </div>

            <div className="flex items-center gap-4">
              {/* Dashboard Flyout Dropdown */}
              <div className="relative" ref={dropdownRef}>
                <button
                  onClick={() => {
                    setIsDropdownOpen(!isDropdownOpen);
                    setHoveredCategory(null);
                  }}
                  className={`flex items-center gap-2 px-3 py-2 rounded-lg transition select-none ${
                    isActive("/dashboards") || isDropdownOpen
                      ? "bg-blue-100 text-blue-700 font-semibold"
                      : "text-gray-600 hover:bg-gray-50"
                  }`}
                >
                  <Home className="w-4 h-4" />
                  Dashboards
                  <ChevronDown
                    className={`w-4 h-4 ml-1 opacity-70 transition-transform duration-200 ${isDropdownOpen ? "rotate-180" : ""}`}
                  />
                </button>

                {isDropdownOpen && (
                  <div className="absolute top-full left-0 mt-1 flex z-50 shadow-xl rounded-lg">
                    <div className="w-52 bg-white border border-gray-200 rounded-l-lg overflow-hidden">
                      {Object.keys(groupedDashboards).length === 0 ? (
                        <p className="px-4 py-3 text-sm text-gray-500">
                          No dashboards available
                        </p>
                      ) : (
                        Object.keys(groupedDashboards).map((category) => (
                          <div
                            key={category}
                            onMouseEnter={() => {
                              clearTimeout(flyoutTimeoutRef.current);
                              setHoveredCategory(category);
                            }}
                            onMouseLeave={() => {
                              flyoutTimeoutRef.current = setTimeout(
                                () => setHoveredCategory(null),
                                150,
                              );
                            }}
                            className={`flex items-center justify-between px-4 py-3 cursor-pointer text-sm transition border-l-4 ${
                              hoveredCategory === category
                                ? "bg-blue-50 text-blue-700 border-blue-600 font-medium"
                                : "text-gray-700 border-transparent hover:bg-gray-50"
                            }`}
                          >
                            <span>{category}</span>
                            <span className="flex items-center gap-1">
                              <span className="text-xs text-gray-400">
                                {groupedDashboards[category].length}
                              </span>
                              <ChevronDown className="w-3 h-3 -rotate-90 opacity-40" />
                            </span>
                          </div>
                        ))
                      )}
                    </div>

                    {hoveredCategory && groupedDashboards[hoveredCategory] && (
                      <div
                        onMouseEnter={() =>
                          clearTimeout(flyoutTimeoutRef.current)
                        }
                        onMouseLeave={() => {
                          flyoutTimeoutRef.current = setTimeout(
                            () => setHoveredCategory(null),
                            150,
                          );
                        }}
                        className="w-64 bg-white border border-l-0 border-gray-200 rounded-r-lg overflow-hidden max-h-80 overflow-y-auto"
                      >
                        <div className="px-4 py-2 bg-gray-50 border-b border-gray-100 sticky top-0">
                          <p className="text-xs font-semibold text-gray-500 uppercase tracking-wider">
                            {hoveredCategory}
                          </p>
                        </div>
                        {groupedDashboards[hoveredCategory].map((dash) => (
                          <button
                            key={dash.id}
                            onClick={() => handleDashboardSelect(dash.id)}
                            className={`block w-full text-left px-4 py-3 text-sm transition border-l-4 hover:bg-gray-50 ${
                              selectedDashboardId === dash.id
                                ? "border-blue-600 text-blue-700 bg-blue-50 font-medium"
                                : "border-transparent text-gray-700"
                            }`}
                          >
                            {dash.title}
                          </button>
                        ))}
                      </div>
                    )}
                  </div>
                )}
              </div>

              {/* Upload Link */}
              {hasUploadAccess && (
                <Link
                  to="/upload"
                  className={`flex items-center gap-3 p-3 rounded-lg transition ${
                    isActive("/upload")
                      ? "bg-blue-100 text-blue-700 font-semibold"
                      : "text-gray-600 hover:bg-gray-50"
                  }`}
                >
                  <UploadCloud className="w-4 h-4" />
                  Upload Data
                </Link>
                
              )}
              <UploadProgressPopup />
            </div>
          </div>

          {/* Center Title */}
          <div className="absolute left-1/2 transform -translate-x-1/2 pointer-events-none">
            <span className="text-xl font-bold text-gray-800 tracking-tight">
              {brandingName && brandingName.trim() !== ""
                ? brandingName
                : defaultBrandingName}
            </span>
          </div>

          {/* Right: User + Logout */}
          <div className="flex items-center gap-6 ml-auto">
            <p className="text-sm text-gray-700 m-0">
              Signed in as:{" "}
              <span className="font-medium">{user.name || user.username}</span>
            </p>
            <button
              onClick={handleLogout}
              className="flex items-center gap-2 px-3 py-2 rounded-lg text-red-600 hover:bg-red-50 transition text-sm font-medium"
            >
              <LogOut className="w-4 h-4" />
              Logout
            </button>
          </div>
        </div>

        {/* ── MOBILE NAV (below md) ──────────────────────────── */}
        <div className="flex lg:hidden items-center justify-between px-4 py-3">
          {/* Hamburger Button */}
          <button
            onClick={() => setIsMobileMenuOpen(!isMobileMenuOpen)}
            className="p-2 rounded-lg text-gray-600 hover:bg-gray-100 transition"
          >
            {isMobileMenuOpen ? (
              <X className="w-6 h-6" />
            ) : (
              <Menu className="w-6 h-6" />
            )}
          </button>

          {/* Center Logo on mobile */}
          <img
            src={logoUrl || defaultLogoUrl}
            alt="Company Logo"
            className="w-24 h-auto object-contain"
            onError={(e) => {
              e.target.onerror = null;
              e.target.src = defaultLogoUrl;
            }}
          />

          {/* Right: Logout icon only on mobile */}
          <button
            onClick={handleLogout}
            className="p-2 rounded-lg text-red-500 hover:bg-red-50 transition"
          >
            <LogOut className="w-5 h-5" />
          </button>
        </div>

        {/* ── MOBILE SLIDE-IN DRAWER (left side) ─────────────── */}

        {/* Overlay — dark background behind drawer */}
        {/* {isMobileMenuOpen && (
          <div
            className="fixed inset-0 bg-black bg-opacity-50 z-40 md:hidden"
            onClick={() => setIsMobileMenuOpen(false)} // click outside to close
          />
        )} */}

        {isMobileMenuOpen && (
              <div
                className="fixed inset-0 z-40 md:hidden"
                style={{ background: "rgba(0,0,0,0.5)" }}
                onClick={() => setIsMobileMenuOpen(false)}
              />
            )}

        {/* Drawer */}
        {/* <div
          className={`fixed top-0 left-0 h-full w-72 bg-white z-50 shadow-2xl flex flex-col
              transform transition-transform duration-300 ease-in-out md:hidden
              ${isMobileMenuOpen ? "translate-x-0" : "-translate-x-full"}`}
        > */}
        {/* New Drawer */}
        <div
              className="fixed top-0 left-0 h-full w-72 bg-white z-50 shadow-2xl flex flex-col transform transition-transform duration-300 ease-in-out lg:hidden"
              style={{ transform: isMobileMenuOpen ? "translateX(0)" : "translateX(-100%)" }}
          >
          {/* Drawer Header — Logo + Close button */}
          <div className="flex items-center justify-between px-4 py-3 border-b border-gray-100">
            <img
              src={logoUrl || defaultLogoUrl}
              alt="Company Logo"
              className="w-24 h-auto object-contain"
              onError={(e) => {
                e.target.onerror = null;
                e.target.src = defaultLogoUrl;
              }}
            />
            <button
              onClick={() => setIsMobileMenuOpen(false)}
              className="p-2 rounded-lg text-gray-400 hover:bg-gray-100 transition"
            >
              <X className="w-5 h-5" />
            </button>
          </div>

          {/* Signed in as — fixed */}
          <div className="px-4 py-3 border-b border-gray-100 bg-gray-50 flex-shrink-0">
            <p className="text-xs text-gray-500 uppercase tracking-wider font-medium mb-1">
              Signed in as
            </p>
            <p className="text-sm font-semibold text-gray-800">
              {user.name || user.username}
            </p>
          </div>

          {/* Scrollable middle — Dashboards + Upload */}
          <div className="flex-1 overflow-y-auto">
            <div className="px-4 py-3">
              <p className="text-xs text-gray-500 uppercase tracking-wider font-medium mb-2">
                Dashboards
              </p>

              {Object.keys(groupedDashboards).length === 0 ? (
                <p className="text-sm text-gray-400">No dashboards available</p>
              ) : (
                Object.keys(groupedDashboards).map((category) => (
                  <div key={category} className="mb-4">
                    {/* Category label */}
                    <p className="text-xs font-semibold text-blue-600 uppercase tracking-wider mb-1 px-1">
                      {category}
                    </p>
                    {/* Dashboard buttons */}
                    {groupedDashboards[category].map((dash) => (
                      <button
                        key={dash.id}
                        onClick={() => {
                          handleDashboardSelect(dash.id);
                          setIsMobileMenuOpen(false);
                        }}
                        className={`block w-full text-left px-3 py-2 text-sm rounded-lg mb-1 transition border-l-4 ${
                          selectedDashboardId === dash.id
                            ? "border-blue-600 text-blue-700 bg-blue-50 font-medium"
                            : "border-transparent text-gray-700 hover:bg-gray-50"
                        }`}
                      >
                        {dash.title}
                      </button>
                    ))}
                  </div>
                ))
              )}
            </div>

            {/* Upload Data */}
            {hasUploadAccess && (
              <div className="px-4 pb-3 border-t border-gray-100 pt-3">
                <Link
                  to="/upload"
                  onClick={() => setIsMobileMenuOpen(false)}
                  className={`flex items-center gap-3 px-3 py-2 rounded-lg transition text-sm ${
                    isActive("/upload")
                      ? "bg-blue-100 text-blue-700 font-semibold"
                      : "text-gray-600 hover:bg-gray-50"
                  }`}
                >
                  <UploadCloud className="w-4 h-4" />
                  Upload Data
                </Link>
              </div>
            )}
          </div>

          {/* Logout — fixed at bottom */}
          <div className="px-4 py-4 border-t border-gray-100 flex-shrink-0">
            <button
              onClick={handleLogout}
              className="flex items-center gap-3 px-3 py-2 rounded-lg text-red-600
                 hover:bg-red-50 transition text-sm font-medium w-full"
            >
              <LogOut className="w-4 h-4" />
              Logout
            </button>
          </div>
        </div>
      </nav>

      {/* Main Content */}
      <main className="flex-1 overflow-y-auto p-2 bg-gray-100">
        <Routes>
          <Route path="/" element={<Navigate to="/dashboards" replace />} />
          <Route
            path="/dashboards"
            element={
              <DashboardView
                dashboards={dashboards}
                selectedId={selectedDashboardId}
              />
            }
          />
          <Route path="/upload" element={<UploadExcel navigate={navigate} />} />
        </Routes>
      </main>
    </div>
  );
}

// --- Simplified Dashboard View ---
function DashboardView({ dashboards, selectedId }) {
  const [isDownloading, setIsDownloading] = useState(false);
  const [pdfFn, setPdfFn] = useState(null);
  const activeDashboard = dashboards.find((d) => d.id === selectedId);
  const dashboardRef = useRef(null); // Reference to the dashboard container
  // const demo = ()=>{
  //   alert("Download PDF functionality coming soon!");
  // }

  const handleDownloadPDF = async () => {
    if (!activeDashboard) return;

    setIsDownloading(true); // add this state

    try {
      const response = await api.get("/download-dashboard-pdf", {
        params: {
          dashboardId: activeDashboard.numericId, // numeric ID from fetchDashboards
          title: activeDashboard.title,
        },
        responseType: "blob", // important — tells axios to expect binary data
        timeout: 60000, // 60s timeout for screenshot generation
      });

      // Create download link
      const url = window.URL.createObjectURL(new Blob([response.data]));
      const link = document.createElement("a");
      link.href = url;
      link.setAttribute(
        "download",
        `${activeDashboard.title || "Dashboard"}.pdf`,
      );
      document.body.appendChild(link);
      link.click();
      link.remove();
      window.URL.revokeObjectURL(url);
    } catch (error) {
      console.error("PDF download failed:", error);
      alert("Failed to generate PDF. Please try again.");
    } finally {
      setIsDownloading(false);
    }
  };

  // DownloadPDF functionality coming soon!
  return (
    <div className="w-full">
      {dashboards.length === 0 && (
        <div className="text-center py-12">
          <p className="text-gray-500">Loading dashboards...</p>
        </div>
      )}

      {activeDashboard ? (
        <div key={activeDashboard.id} className="mb-8">
          {/* Title above the chart */}
          {/* <div className="mb-4 flex items-center justify-between">
            <h2 className="text-2xl font-semibold text-gray-800">
              {activeDashboard.title}
            </h2>
            {/* <button 
                onClick={handleDownloadPDF}
                disabled={isDownloading}
                className="px-6 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition flex items-center gap-2 disabled:opacity-50 disabled:cursor-not-allowed"
              >
                {isDownloading ? (
                  <>
                    <Loader2 className="w-4 h-4 animate-spin" />
                    Generating PDF...
                  </>
                ) : (
                  'Download Dashboard PDF'  
                )}
              </button> */}
          {/* </div> */} 

          <div className="mb-4 flex items-center justify-between">
              <h2 className="text-2xl font-semibold text-gray-800">
                {activeDashboard.title}
              </h2>

              {pdfFn && (
                <button
                  onClick={pdfFn}
                  className="flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-semibold transition"
                  style={{
                    border: "1px solid rgba(31,168,201,0.4)",
                    background: "rgba(31,168,201,0.08)",
                    color: "#1FA8C9",
                    cursor: "pointer",
                  }}
                >
                  <Download className="w-4 h-4" />
                  Download PDF
                </button>
              )}
              </div>

          {/* THE CAPTURE AREA */}
          <div ref={dashboardRef} className="bg-white p-4 rounded-xl shadow-sm">
            {/*<SupersetChart 
               dashboardId={activeDashboard.id} 
               chartTitle={activeDashboard.title} 
             />*/}
            <DashboardChartsPage
              dashboardNumericId={activeDashboard.numericId}
              dashboardTitle={activeDashboard.title}
              onPdfReady={setPdfFn}
            />
          </div>

          {/* <SupersetChart 
             dashboardId={activeDashboard.id} 
             chartTitle={activeDashboard.title} 
           /> */}
        </div>
      ) : (
        dashboards.length > 0 && (
          <div className="text-center py-12 text-gray-500">
            Please select a dashboard from the menu above.
          </div>
        )
      )}
    </div>
  );
}

export default App;
