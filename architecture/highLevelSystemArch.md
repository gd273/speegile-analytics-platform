graph TB
    subgraph "Client Browser"
        USER[User]
        BROWSER[React Frontend<br/>Port 80]
    end
    
    subgraph "Render Services - Oregon Region"
        subgraph "Web Services"
            FRONTEND[Frontend Service<br/>Nginx + React<br/>Starter Plan]
            BACKEND[Backend Service<br/>Flask API<br/>Port 5000<br/>Starter Plan]
            SUPERSET[Superset Service<br/>Analytics Engine<br/>Port 8088<br/>Starter Plan]
        end
        
        subgraph "Data Layer"
            REDIS[(Redis<br/>Session & Cache<br/>Free Plan)]
            CLIENT_DB[(client-analytics-db<br/>PostgreSQL 18<br/>256MB)]
            SUPERSET_DB[(superset-metastore-db<br/>PostgreSQL 18<br/>256MB)]
        end
    end
    
    subgraph "AWS"
        S3[S3 Bucket<br/>client-analytics-data-storage<br/>Excel Archive]
    end
    
    USER -->|HTTPS| BROWSER
    BROWSER -->|API Calls| FRONTEND
    FRONTEND -->|REST API| BACKEND
    FRONTEND -->|Embedded Dashboards| SUPERSET
    
    BACKEND -->|Auth & CRUD| CLIENT_DB
    BACKEND -->|Guest Token Gen| SUPERSET
    BACKEND -->|Session Storage| REDIS
    BACKEND -->|File Archive| S3
    
    SUPERSET -->|Metadata| SUPERSET_DB
    SUPERSET -->|Query Data| CLIENT_DB
    SUPERSET -->|Query Cache| REDIS
    
    style USER fill:#60A5FA
    style FRONTEND fill:#34D399
    style BACKEND fill:#FBBF24
    style SUPERSET fill:#F87171
    style REDIS fill:#FB923C
    style CLIENT_DB fill:#A78BFA
    style SUPERSET_DB fill:#A78BFA
    style S3 fill:#EC4899