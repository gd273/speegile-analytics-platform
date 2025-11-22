import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import api from './api'; // Your existing api.js

const CreateUser = () => {
  const navigate = useNavigate();
  const [message, setMessage] = useState(null);
  const [formData, setFormData] = useState({
    username: '',          // Login Username
    password: '',          // Login Password
    name: '',              // Display Name
    superset_username: '', // Superset User to Map to
    roles: ''              // Comma separated string
  });

  const handleSubmit = async (e) => {
    e.preventDefault();
    try {
      // Convert comma-string "A, B" to array ["A", "B"]
      const rolesArray = formData.roles.split(',').map(r => r.trim()).filter(r => r);

      const payload = {
        ...formData,
        roles: rolesArray
      };

      // Send to your Backend
      const response = await api.post('/admin/create-user', payload);
      
      alert("Success: " + response.data.message);
      navigate('/dashboards'); // Go back to dashboard after success
      
    } catch (err) {
      const errorMsg = err.response?.data?.error || 'Failed to create user';
      setMessage({ type: 'error', text: errorMsg });
    }
  };

  return (
    <div className="flex flex-col items-center justify-center min-h-screen bg-gray-100">
      <div className="p-8 bg-white rounded shadow-md w-96">
        <h2 className="text-2xl font-bold mb-6 text-center">Create New User</h2>
        
        {message && (
          <div className="bg-red-100 text-red-700 p-2 mb-4 rounded">
            {message.text}
          </div>
        )}

        <form onSubmit={handleSubmit} className="space-y-4">
          <input 
            className="w-full p-2 border rounded" 
            placeholder="Login Username (e.g. User_3)"
            value={formData.username}
            onChange={e => setFormData({...formData, username: e.target.value})}
            required
          />
          <input 
            className="w-full p-2 border rounded" 
            type="password"
            placeholder="Login Password"
            value={formData.password}
            onChange={e => setFormData({...formData, password: e.target.value})}
            required
          />
          <input 
            className="w-full p-2 border rounded" 
            placeholder="Display Name (e.g. Bob Client)"
            value={formData.name}
            onChange={e => setFormData({...formData, name: e.target.value})}
            required
          />
          <input 
            className="w-full p-2 border rounded" 
            placeholder="Superset Username (e.g. User_3)"
            value={formData.superset_username}
            onChange={e => setFormData({...formData, superset_username: e.target.value})}
            required
          />
          <input 
            className="w-full p-2 border rounded" 
            placeholder="Roles (e.g. DASHBOARD-READ-BASE)"
            value={formData.roles}
            onChange={e => setFormData({...formData, roles: e.target.value})}
            required
          />
          
          <button type="submit" className="w-full bg-blue-600 text-white p-2 rounded hover:bg-blue-700 font-bold">
            Create User
          </button>
        </form>
        
        <button onClick={() => navigate('/dashboards')} className="mt-4 w-full text-gray-500 text-sm">
          Cancel
        </button>
      </div>
    </div>
  );
};

export default CreateUser;