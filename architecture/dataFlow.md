```mermaid
flowchart TD
    START([User Accesses Platform])
    
    START --> LOGIN{Authenticated?}
    LOGIN -->|No| AUTH[Login Flow:<br/>POST /login<br/>Validate credentials<br/>Create Redis session]
    AUTH --> LOGGED_IN
    LOGIN -->|Yes| LOGGED_IN[User Dashboard]
    
    LOGGED_IN --> ACTION{User Action}
    
    ACTION -->|View Dashboards| DASH_FLOW[Dashboard Flow:<br/>1. GET /dashboards<br/>2. Filter by roles<br/>3. GET /guest-token<br/>4. Embed with SDK]
    DASH_FLOW --> DISPLAY[Display Dashboard]
    
    ACTION -->|Upload Data| UPLOAD_FLOW[Upload Flow:<br/>1. POST /upload-excel<br/>2. Validate & Parse<br/>3. Archive to S3<br/>4. Save to tenant schema<br/>5. Update load_master]
    UPLOAD_FLOW --> SUCCESS{Success?}
    SUCCESS -->|Yes| DATA_READY[Data Available<br/>for Dashboards]
    SUCCESS -->|No| ERROR_LOG[Log to load_errors<br/>Show error to user]
    
    DATA_READY --> SUPERSET_QUERY[Superset queries<br/>tenant schema tables<br/>to render charts]
    SUPERSET_QUERY --> DISPLAY
    
    DISPLAY --> ACTION
    ERROR_LOG --> ACTION
    
    style START fill:#60A5FA
    style LOGIN fill:#34D399
    style AUTH fill:#FBBF24
    style LOGGED_IN fill:#F87171
    style ACTION fill:#FB923C
    style DASH_FLOW fill:#A78BFA
    style UPLOAD_FLOW fill:#EC4899
    style DISPLAY fill:#10B981
    style DATA_READY fill:#8B5CF6
    style ERROR_LOG fill:#EF4444
```mermaid