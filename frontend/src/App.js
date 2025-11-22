
import React, { useState, useEffect } from "react";
import api from "./api";
import SupersetChart from "./SupersetChart";
import Login from "./Login";
import UploadExcel from "./UploadExcel";
// import CreateUser from "./CreateUser"; // Import the new component
import { LogOut, Home, UploadCloud, Loader2, UserPlus } from "lucide-react"; 
import { Routes, Route, Link, useNavigate, useLocation, Navigate } from 'react-router-dom';


console.log("DEBUG: REACT_APP_API_BASE_URL =", process.env.REACT_APP_API_BASE_URL);

// --- Main App Wrapper ---
function App() {
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const [user, setUser] = useState(null);
  const [loading, setLoading] = useState(true);
  const navigate = useNavigate();
  const location = useLocation();

  // Check Auth on Load
  useEffect(() => {
    checkAuth();
  }, []);

  const checkAuth = async () => {
    try {
      const response = await api.get('/check-auth');
      if (response.data.authenticated) {
        setIsAuthenticated(true);
        setUser(response.data.user);
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

  const handleLoginSuccess = (userData) => {
    setIsAuthenticated(true);
    setUser(userData);
    navigate('/dashboards'); // Go to dashboards after login
  };

  const handleLogout = async () => {
    try {
      await api.post('/logout');
    } catch (err) {
      console.error("Logout failed:", err);
    } finally {
      setIsAuthenticated(false);
      setUser(null);
      navigate('/');
    }
  };

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-100">
        <Loader2 className="w-8 h-8 text-blue-500 animate-spin" />
        <p className="ml-3 text-lg text-gray-700">Loading application...</p>
      </div>
    );
  }

  // If not authenticated, show Login
  if (!isAuthenticated) {
    return <Login onLoginSuccess={handleLoginSuccess} />;
  }

  // Helper to check active route for styling
  const isActive = (path) => location.pathname === path;

  return (
    <div className="min-h-screen bg-gray-100 font-sans flex">
      {/* Sidebar Navigation */}
      <nav className="w-64 bg-white shadow-xl flex flex-col p-4 border-r border-gray-200">
        <div className="flex-grow">
          <h1 className="text-2xl font-bold text-blue-600 mb-6 border-b pb-4 pl-2">Data Portal</h1>
          
          <div className="space-y-2">
            <Link
              to="/dashboards"
              className={`w-full flex items-center gap-3 p-3 rounded-lg transition ${
                isActive('/dashboards') ? 'bg-blue-100 text-blue-700 font-semibold' : 'text-gray-600 hover:bg-gray-50'
              }`}
            >
              <Home className="w-5 h-5" />
              Dashboards
            </Link>

            <Link
              to="/upload"
              className={`w-full flex items-center gap-3 p-3 rounded-lg transition ${
                isActive('/upload') ? 'bg-blue-100 text-blue-700 font-semibold' : 'text-gray-600 hover:bg-gray-50'
              }`}
            >
              <UploadCloud className="w-5 h-5" />
              Upload Data
            </Link>

            {/* Admin Link - Only visible to Admins */}
            {/*{user && user.roles.includes('Admin') && (
              <Link 
                to="/admin/create-user"
                className={`w-full flex items-center gap-3 p-3 rounded-lg transition ${
                  isActive('/admin/create-user') ? 'bg-red-50 text-red-600 font-semibold' : 'text-gray-600 hover:bg-gray-50'
                }`}
              >
                <UserPlus className="w-5 h-5 text-red-500" />
                <span className="text-red-600">Add User</span>
              </Link>
            )}
           */}
          </div>
        </div>
        
        {/* User Info & Logout */}
        <div className="pt-4 border-t border-gray-200">
          <p className="text-sm text-gray-700 mb-3 truncate px-2">
            Signed in as: <span className="font-medium">{user.name || user.username}</span>
          </p>
          <button
            onClick={handleLogout}
            className="w-full flex items-center gap-3 p-3 rounded-lg text-red-600 hover:bg-red-50 transition font-medium"
          >
            <LogOut className="w-5 h-5" />
            Logout
          </button>
        </div>
      </nav>

      {/* Main Content Area - Handles Routing */}
      <main className="flex-1 p-8 overflow-y-auto">
        <Routes>
          <Route path="/" element={<Navigate to="/dashboards" replace />} />
          <Route path="/dashboards" element={<DashboardView />} />
          <Route path="/upload" element={<UploadExcel navigate={navigate} />} />
          {/*<Route path="/admin/create-user" element={<CreateUser />} />*/}
        </Routes>
      </main>
    </div>
  );
}

// --- Sub-Component for Dashboards Logic ---
// We moved this logic out of App() to keep the main file clean
function DashboardView() {
  const [dashboards, setDashboards] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    fetchDashboards();
  }, []);

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
      } else {
        setError("Failed to load dashboards");
      }
    } catch (err) {
      setError("Failed to load dashboards");
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="max-w-7xl mx-auto">
      <header className="mb-8 border-b pb-4">
        <h2 className="text-3xl font-semibold text-gray-800">Superset Dashboards</h2>
        <p className="text-gray-500 mt-1">Visualizations embedded directly from Superset.</p>
      </header>

      {loading && (
        <div className="text-center py-12">
          <Loader2 className="w-8 h-8 text-blue-500 animate-spin mx-auto" />
          <p className="mt-3 text-gray-600">Loading dashboards...</p>
        </div>
      )}

      {error && (
        <div className="p-4 bg-red-50 rounded-xl text-red-600 mb-6">
          {error} <button onClick={fetchDashboards} className="underline ml-2 font-bold">Retry</button>
        </div>
      )}

      {!loading && !error && dashboards.length === 0 && (
        <div className="text-center py-12 bg-white rounded-xl shadow-md">
          <p className="text-gray-500">You don't have access to any dashboards yet.</p>
        </div>
      )}

      {dashboards.map((dash) => (
        <div key={dash.id} className="mb-8">
          <SupersetChart dashboardId={dash.id} chartTitle={dash.title} />
        </div>
      ))}
    </div>
  );
}

export default App;