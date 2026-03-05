import React, { useState } from "react";
import api from "./api"; // Now correctly points to the new api.js
import { UploadCloud, Database, Home, XCircle, CheckCircle, Loader2, FileText } from "lucide-react";

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
      // Use axios directly with full config
      const response = await api.post("/upload-excel", formData, {
        withCredentials: true,  // Explicitly set
        headers: {
          'Content-Type': 'multipart/form-data',
        }
      });

      if (response.data.success) {
        setMessage({ type: 'success', text: response.data.message });
        setIsSuccess(true);
        setFile(null);
        // document.getElementById('excel-file-input').value = null;
      } else {
        setMessage({ type: 'error', text: response.data.message || 'File upload failed.' });
        setIsSuccess(false);
      }
    } catch (err) {
      console.error("Upload error:", err);
      console.error("Response:", err.response);  // Add this to see full error
      const errorText = err.response?.data?.error || "An unexpected error occurred during upload.";
      setMessage({ type: 'error', text: errorText });
      setIsSuccess(false);
    } finally {
      setLoading(false);
    }
};

const testSession = async () => {
  try {
    const response = await api.get('/check-auth');
    console.log('Session test result:', response.data);
    alert(`Session active: ${response.data.authenticated}, User: ${response.data.user?.username}`);
  } catch (err) {
    console.error('Session test failed:', err);
    alert('Session test failed - see console');
  }
};

return (
    <div className="min-h-screen bg-gray-50 flex items-center justify-center p-4">
      <div className="w-full max-w-lg bg-white p-8 rounded-2xl shadow-2xl border border-indigo-100">
        <h2 className="text-3xl font-extrabold text-indigo-700 text-center mb-6">
          Upload Data
        </h2>
        <p className="text-center text-gray-500 mb-8">
          Upload a new **Excel file (.xlsx)** to process and refresh the data used for visualizations.
        </p>

        {/* Message Banner */}
        {message && (
          <div
            className={`flex items-center p-4 mb-6 rounded-xl ${
              message.type === 'success'
                ? 'bg-green-100 text-green-700 border border-green-300'
                : 'bg-red-100 text-red-700 border border-red-300'
            } shadow-md`}
            role="alert"
          >
            {message.type === 'success' ? (
              <CheckCircle className="w-5 h-5 mr-3" />
            ) : (
              <XCircle className="w-5 h-5 mr-3" />
            )}
            <span className="font-medium">{message.text}</span>
          </div>
        )}

        <form onSubmit={handleUpload} className="space-y-6">
          {/* File Selection Area (Drag and Drop style) */}
          <div className="border-2 border-dashed border-indigo-300 rounded-xl p-8 transition duration-300 ease-in-out hover:border-indigo-500 bg-indigo-50">
            <input
              type="file"
              id="file-upload"
              // Corrected accept attribute to ensure proper file type
              accept="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet, .xlsx" 
              className="hidden"
              onChange={handleFileChange}
              disabled={loading}
            />
            <label
              htmlFor="file-upload"
              className="cursor-pointer flex flex-col items-center justify-center text-center p-2"
            >
              {file ? (
                <>
                  <FileText className="w-10 h-10 text-indigo-600 mb-2" />
                  <p className="font-semibold text-gray-800">
                    File selected: <span className="text-indigo-600 font-bold break-all">{file.name}</span>
                  </p>
                  <p className="text-sm text-gray-500 mt-1">
                    Click to select a different file.
                  </p>
                </>
              ) : (
                <>
                  <UploadCloud className="w-12 h-12 text-indigo-400 mb-3" />
                  <p className="text-lg font-medium text-gray-700">
                    Drag and drop or <span className="text-indigo-600 font-semibold hover:text-indigo-700 transition">Browse</span>
                  </p>
                  <p className="text-sm text-gray-500 mt-1">
                    Max file size 5MB (only .xlsx)
                  </p>
                </>
              )}
            </label>
          </div>

          <button
            type="submit"
            disabled={loading || !file}
            className="w-full flex items-center justify-center gap-2 px-4 py-3 border border-transparent text-lg font-medium rounded-lg text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 transition duration-150 ease-in-out disabled:bg-gray-400 disabled:cursor-not-allowed shadow-xl hover:shadow-2xl transform hover:scale-[1.005] active:scale-[0.99]"
          >
            {loading ? (
              <>
                <Loader2 className="w-5 h-5 animate-spin" />
                Processing Data...
              </>
            ) : (
              <>
                <Database className="w-5 h-5" />
                Upload and Save to Database
              </>
            )}
          </button>
        </form>

        {/* Return Home Button */}
        {isSuccess && (
          <div className="mt-8 pt-6 border-t border-gray-100">
            <button
              onClick={() => navigate('dashboards')}
              className="w-full flex items-center justify-center gap-2 px-4 py-3 text-lg font-medium rounded-lg text-indigo-600 bg-indigo-50 hover:bg-indigo-100 transition duration-150 ease-in-out focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
            >
              <Home className="w-5 h-5" />
              Go to Dashboards
            </button>
          </div>
        )}
      </div>
    </div>
  );
};

export default UploadExcel;
