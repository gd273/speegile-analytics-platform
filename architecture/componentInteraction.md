```mermaid
graph LR

    %% ===============================
    %% Frontend
    %% ===============================
    subgraph "Frontend (React + Nginx)"
        LOGIN[Login Page]
        DASH[Dashboard Page]
        UPLOAD[Upload Page]
        SDK[Superset Embedded SDK]
    end

    %% ===============================
    %% Backend
    %% ===============================
    subgraph "Backend (Flask API)"
        AUTH[Authentication Middleware]
        LOGIN_EP[/login endpoint]
        DASH_EP[/dashboards endpoint]
        TOKEN_EP[/guest-token endpoint]
        UPLOAD_EP[/upload-excel endpoint]
    end

    %% ===============================
    %% Superset
    %% ===============================
    subgraph "Superset"
        API[REST API]
        EMBED[Embedded Dashboard Renderer]
        QUERY[Query Engine]
    end

    %% ===============================
    %% Auth Flow
    %% ===============================
    LOGIN --> LOGIN_EP
    LOGIN_EP --> AUTH

    %% ===============================
    %% Dashboard Flow
    %% ===============================
    DASH --> DASH_EP
    DASH_EP --> API

    DASH --> TOKEN_EP
    TOKEN_EP --> SDK

    %% ===============================
    %% Embed Flow
    %% ===============================
    SDK --> EMBED
    EMBED --> API
    EMBED --> QUERY

    %% ===============================
    %% Upload Flow
    %% ===============================
    UPLOAD --> UPLOAD_EP
    UPLOAD_EP -.-> S3[(S3)]
    UPLOAD_EP -.-> DB[(client-analytics-db)]

    QUERY -.-> DB

    %% ===============================
    %% Styling
    %% ===============================
    style LOGIN fill:#60A5FA
    style DASH fill:#34D399
    style UPLOAD fill:#FBBF24
    style SDK fill:#F87171

    style AUTH fill:#FB923C
    style LOGIN_EP fill:#A78BFA
    style DASH_EP fill:#A78BFA
    style TOKEN_EP fill:#A78BFA
    style UPLOAD_EP fill:#A78BFA

    style API fill:#EC4899
    style EMBED fill:#EC4899
    style QUERY fill:#EC4899
```
