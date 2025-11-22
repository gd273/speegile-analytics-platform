
// import React, { useState } from "react";
// import api from "./api";
// import { User, Lock, ArrowRight, Loader2 } from "lucide-react";

// const Login = ({ onLoginSuccess }) => {
//   const [username, setUsername] = useState("");
//   const [password, setPassword] = useState("");
//   const [error, setError] = useState("");
//   const [loading, setLoading] = useState(false);

//   const handleSubmit = async (e) => {
//     e.preventDefault();
//     setError("");
//     setLoading(true);

//     try {
//       const response = await api.post('/login', { username, password });

//       if (response.data.success) {
//         setTimeout(() => {
//           onLoginSuccess(response.data.user);
//         }, 500);
//         return;
//       }
//     } catch (err) {
//       console.error("Login error:", err);
//       setError(
//         err.response?.data?.error || "Invalid credentials provided."
//       );
//       setLoading(false);
//     }
//   };

//   return (
//     // CHANGE 1: Removed "bg-slate-50" from this line so it is transparent
//     <div className="relative min-h-screen flex items-center justify-center overflow-hidden">
      
//       {/* CHANGE 2: Added "bg-slate-50" here so it blends with the grid */}
//       <div className="absolute inset-0 -z-10 h-full w-full bg-slate-50 bg-grid-pattern">
//           <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[500px] h-[500px] bg-indigo-100 rounded-full blur-[100px] opacity-50" />
//       </div>

//       <div className="relative w-full max-w-md p-8 bg-white rounded-2xl shadow-[0_20px_50px_rgba(8,_112,_184,_0.07)] border border-slate-100">
        
//         <div className="text-center mb-8">
//           <img 
//             src="/SpeegileLogo.jpeg" 
//             alt="Speegile Logo" 
//             className="h-20 w-auto mx-auto mb-6 object-contain rounded-lg shadow-sm"
//           />
          
//           <h2 className="text-2xl font-bold text-slate-900 tracking-tight">
//             Welcome back
//           </h2>
//           <p className="mt-2 text-sm text-slate-500">
//             Please enter your details to access the portal.
//           </p>
//         </div>

//         {error && (
//           <div className="mb-6 p-4 rounded-lg bg-red-50 border border-red-100 text-red-600 text-sm flex items-center gap-2 animate-in fade-in slide-in-from-top-2 duration-200">
//             <span className="w-1.5 h-1.5 rounded-full bg-red-500 shrink-0" />
//             {error}
//           </div>
//         )}

//         <form className="space-y-5" onSubmit={handleSubmit}>
//           <div className="space-y-1.5">
//             <label className="text-xs font-semibold text-slate-500 uppercase tracking-wider ml-1">
//               Username
//             </label>
//             <div className="relative group">
//               <User className="absolute left-4 top-3.5 h-5 w-5 text-slate-400 group-focus-within:text-indigo-500 transition-colors" />
//               <input
//                 type="text"
//                 value={username}
//                 onChange={(e) => setUsername(e.target.value)}
//                 className="w-full pl-11 pr-4 py-3 bg-slate-50 border border-slate-200 rounded-xl text-slate-900 placeholder-slate-400 focus:outline-none focus:bg-white focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-500 transition-all duration-200"
//                 placeholder="Enter your username"
//                 required
//                 disabled={loading}
//               />
//             </div>
//           </div>

//           <div className="space-y-1.5">
//             <label className="text-xs font-semibold text-slate-500 uppercase tracking-wider ml-1">
//               Password
//             </label>
//             <div className="relative group">
//               <Lock className="absolute left-4 top-3.5 h-5 w-5 text-slate-400 group-focus-within:text-indigo-500 transition-colors" />
//               <input
//                 type="password"
//                 value={password}
//                 onChange={(e) => setPassword(e.target.value)}
//                 className="w-full pl-11 pr-4 py-3 bg-slate-50 border border-slate-200 rounded-xl text-slate-900 placeholder-slate-400 focus:outline-none focus:bg-white focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-500 transition-all duration-200"
//                 placeholder="••••••••"
//                 required
//                 disabled={loading}
//               />
//             </div>
//           </div>

//           <button
//             type="submit"
//             disabled={loading}
//             className="w-full flex items-center justify-center gap-2 bg-indigo-600 hover:bg-indigo-700 text-white py-3 rounded-xl font-semibold transition-all duration-200 shadow-lg shadow-indigo-500/30 hover:shadow-indigo-500/40 disabled:opacity-70 disabled:cursor-not-allowed active:scale-[0.98] mt-2"
//           >
//             {loading ? (
//               <Loader2 className="h-5 w-5 animate-spin" />
//             ) : (
//               <>
//                 Sign In <ArrowRight className="h-4 w-4" />
//               </>
//             )}
//           </button>
//         </form>

//         <div className="mt-8 text-center border-t border-slate-100 pt-6">
//           <p className="text-xs text-slate-400">
//             Demo Credentials: 
//             <span className="mx-2 font-mono text-indigo-600 bg-indigo-50 px-1.5 py-0.5 rounded">bob</span> 
//             / 
//             <span className="ml-2 font-mono text-indigo-600 bg-indigo-50 px-1.5 py-0.5 rounded">password</span>
//           </p>
//         </div>
//       </div>
//     </div>
//   );
// };

// export default Login;


import React, { useState, useEffect } from "react";
import api from "./api";
import { User, Lock, ArrowRight, Loader2 } from "lucide-react";

