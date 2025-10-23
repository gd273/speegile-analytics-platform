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

  // State to manage the current view: 'dashboards' or 'upload'
  const [currentView, setCurrentView] = useState('dashboards'); 

  useEffect(() => {
    checkAuth();
  }, []);

  const checkAuth = async () => {
    try {
      const response = await api.get('/check-auth');

      if (response.data.authenticated) {
        setIsAuthenticated(true);
        setUser(response.data.user);
        // Fetch dashboards after authentication is confirmed
        await fetchDashboards();
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
    setIsAuthenticated(true);
    setUser(userData);
    // Fetch dashboards after successful login
    await fetchDashboards();
  };

  const handleLogout = async () => {
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
    }
  };

    // Function to switch between views, passed to UploadExcel
  const navigate = async (view) => {
    setCurrentView(view);
    if (view === 'dashboards') {
      // Re-fetch dashboards in case the new data affects them (optional)
      await fetchDashboards(); 
    }
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center h-screen bg-gray-100">
        <div className="text-xl text-gray-600">Loading...</div>
      </div>
    );
  }

  if (!isAuthenticated) {
    return <Login onLoginSuccess={handleLoginSuccess} />;
  }

  // return (
  //   <div className="flex flex-col h-screen">
  //     <header className="fixed top-0 left-0 w-full bg-white shadow z-50">
  //          <div className="py-4 px-6 flex items-center justify-between max-w-screen-2xl mx-auto"> 
  //       <a href="/" className="flex items-center gap-3 text-3xl font-extrabold text-blue-700 hover:text-blue-800 transition">
  //           <img
  //               src="/SpeegileLogo.jpeg"
  //               alt="Speegile logo"
  //               className="h-16 w-16 md:h-20 md:w-20 lg:h-24 lg:w-24 object-contain rounded-full" // Increased size and added rounded-full
  //           />
  //           <span className="hidden sm:inline">Embedded Analytics</span> {/* Only show on medium screens and up */}
  //       </a>
        
  //       <div className="flex items-center gap-4">
  //           <span className="text-gray-600 text-sm">
  //               User: 
  //               <span className="font-semibold text-gray-800 ml-1">{user?.name || user?.username}</span>
  //           </span>
  //           {user?.roles && (
  //               <span className="hidden md:inline text-xs bg-blue-100 text-blue-700 py-1 px-3 rounded-full font-medium border border-blue-200">
  //                   Roles: {user.roles.join(", ")}
  //               </span>
  //           )}
  //           <button
  //               onClick={handleLogout}
  //               className="px-4 py-2 bg-red-600 text-white rounded-lg font-medium hover:bg-red-700 transition shadow-md hover:shadow-lg"
  //           >
  //               Logout
  //           </button>
  //       </div>
  //   </div>
  //     </header>

  //     <main className="flex-1 overflow-y-auto px-4 pb-8 pt-24">
  //       <div className="max-w-screen-2xl mx-auto">
  //         {dashboardsLoading && (
  //           <div className="flex items-center justify-center py-12">
  //             <div className="text-xl text-gray-600">Loading dashboards...</div>
  //           </div>
  //         )}

  //         {error && (
  //           <div className="bg-red-50 border border-red-200 rounded p-4 mb-6">
  //             <h3 className="text-red-800 font-semibold">Error Loading Dashboards</h3>
  //             <p className="text-red-600 mt-2">{error}</p>
  //             <button
  //               onClick={fetchDashboards}
  //               className="mt-3 px-4 py-2 bg-red-600 text-white rounded hover:bg-red-700"
  //             >
  //               Retry
  //             </button>
  //           </div>
  //         )}

  //         {!dashboardsLoading && !error && dashboards.length === 0 && (
  //           <div className="text-center py-12">
  //             <h2 className="text-2xl text-gray-600">No dashboards available</h2>
  //             <p className="text-gray-500 mt-2">
  //               You don't have access to any dashboards yet.
  //             </p>
  //           </div>
  //         )}

  //         {dashboards.map((dash) => (
  //           <div key={dash.id} className="my-4 min-h-[1000px]">
  //             <SupersetChart dashboardId={dash.id} chartTitle={dash.title} />
  //           </div>
  //         ))}
  //       </div>
  //     </main>
  //   </div>
  // );
  return (
    <div className="flex flex-col min-h-screen bg-gray-50">
      {/* Header/Nav with dynamic button and user info */}
      <header className="fixed top-0 left-0 right-0 z-50 bg-white shadow-lg p-4 flex justify-between items-center border-b border-gray-100">
        <h1 className="text-2xl font-bold text-indigo-700 flex items-center">
            <Home className="w-6 h-6 mr-2" />
            Analytics Platform
        </h1>
        <div className="flex items-center space-x-4">
          <span className="text-sm font-medium text-gray-600">Welcome, {user?.name || 'User'}!</span>
            
          {/* Dynamic Navigation Button */}
          {currentView === 'dashboards' ? (
            <button
              onClick={() => navigate('upload')}
              className="px-4 py-2 bg-green-600 text-white rounded-lg font-medium hover:bg-green-700 transition flex items-center gap-1"
            >
              <UploadCloud className="w-4 h-4" />
              Upload Data
            </button>
          ) : (
            <button
              onClick={() => navigate('dashboards')}
              className="px-4 py-2 bg-indigo-600 text-white rounded-lg font-medium hover:bg-indigo-700 transition flex items-center gap-1"
            >
              <Home className="w-4 h-4" />
              Return to Dashboard
            </button>
          )}

          <button
            onClick={handleLogout}
            className="px-4 py-2 border border-gray-300 text-gray-700 rounded-lg font-medium hover:bg-gray-100 transition flex items-center gap-1"
          >
            <LogOut className="w-4 h-4" />
            Logout
          </button>
        </div>
      </header>

      <main className="flex-1 overflow-y-auto px-4 pb-8 pt-24">
        <div className="max-w-screen-2xl mx-auto">
          
          {/* Conditional Rendering based on currentView */}
          {currentView === 'dashboards' && (
            <>
              {dashboardsLoading && (
                <div className="flex items-center justify-center py-12">
                  <Loader2 className="w-6 h-6 text-indigo-600 animate-spin mr-3" />
                  <div className="text-xl text-gray-600">Loading dashboards...</div>
                </div>
              )}

              {error && (
                <div className="bg-red-50 border border-red-200 rounded-xl p-4 mb-6 shadow-sm">
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