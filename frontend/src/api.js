import axios from 'axios';

const api = axios.create({
  withCredentials: true,
  baseURL: `${process.env.REACT_APP_API_BASE_URL}/api`,
  headers: {
    'Content-Type': 'application/json'
  }
});

export default api;
