graph LR
    subgraph "Frontend (React + Nginx)"
        LOGIN[Login Page]
        DASH[Dashboard Page]
        UPLOAD[Upload Page]
        SDK[Superset Embedded SDK]
    end
    
    subgraph "Backend (Flask API)"
        AUTH[Authentication<br/>Middleware]
        LOGIN_EP[/login endpoint]
        DASH_EP[/dashboards endpoint]
        TOKEN_EP[/guest-token endpoint]
        UPLOAD_EP[/upload-excel endpoint]
    end
    
    subgraph "Superset"
        API[REST API]
        EMBED[Embedded Dashboard<br/>Renderer]
        QUERY[Query Engine]
    end
    
    LOGIN -->|POST credentials| LOGIN_EP
    LOGIN_EP -->|Create session| AUTH
    
    DASH -->|GET dashboards| DASH_EP
    DASH_EP -->|Fetch dashboards| API
    
    DASH -->|Request token| TOKEN_EP
    TOKEN_EP -->|Generate JWT| SDK
    
    SDK -->|Embed with token| EMBED
    EMBED -->|Validate token| API
    EMBED -->|Execute SQL| QUERY
    
    UPLOAD -->|POST Excel| UPLOAD_EP
    UPLOAD_EP -.->|Archive| S3[(S3)]
    UPLOAD_EP -.->|Save data| DB[(client-analytics-db)]
    
    QUERY -.->|Query tenant data| DB
    
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