const Login = ({ onLoginSuccess }) => {
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  // 1. State for tracking mouse position (The "Spotlight" effect)
  const [mousePosition, setMousePosition] = useState({ x: 0, y: 0 });

  // 2. Effect to update mouse position
  useEffect(() => {
    const handleMouseMove = (event) => {
      setMousePosition({ x: event.clientX, y: event.clientY });
    };

    window.addEventListener("mousemove", handleMouseMove);
    
    // Cleanup listener when component unmounts
    return () => {
      window.removeEventListener("mousemove", handleMouseMove);
    };
  }, []);

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError("");
    setLoading(true);

    try {
      const response = await api.post('/login', { username, password });

      if (response.data.success) {
        // Small delay to show the "success" state smoothly
        setTimeout(() => {
          onLoginSuccess(response.data.user);
        }, 500);
        return;
      }
    } catch (err) {
      console.error("Login error:", err);
      setError(
        err.response?.data?.error || "Invalid credentials provided."
      );
      setLoading(false);
    }
  };

  return (
    // MAIN CONTAINER
    <div className="relative min-h-screen flex items-center justify-center overflow-hidden bg-slate-50">
      
      {/* --- BACKGROUND LAYER START --- */}
      
      {/* 1. The Static Tech Grid (The dots) */}
      <div className="absolute inset-0 z-0 h-full w-full bg-slate-50 bg-[radial-gradient(#e5e7eb_1px,transparent_1px)] [background-size:16px_16px]" />
      
      {/* 2. The Interactive Spotlight (Follows Mouse) */}
      <div 
        className="absolute inset-0 z-0 pointer-events-none transition-opacity duration-300"
        style={{
          background: `radial-gradient(600px circle at ${mousePosition.x}px ${mousePosition.y}px, rgba(79, 70, 229, 0.10), transparent 40%)`
        }}
      />
      
      {/* --- BACKGROUND LAYER END --- */}


      {/* LOGIN CARD (Floating above background) */}
      <div className="relative z-10 w-full max-w-md p-8 bg-white rounded-2xl shadow-[0_20px_50px_rgba(8,_112,_184,_0.07)] border border-slate-100">
        
        {/* Header */}
        <div className="text-center mb-8">
          <img 
            src="/SpeegileLogo.jpeg" 
            alt="Speegile Logo" 
            className="h-20 w-auto mx-auto mb-6 object-contain rounded-lg shadow-sm"
          />
          
          <h2 className="text-2xl font-bold text-slate-900 tracking-tight">
            Welcome back
          </h2>
          <p className="mt-2 text-sm text-slate-500">
            Please enter your details to access the portal.
          </p>
        </div>

        {/* Error Message */}
        {error && (
          <div className="mb-6 p-4 rounded-lg bg-red-50 border border-red-100 text-red-600 text-sm flex items-center gap-2 animate-in fade-in slide-in-from-top-2 duration-200">
            <span className="w-1.5 h-1.5 rounded-full bg-red-500 shrink-0" />
            {error}
          </div>
        )}

        {/* Form */}
        <form className="space-y-5" onSubmit={handleSubmit}>
          
          {/* Username Field */}
          <div className="space-y-1.5">
            <label className="text-xs font-semibold text-slate-500 uppercase tracking-wider ml-1">
              Username
            </label>
            <div className="relative group">
              <User className="absolute left-4 top-3.5 h-5 w-5 text-slate-400 group-focus-within:text-indigo-500 transition-colors" />
              <input
                type="text"
                value={username}
                onChange={(e) => setUsername(e.target.value)}
                className="w-full pl-11 pr-4 py-3 bg-slate-50 border border-slate-200 rounded-xl text-slate-900 placeholder-slate-400 focus:outline-none focus:bg-white focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-500 transition-all duration-200"
                placeholder="Enter your username"
                required
                disabled={loading}
              />
            </div>
          </div>

          {/* Password Field */}
          <div className="space-y-1.5">
            <label className="text-xs font-semibold text-slate-500 uppercase tracking-wider ml-1">
              Password
            </label>
            <div className="relative group">
              <Lock className="absolute left-4 top-3.5 h-5 w-5 text-slate-400 group-focus-within:text-indigo-500 transition-colors" />
              <input
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                className="w-full pl-11 pr-4 py-3 bg-slate-50 border border-slate-200 rounded-xl text-slate-900 placeholder-slate-400 focus:outline-none focus:bg-white focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-500 transition-all duration-200"
                placeholder="••••••••"
                required
                disabled={loading}
              />
            </div>
          </div>

          {/* Submit Button */}
          <button
            type="submit"
            disabled={loading}
            className="w-full flex items-center justify-center gap-2 bg-indigo-600 hover:bg-indigo-700 text-white py-3 rounded-xl font-semibold transition-all duration-200 shadow-lg shadow-indigo-500/30 hover:shadow-indigo-500/40 disabled:opacity-70 disabled:cursor-not-allowed active:scale-[0.98] mt-2"
          >
            {loading ? (
              <Loader2 className="h-5 w-5 animate-spin" />
            ) : (
              <>
                Sign In <ArrowRight className="h-4 w-4" />
              </>
            )}
          </button>
        </form>

        {/* Footer */}
        <div className="mt-8 text-center border-t border-slate-100 pt-6">
          <p className="text-xs text-slate-400">
            Demo Credentials: 
            <span className="mx-2 font-mono text-indigo-600 bg-indigo-50 px-1.5 py-0.5 rounded">bob</span> 
            / 
            <span className="ml-2 font-mono text-indigo-600 bg-indigo-50 px-1.5 py-0.5 rounded">password</span>
          </p>
        </div>
      </div>
    </div>
  );
};

export default Login;