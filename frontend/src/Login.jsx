import React, { useState } from "react";
import api from "./api";
import { User, Lock, LogIn } from "lucide-react";

const Login = ({ onLoginSuccess }) => {
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError("");
    setLoading(true);
    let response;
    try {
      const response = await api.post('/login', { username, password });

      if (response.data.success) {
        console.log("Login successful:", response.data.user);
        setTimeout(() => {
          onLoginSuccess(response.data.user);
        }, 200);
        // onLoginSuccess(response.data.user);
                setLoading(false);
        return;
      }
    } catch (err) {
      console.error("Login error:", err);
      setError(
        err.response?.data?.error || "Login failed. Please try again."
      );
    } finally {
    //   setLoading(false);
    if (!response || !response.data.success) {
          setLoading(false);
      }
    }
  };

//   return (
//     <div className="min-h-screen flex items-center justify-center bg-gray-100"> {/* Use a softer background */}
//     <div className="bg-white p-10 rounded-2xl shadow-xl w-full max-w-sm border border-gray-200"> {/* Softer shadow and border */}
//         <div className="text-center mb-8">
//             <a href="/" className="flex items-center justify-center text-3xl font-extrabold text-blue-700 gap-2 mb-4">
//                 <img
//                     src="/Speegilelogo.jpeg"
//                     alt="Speegile logo"
//                     className="h-16 w-16 md:h-20 md:w-20 lg:h-24 lg:w-24 object-contain rounded-full"
//                 />
//             </a>
//             <h1 className="text-2xl font-bold text-gray-800 mb-1">
//                 Sign in to Dashboard
//             </h1>
//             <p className="text-gray-500 text-sm">Enter your credentials below</p>
//         </div>

//         <form onSubmit={handleSubmit} className="space-y-5"> {/* Adjusted spacing */}
//             {/* ... Error Block (kept the same) ... */}

//             <div>
//                 <label
//                     htmlFor="username"
//                     className="block text-sm font-medium text-gray-700 mb-2"
//                 >
//                     Username
//                 </label>
//                 <div className="relative">
//                     <User className="absolute left-3 top-1/2 transform -translate-y-1/2 h-5 w-5 text-gray-400" />
//                     <input
//                         id="username"
//                         type="text"
//                         value={username}
//                         onChange={(e) => setUsername(e.target.value)}
//                         // Added padding-left for the icon
//                         className="w-full pl-10 pr-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none transition" 
//                         placeholder="e.g., bob"
//                         required
//                         disabled={loading}
//                     />
//                 </div>
//             </div>

//             <div>
//                 <label
//                     htmlFor="password"
//                     className="block text-sm font-medium text-gray-700 mb-2"
//                 >
//                     Password
//                 </label>
//                 <div className="relative">
//                     <Lock className="absolute left-3 top-1/2 transform -translate-y-1/2 h-5 w-5 text-gray-400" />
//                     <input
//                         id="password"
//                         type="password"
//                         value={password}
//                         onChange={(e) => setPassword(e.target.value)}
//                         // Added padding-left for the icon
//                         className="w-full pl-10 pr-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none transition"
//                         placeholder="Enter your password"
//                         required
//                         disabled={loading}
//                     />
//                 </div>
//             </div>

//             <button
//                 type="submit"
//                 disabled={loading}
//                 className="w-full flex items-center justify-center gap-2 bg-blue-600 text-white py-3 rounded-lg font-semibold hover:bg-blue-700 transition disabled:bg-gray-400 disabled:cursor-not-allowed shadow-md hover:shadow-lg"
//             >
//                 {loading ? "Signing in..." : <><LogIn className="h-5 w-5"/> Sign In</>}
//             </button>
//         </form>

//         <div className="mt-6 text-center border-t pt-4">
//             <p className="text-sm text-gray-500">
//                 Demo credentials: <code className="font-mono text-gray-700 bg-gray-100 px-2 py-0.5 rounded">bob / bob123</code>
//             </p>
//         </div>
//     </div>
// </div>
//   );
  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-100"> {/* Use a softer background */}
    <div className="bg-white p-10 rounded-2xl shadow-xl w-full max-w-sm border border-gray-200"> {/* Softer shadow and border */}
        <div className="text-center mb-8">
            <h2 className="text-3xl font-extrabold text-gray-900">Sign in to your account</h2>
            <p className="mt-2 text-sm text-gray-500">
                Data Application Portal
            </p>
        </div>

        {error && (
            <div className="mb-4 p-3 bg-red-100 border border-red-400 text-red-700 rounded-lg text-sm" role="alert">
                {error}
            </div>
        )}

        <form className="space-y-6" onSubmit={handleSubmit}>
            <div>
                <label htmlFor="username" className="block text-sm font-medium text-gray-700 mb-2">
                    Username
                </label>
                <div className="relative">
                    <User className="absolute left-3 top-1/2 transform -translate-y-1/2 h-5 w-5 text-gray-400" />
                    <input
                        id="username"
                        type="text"
                        value={username}
                        onChange={(e) => setUsername(e.target.value)}
                        // Added padding-left for the icon
                        className="w-full pl-10 pr-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none transition"
                        placeholder="Enter your username"
                        required
                        disabled={loading}
                    />
                </div>
            </div>

            <div>
                <label htmlFor="password" className="block text-sm font-medium text-gray-700 mb-2">
                    Password
                </label>
                <div className="relative">
                    <Lock className="absolute left-3 top-1/2 transform -translate-y-1/2 h-5 w-5 text-gray-400" />
                    <input
                        id="password"
                        type="password"
                        value={password}
                        onChange={(e) => setPassword(e.target.value)}
                        // Added padding-left for the icon
                        className="w-full pl-10 pr-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none transition"
                        placeholder="Enter your password"
                        required
                        disabled={loading}
                    />
                </div>
            </div>

            <button
                type="submit"
                disabled={loading}
                className="w-full flex items-center justify-center gap-2 bg-blue-600 text-white py-3 rounded-lg font-semibold hover:bg-blue-700 transition disabled:bg-gray-400 disabled:cursor-not-allowed shadow-md hover:shadow-lg"
            >
                {loading ? "Signing in..." : <><LogIn className="h-5 w-5"/> Sign In</>}
            </button>
        </form>

        <div className="mt-6 text-center border-t pt-4">
            <p className="text-sm text-gray-500">
                Demo credentials: <code className="font-mono text-gray-700 bg-gray-100 px-2 py-0.5 rounded">bob</code> / <code className="font-mono text-gray-700 bg-gray-100 px-2 py-0.5 rounded">password</code>
            </p>
        </div>
    </div>
    </div>
  );
};

export default Login;