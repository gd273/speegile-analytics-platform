import React, { useState, useEffect, useRef } from "react";
import api from "./api";
import SupersetChart from "./SupersetChart";
import Login from "./Login";
import UploadExcel from "./UploadExcel";
import { LogOut, Home, UploadCloud, Loader2, ChevronDown } from "lucide-react"; 
import { Routes, Route, Link, useNavigate, useLocation, Navigate } from 'react-router-dom';

console.log("DEBUG: REACT_APP_API_BASE_URL =", process.env.REACT_APP_API_BASE_URL);

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
  // ---------------------------

  const navigate = useNavigate();
  const location = useLocation();

  // Check Auth on Load
  useEffect(() => {
    checkAuth();
  }, []);

  // --- NEW: CLICK OUTSIDE LISTENER ---
  // If user clicks anywhere on the screen that is NOT the dropdown, close it.
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

  const checkAuth = async () => {
    try {
      const response = await api.get('/check-auth');
      if (response.data.authenticated) {
        setIsAuthenticated(true);
        setUser(response.data.user);
        fetchDashboards(); 
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
      const response = await api.get('/dashboards');
      if (response.data.success) {
        const dashboardList = response.data.dashboards.map(dash => ({
          id: dash.embedded_uuid,
          title: dash.dashboard_title,
          url: dash.url,
          roles: dash.roles
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

  const handleLoginSuccess = (userData) => {
    setIsAuthenticated(true);
    setUser(userData);
    fetchDashboards(); 
    navigate('/dashboards');
  };

  const handleLogout = async () => {
    try {
      await api.post('/logout');
    } catch (err) {
      console.error("Logout failed:", err);
    } finally {
      setIsAuthenticated(false);
      setUser(null);
      setDashboards([]); 
      navigate('/');
    }
  };

  const handleDashboardSelect = (id) => {
    setSelectedDashboardId(id);
    setIsDropdownOpen(false); // Close menu on selection
    navigate('/dashboards'); 
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
      
      {/* --- NAV BAR --- */}
      <nav className="w-full bg-white shadow-md flex items-center justify-between p-4 border-b border-gray-200 relative z-50">
        
        <div className="flex items-center gap-8">
          <div className="flex-shrink-0">
             <img src="/SpeegileLogo.jpeg" alt="Speegile Logo" className="w-32 h-auto object-contain" />
          </div>
          
          <div className="flex items-center gap-4">
            
            {/* --- DROPDOWN BUTTON (CLICK) --- */}
            <div className="relative" ref={dropdownRef}>
                <button
                  onClick={() => setIsDropdownOpen(!isDropdownOpen)} // Toggle on click
                  className={`flex items-center gap-2 px-3 py-2 rounded-lg transition select-none ${
                    isActive('/dashboards') || isDropdownOpen ? 'bg-blue-100 text-blue-700 font-semibold' : 'text-gray-600 hover:bg-gray-50'
                  }`}
                >
                  <Home className="w-4 h-4" />
                  Dashboards
                  <ChevronDown 
                    className={`w-4 h-4 ml-1 opacity-70 transition-transform duration-200 ${isDropdownOpen ? 'transform rotate-180' : ''}`} 
                  />
                </button>

                {/* THE DROPDOWN MENU */}
                {isDropdownOpen && (
                  <div className="absolute top-full left-0 mt-1 w-64 bg-white border border-gray-200 rounded-lg shadow-xl z-50 transform origin-top-left animate-in fade-in zoom-in-95 duration-100">
                      <div className="py-2 max-h-96 overflow-y-auto">
                          {dashboards.length === 0 ? (
                             <div className="px-4 py-3 text-sm text-gray-500">No dashboards available</div>
                          ) : (
                             dashboards.map((dash) => (
                               <button
                                 key={dash.id}
                                 onClick={() => handleDashboardSelect(dash.id)}
                                 className={`block w-full text-left px-4 py-3 text-sm hover:bg-gray-50 transition border-l-4 ${
                                   selectedDashboardId === dash.id 
                                     ? 'border-blue-600 text-blue-700 bg-blue-50 font-medium' 
                                     : 'border-transparent text-gray-700'
                                 }`}
                               >
                                 {dash.title}
                               </button>
                             ))
                          )}
                      </div>
                  </div>
                )}
            </div>
            
                {/* Pending To Add New Code */}
            <Link
              to="/upload"
              className={`flex items-center gap-3 p-3 rounded-lg transition ${
                isActive('/upload') ? 'bg-blue-100 text-blue-700 font-semibold' : 'text-gray-600 hover:bg-gray-50'
              }`}
            >
              <UploadCloud className="w-4 h-4" />
              Upload Data
            </Link>

            
          </div>
        </div>

        {/* Center Title */}
        <div className="absolute left-1/2 transform -translate-x-1/2 pointer-events-none">
           <span className="text-xl font-bold text-gray-800 tracking-tight">
              Speegile Analytics
             {/* In Future We Will Make This Dynamic*/}
           </span>
        </div>
        
        {/* Right Side: Logout */}
        <div className="flex items-center gap-6 ml-auto">
          <p className="text-sm text-gray-700 m-0">
            Signed in as: <span className="font-medium">{user.name || user.username}</span>
          </p>
          <button
            onClick={handleLogout}
            className="flex items-center gap-2 px-3 py-2 rounded-lg text-red-600 hover:bg-red-50 transition text-sm font-medium"
          >
            <LogOut className="w-4 h-4" />
            Logout
          </button>
        </div>
      </nav>

      {/* Main Content */}
      <main className="flex-1 overflow-y-auto p-8 bg-gray-100">
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
  const activeDashboard = dashboards.find(d => d.id === selectedId);

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
           <div className="mb-4">
              <h2 className="text-2xl font-semibold text-gray-800">{activeDashboard.title}</h2>
           </div>
           
           <SupersetChart 
             dashboardId={activeDashboard.id} 
             chartTitle={activeDashboard.title} 
           />
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