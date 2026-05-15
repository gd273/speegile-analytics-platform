import axios from 'axios';
// const API_BASE = "https://backend-zr5v.onrender.com/api";
const API_BASE = "http://localhost:5000/api";
const api = axios.create({
  withCredentials: true,
  baseURL: API_BASE,
  timeout: 600000,
  headers: {
    'Content-Type': 'application/json'
  }
});

// Optional: helpful interceptor to debug issues
api.interceptors.response.use(
  (response) => response,
  (error) => {
    console.error("API ERROR:", {
      url: error?.config?.url,
      method: error?.config?.method,
      message: error?.message,
      response: error?.response?.data
    });
    return Promise.reject(error);
  }
);

export default api;
