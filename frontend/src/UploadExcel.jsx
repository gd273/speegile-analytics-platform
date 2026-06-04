import React, { useState, useRef, useEffect } from "react";
import api from "./api";
import {
  UploadCloud,
  Database,
  Home,
  XCircle,
  CheckCircle,
  Loader2,
  FileText,
} from "lucide-react";

const UploadExcel = ({ navigate }) => {

  // ── File selection state ──────────────────────────────
  const [file, setFile]           = useState(null);
  const [isDragging, setIsDragging] = useState(false);

  // ── Upload button state ───────────────────────────────
  const isSubmitting              = useRef(false); // prevents duplicate submissions
  const [loading, setLoading]     = useState(false);
  const [isSuccess, setIsSuccess] = useState(false);

  // ── Inline message (success / error below form) ───────
  const [message, setMessage]     = useState(null);

  // ── Background processing popup state ─────────────────
  // loadId   → returned immediately from /api/upload-excel (202 response)
  // popupStatus → updated every 3s by polling /api/upload-status/<loadId>
  // const [loadId, setLoadId]           = useState(null);
  // const [popupStatus, setPopup]       = useState(null);
  const intervalRef                   = useRef(null); // holds setInterval ref for cleanup


        // ── Listen for upload completion from UploadProgressPopup ────
      // Updates the inline alert when background processing finishes
      useEffect(() => {
          const handleComplete = (e) => {
              const { status, message } = e.detail;

              if (status === "Fail") {
                  // Show error in inline alert — replaces the success message
                  setMessage({ type: "error", text: message });
                  setIsSuccess(false);
              } else if (status === "Pass") {
                  // Update inline alert to final success message
                  setMessage({ type: "success", text: "Data uploaded successfully! Please refresh your dashboard." });
              }
          };

          window.addEventListener("upload_complete", handleComplete);
          return () => window.removeEventListener("upload_complete", handleComplete);
      }, []);

  // ─────────────────────────────────────────────────────
  //  FILE SELECTION HANDLERS
  // ─────────────────────────────────────────────────────

  const handleFileChange = (e) => {
    const selectedFile = e.target.files[0];
    const isValid =
      selectedFile.type.includes("spreadsheetml.sheet") ||
      selectedFile.type.includes("csv") ||
      selectedFile.name.endsWith(".csv");

    if (selectedFile && isValid) {
      setFile(selectedFile);
      setMessage(null);
    } else {
      setFile(null);
      setMessage({ type: "error", text: "Please select a valid Excel or CSV file." });
    }
  };


  // ─────────────────────────────────────────────────────
  //  DRAG AND DROP HANDLERS
  // ─────────────────────────────────────────────────────

  const handleDragOver = (e) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragging(true);
  };

  const handleDragEnter = (e) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragging(true);
  };

  const handleDragLeave = (e) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragging(false);
  };

  const handleDrop = (e) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragging(false);

    const droppedFile = e.dataTransfer.files[0];
    const isValid =
      droppedFile.type.includes("spreadsheetml.sheet") ||
      droppedFile.type.includes("csv") ||
      droppedFile.name.endsWith(".csv");

    if (droppedFile && isValid) {
      setFile(droppedFile);
      setMessage(null);
    } else {
      setFile(null);
      setMessage({ type: "error", text: "Please drop a valid Excel or CSV file." });
    }
  };


  // ─────────────────────────────────────────────────────
  //  UPLOAD HANDLER
  //  1. Sends file to /api/upload-excel
  //  2. Server responds immediately with load_id (202)
  //  3. Starts polling for background processing status
  // ─────────────────────────────────────────────────────

  const handleUpload = async (e) => {
    e.preventDefault();
    if (!file || isSubmitting.current) return;

    isSubmitting.current = true;
    setLoading(true);
    setMessage(null);
    setIsSuccess(false);

    const formData = new FormData();
    formData.append("excel_file", file);

    try {
      const response = await api.post("/upload-excel", formData, {
        withCredentials: true,
        headers: { "Content-Type": "multipart/form-data" },
      });

      if (response.data.success) {
        // File received by server — background thread has started
        setMessage({ type: "success", text: response.data.message });
        setIsSuccess(true);
        setFile(null);

        // Store load_id and show the progress popup
        // setLoadId(response.data.load_id);
        // setPopup({
        //   status:  "Queued",
        //   percent: 5,
        //   message: "File received, starting processing...",
        //   load_id: response.data.load_id,
        // });

        // Begin polling for background thread status
        startPolling(response.data.load_id);

      } else {
        setMessage({
          type: "error",
          text: response.data.message || "File upload failed.",
        });
        setIsSuccess(false);
      }

    } catch (err) {
      console.error("Upload error:", err);
      const errorText =
        err.response?.data?.error || "An unexpected error occurred during upload.";
      setMessage({ type: "error", text: errorText });
      setIsSuccess(false);

    } finally {
      setLoading(false);
      isSubmitting.current = false;
    }
  };


  // ─────────────────────────────────────────────────────
  //  POLLING — checks /api/upload-status/<loadId> every 3s
  //  Updates popup with current status from load_master:
  //    Queued (5%) → Processing (40%) → Pass (100%) / Fail (0%)
  //  Stops automatically when status is Pass or Fail
  // ─────────────────────────────────────────────────────

  // const startPolling = (id) => {
  //   // Clear any existing poll before starting a new one
  //   if (intervalRef.current) {
  //     clearInterval(intervalRef.current);
  //   }

  //   intervalRef.current = setInterval(async () => {
  //     try {
  //       const res = await api.get(`/upload-status/${id}`);
  //       setPopup(res.data);

  //       // Stop polling once processing is complete
  //       if (res.data.status === "Pass" || res.data.status === "Fail") {
  //         clearInterval(intervalRef.current);
  //         intervalRef.current = null;
  //       }

  //     } catch (err) {
  //       console.error("Polling error:", err);
  //     }
  //   }, 3000);
  // };

  const startPolling = (loadId) => {
  // Fire a custom event — UploadProgressPopup listens for this
  // and handles all polling + display independently
  window.dispatchEvent(
    new CustomEvent("upload_started", { detail: { loadId } })
  );
};


  // ─────────────────────────────────────────────────────
  //  RENDER
  // ─────────────────────────────────────────────────────

  return (
    <div className="min-h-screen bg-gray-50 flex items-center justify-center p-4">
      <div className="w-full max-w-lg bg-white p-8 rounded-2xl shadow-2xl border border-indigo-100">

        <h2 className="text-3xl font-extrabold text-indigo-700 text-center mb-6">
          Upload Data
        </h2>
        <p className="text-center text-gray-500 mb-8">
          Upload a new <strong>Excel file (.xlsx)</strong> to process and
          refresh the data used for visualizations.
        </p>

        {/* ── Inline success / error message ── */}
        {message && (
          <div
            className={`flex items-center p-4 mb-6 rounded-xl ${
              message.type === "success"
                ? "bg-green-100 text-green-700 border border-green-300"
                : "bg-red-100 text-red-700 border border-red-300"
            } shadow-md`}
            role="alert"
          >
            {message.type === "success" ? (
              <CheckCircle className="w-5 h-5 mr-3" />
            ) : (
              <XCircle className="w-5 h-5 mr-3" />
            )}
            <span className="font-medium">{message.text}</span>
          </div>
        )}

        <form onSubmit={handleUpload} className="space-y-8">

          {/* ── Drag and drop / file select zone ── */}
          <div
            onDragOver={handleDragOver}
            onDragEnter={handleDragEnter}
            onDragLeave={handleDragLeave}
            onDrop={handleDrop}
            className={`border-2 border-dashed rounded-xl transition duration-300 ease-in-out ${
              isDragging
                ? "border-indigo-600 bg-indigo-100 scale-[1.02]"
                : "border-indigo-300 bg-indigo-50 hover:border-indigo-500"
            }`}
          >
            <input
              type="file"
              id="file-upload"
              accept=".xlsx, .csv, application/vnd.openxmlformats-officedocument.spreadsheetml.sheet, text/csv"
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
                  <FileText className="w-12 h-12 text-indigo-600 mb-3" />
                  <p className="font-semibold text-gray-800">
                    File selected:{" "}
                    <span className="text-indigo-600 font-bold break-all">
                      {file.name}
                    </span>
                  </p>
                  <p className="text-sm text-gray-500 mt-1">
                    Click to select a different file.
                  </p>
                </>
              ) : (
                <>
                  <UploadCloud
                    className={`w-14 h-14 mb-3 transition ${
                      isDragging ? "text-indigo-600" : "text-indigo-400"
                    }`}
                  />
                  <p className="text-lg font-medium text-gray-700">
                    {isDragging ? (
                      <span className="text-indigo-600 font-semibold">
                        Drop your file here!
                      </span>
                    ) : (
                      <>
                        Drag and drop or{" "}
                        <span className="text-indigo-600 font-semibold hover:text-indigo-700 transition">
                          Browse
                        </span>
                      </>
                    )}
                  </p>
                  <p className="text-sm text-gray-500 mt-1">
                    Max file size 50MB (.xlsx or .csv)
                  </p>
                </>
              )}
            </label>
          </div>

          {/* ── Upload submit button ── */}
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
        
        {/* ── Navigate to dashboards after successful upload ── */}
        {isSuccess && (
          <div className="mt-8 pt-6 border-t border-gray-100">
            <button
              onClick={() => navigate("dashboards")}
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