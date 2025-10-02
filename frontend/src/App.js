import React from "react";
import SupersetChart from "./SupersetChart";

function App() {
  return (
    <div className="App">
      <h1>Superset Chart Viewer</h1>
      {/* Pass chartId from Superset */}
      <SupersetChart dashboardId={"91446e54-c273-4c4d-82dc-71c002f66eea"} chartTitle="Countrylang"/>
    </div>
  );
}

export default App;
