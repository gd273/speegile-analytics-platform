import React, { useState } from "react";
import api from "./api"; // Now correctly points to the new api.js
import { UploadCloud, Database, Home, XCircle, CheckCircle, Loader2 } from "lucide-react";

const UploadExcel = ({ navigate }) => {
  const [file, setFile] = useState(null);
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState(null);
  const [isSuccess, setIsSuccess] = useState(false);

  const handleFileChange = (e) => {
    const selectedFile = e.target.files[0];
    if (selectedFile && selectedFile.type.includes("spreadsheetml.sheet")) {
      setFile(selectedFile);
      setMessage(null);
    } else {
      setFile(null);
      setMessage({ type: 'error', text: 'Please select a valid Excel file (.xlsx).' });
    }
  };

  const handleUpload = async (e) => {
    e.preventDefault();
    if (!file) {
      setMessage({ type: 'error', text: 'No file selected for upload.' });
      return;
    }

    setLoading(true);
    setMessage(null);
    setIsSuccess(false);

    const formData = new FormData();
    formData.append("excel_file", file);

    try {
      // Use the configured API instance
      const response = await api.post("/upload-excel", formData, {
        headers: {
          "Content-Type": "multipart/form-data",
        },
      });

      if (response.data.success) {
        setMessage({ type: 'success', text: response.data.message });
        setIsSuccess(true);
        // Clear the file input after successful upload
        setFile(null);
        document.getElementById('excel-file-input').value = null;
      } else {
        setMessage({ type: 'error', text: response.data.message || 'File upload failed.' });
        setIsSuccess(false);
        // console.log("Error while uploading");
      }
    } catch (err) {
      console.error("Upload error:", err);
      const errorText = err.response?.data?.error || "An unexpected error occurred during upload.";
      setMessage({ type: 'error', text: errorText });
      setIsSuccess(false);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="max-w-xl mx-auto mt-10 p-8 bg-white rounded-2xl shadow-2xl border border-gray-100">
      <h2 className="text-3xl font-extrabold text-gray-800 flex items-center mb-6 border-b pb-4">
        <UploadCloud className="w-7 h-7 mr-3 text-indigo-600" />
        Upload Data to MySQL
      </h2>

      {/* Status Message */}
      {message && (
        <div className={`p-4 mb-6 rounded-xl border-l-4 ${message.type === 'success' ? 'bg-green-50 border-green-500 text-green-700' : 'bg-red-50 border-red-500 text-red-700'}`}>
          <div className="flex items-center">
            {message.type === 'success' ? <CheckCircle className="w-5 h-5 mr-3" /> : <XCircle className="w-5 h-5 mr-3" />}
            <span className="font-medium">{message.text}</span>
          </div>
        </div>
      )}

      {/* Upload Form */}
      <form onSubmit={handleUpload} className="space-y-6">
        <div>
          <label htmlFor="excel-file-input" className="block text-sm font-medium text-gray-700 mb-2">
            Select Excel File (.xlsx)
          </label>
          <div className="flex items-center justify-center w-full">
            <label 
              htmlFor="excel-file-input" 
              className="flex flex-col items-center justify-center w-full h-32 border-2 border-dashed rounded-lg cursor-pointer bg-gray-50 hover:bg-gray-100 transition-colors"
            >
              <div className="flex flex-col items-center justify-center pt-5 pb-6">
                <Database className="w-8 h-8 mb-3 text-gray-400" />
                <p className="mb-2 text-sm text-gray-500">
                  <span className="font-semibold">Click to upload</span> or drag and drop
                </p>
                <p className="text-xs text-gray-500">
                  {file ? `Selected: ${file.name}` : "Only .xlsx files are supported"}
                </p>
              </div>
              <input 
                id="excel-file-input" 
                type="file" 
                accept=".xlsx"
                className="hidden" 
                onChange={handleFileChange} 
                disabled={loading}
              />
            </label>
          </div>
        </div>

        <button
          type="submit"
          disabled={loading || !file}
          className="w-full flex items-center justify-center gap-2 px-4 py-3 border border-transparent text-lg font-medium rounded-lg text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 transition duration-150 ease-in-out disabled:bg-gray-400"
        >
          {loading ? (
            <>
              <Loader2 className="w-5 h-5 animate-spin" />
              Processing Data...
            </>
          ) : (
            <>
              <UploadCloud className="w-5 h-5" />
              Upload and Save to Database
            </>
          )}
        </button>
      </form>

      {/* Return Home Button */}
      {isSuccess && (
        <div className="mt-8 pt-6 border-t">
          <button
            onClick={() => navigate('dashboards')}
            className="w-full flex items-center justify-center gap-2 px-4 py-3 text-lg font-medium rounded-lg text-indigo-600 bg-indigo-50 hover:bg-indigo-100 transition duration-150 ease-in-out border border-indigo-200"
          >
            <Home className="w-5 h-5" />
            Return to Dashboard
          </button>
        </div>
      )}
    </div>
  );
};

export default UploadExcel;
