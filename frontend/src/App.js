import React, { useState, useEffect } from "react";
import api from "./api";
import SupersetChart from "./SupersetChart";
import Login from "./Login";
import UploadExcel from "./UploadExcel";
import { LogOut, Home, UploadCloud, Loader2 } from "lucide-react"; 

function App() {
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const [user, setUser] = useState(null);
  const [dashboards, setDashboards] = useState([]);
  const [loading, setLoading] = useState(true);
  const [dashboardsLoading, setDashboardsLoading] = useState(false);
  const [error, setError] = useState(null);
  const [currentView, setCurrentView] = useState('dashboards'); 

  useEffect(() => {
    console.log("App.js checkauth");
    checkAuth();
  }, []);

  const checkAuth = async () => {
    try {
      console.log("App.js checkauth im fn");
      const response = await api.get('/check-auth');

      if (response.data.authenticated) {
        setIsAuthenticated(true);
        setUser(response.data.user);
        // Fetch dashboards after authentication is confirmed
        console.log("App.js checkauth im fn and trying to fetch dasboard");
        await fetchDashboards();
      } else {
        console.log("❌ User not authenticated")
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
    console.log("App.js in fetchdashboard");
    console.log("📊 Fetching accessible dashboards...");
    setDashboardsLoading(true);
    setError(null);

    try {
      const response = await api.get('/dashboards');
      console.log("✅ Dashboards API Response:", response.data);

      if (response.data.success) {
        const dashboardList = response.data.dashboards.map(dash => ({
          id: dash.embedded_uuid,  // Use UUID for embedding
          title: dash.dashboard_title,
          url: dash.url,
          roles: dash.roles
        }));

        setDashboards(dashboardList);
        console.log(`✅ Loaded ${dashboardList.length} dashboards for user`);
      } else {
        setError("Failed to load dashboards");
      }
    } catch (err) {
      console.error("❌ Failed to fetch dashboards:", err);
      setError(err.response?.data?.error || "Failed to load dashboards");
    } finally {
      setDashboardsLoading(false);
    }
  };

  const handleLoginSuccess = async (userData) => {
    console.log("App.js in handleLoginSuccess");
    setIsAuthenticated(true);
    setUser(userData);
    // Fetch dashboards after successful login
    await checkAuth();
    await fetchDashboards();
  };

  const handleLogout = async () => {
    console.log("App.js in handleLogout");
    console.log("🔴 Logout clicked");
    
    try {
      const response = await api.post('/logout');
      console.log("✅ Backend logout successful:", response.data);
    } catch (err) {
      console.error("❌ Backend logout failed:", err);
    } finally {
      console.log("🧹 Clearing local state...");
      setIsAuthenticated(false);
      setUser(null);
      setDashboards([]);
      setCurrentView('dashboards');
    }
  };

const navigate = async (view) => {
    console.log(`🔄 Navigating to: ${view}`);
    setCurrentView(view);
    
    // Add a small delay to avoid concurrent requests
    if (view === 'dashboards') {
        // Small delay to let other requests complete
        await new Promise(resolve => setTimeout(resolve, 100));
        await fetchDashboards(); 
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

  // If not authenticated, show the Login component
  if (!isAuthenticated) {
    return <Login onLoginSuccess={handleLoginSuccess} />;
  }

  // If authenticated, show the main application UI
  return (
    <div className="min-h-screen bg-gray-100 font-sans flex">
      {/* Sidebar Navigation */}
      <nav className="w-56 bg-white shadow-xl flex flex-col p-4 border-r border-gray-200">
        <div className="flex-grow">
          <h1 className="text-2xl font-bold text-blue-600 mb-6 border-b pb-4">Data Portal</h1>
          
          <div className="space-y-2">
            <button
              onClick={() => navigate('dashboards')}
              className={`w-full flex items-center gap-3 p-3 rounded-lg transition ${
                currentView === 'dashboards' ? 'bg-blue-100 text-blue-700 font-semibold' : 'text-gray-600 hover:bg-gray-50'
              }`}
            >
              <Home className="w-5 h-5" />
              Dashboards
            </button>
            <button
              onClick={() => navigate('upload')}
              className={`w-full flex items-center gap-3 p-3 rounded-lg transition ${
                currentView === 'upload' ? 'bg-blue-100 text-blue-700 font-semibold' : 'text-gray-600 hover:bg-gray-50'
              }`}
            >
              <UploadCloud className="w-5 h-5" />
              Upload Data
            </button>
          </div>
        </div>
        
        {/* User and Logout Section */}
        <div className="pt-4 border-t border-gray-200">
          {user && (
            <p className="text-sm text-gray-700 mb-3 truncate">
              Signed in as: <span className="font-medium">{user.name || user.username}</span>
            </p>
          )}
          <button
            onClick={handleLogout}
            className="w-full flex items-center gap-3 p-3 rounded-lg text-red-600 hover:bg-red-50 transition font-medium"
          >
            <LogOut className="w-5 h-5" />
            Logout
          </button>
        </div>
      </nav>

      {/* Main Content Area */}
      <main className="flex-1 p-8 overflow-y-auto">
        <header className="mb-8 border-b pb-4">
          <h2 className="text-3xl font-semibold text-gray-800">
            {currentView === 'dashboards' ? 'Superset Dashboards' : 'Upload New Data'}
          </h2>
          <p className="text-gray-500 mt-1">
            {currentView === 'dashboards' ? 'Visualizations of your data, embedded directly from Superset.' : 'Submit Excel files to update your data source.'}
          </p>
        </header>

        <div className="max-w-7xl mx-auto">
          {currentView === 'dashboards' && (
            <>
              {dashboardsLoading && (
                <div className="text-center py-12">
                  <Loader2 className="w-8 h-8 text-blue-500 animate-spin mx-auto" />
                  <p className="mt-3 text-gray-600">Loading dashboards...</p>
                </div>
              )}

              {error && (
                <div className="p-4 bg-red-50 rounded-xl mb-6 shadow-sm">
                  <h3 className="text-red-800 font-semibold">Error Loading Dashboards</h3>
                  <p className="text-red-600 mt-2">{error}</p>
                  <button
                    onClick={fetchDashboards}
                    className="mt-3 px-4 py-2 bg-red-600 text-white rounded-lg hover:bg-red-700 transition text-sm"
                  >
                    Retry
                  </button>
                </div>
              )}

              {!dashboardsLoading && !error && dashboards.length === 0 && (
                <div className="text-center py-12 bg-white rounded-xl shadow-md">
                  <h2 className="text-2xl text-gray-600">No dashboards available</h2>
                  <p className="text-gray-500 mt-2">
                    You don't have access to any dashboards yet.
                  </p>
                </div>
              )}

              {dashboards.map((dash) => (
                <div key={dash.id} className="mb-8">
                  <SupersetChart 
                    dashboardId={dash.id} 
                    chartTitle={dash.title} 
                  />
                </div>
              ))}
            </>
          )}

          {currentView === 'upload' && (
            // Pass the navigate function down to the UploadExcel component
            <UploadExcel navigate={navigate} />
          )}

        </div>
      </main>
    </div>
  );
}

export default App;