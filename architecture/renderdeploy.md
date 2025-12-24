graph TB
    subgraph "GitHub Repository"
        REPO[speegile-analytics-platform<br/>Main Branch]
    end
    
    subgraph "Render - Oregon Region"
        subgraph "Auto-Deploy Triggers"
            FRONTEND_TRIGGER[Frontend Service<br/>✓ Auto-deploy on commit]
            BACKEND_TRIGGER[Backend Service<br/>✓ Auto-deploy on commit]
            SUPERSET_TRIGGER[Superset Service<br/>✓ Auto-deploy on commit]
        end
        
        subgraph "Running Services"
            FRONTEND_SVC[frontend<br/>Docker: Node 18 + Nginx<br/>Port: 80<br/>Plan: Starter]
            BACKEND_SVC[backend<br/>Docker: Python 3.11<br/>Port: 5000<br/>Plan: Starter<br/>Workers: 3]
            SUPERSET_SVC[superset<br/>Docker: apache/superset:latest<br/>Port: 8088<br/>Plan: Starter<br/>Workers: 1]
        end
        
        subgraph "Managed Databases"
            CLIENT_DB[(client-analytics-db<br/>PostgreSQL 18<br/>Plan: Basic 256MB<br/>Disk: 15GB<br/>IP: 0.0.0.0/0)]
            SUPERSET_DB[(superset-metastore-db<br/>PostgreSQL 18<br/>Plan: Basic 256MB<br/>Disk: 15GB<br/>IP: 0.0.0.0/0)]
        end
        
        subgraph "Cache"
            REDIS_SVC[(redis<br/>KeyValue Store<br/>Plan: Free<br/>Policy: allkeys-lru)]
        end
    end
    
    subgraph "External Services"
        S3[AWS S3<br/>client-analytics-data-storage<br/>Region: us-east-1]
    end
    
    REPO -->|Git Push| FRONTEND_TRIGGER
    REPO -->|Git Push| BACKEND_TRIGGER
    REPO -->|Git Push| SUPERSET_TRIGGER
    
    FRONTEND_TRIGGER -->|Build & Deploy| FRONTEND_SVC
    BACKEND_TRIGGER -->|Build & Deploy| BACKEND_SVC
    SUPERSET_TRIGGER -->|Build & Deploy| SUPERSET_SVC
    
    BACKEND_SVC -->|SQLAlchemy| CLIENT_DB
    BACKEND_SVC -->|Flask-Session| REDIS_SVC
    BACKEND_SVC -->|boto3| S3
    
    SUPERSET_SVC -->|SQLAlchemy| SUPERSET_DB
    SUPERSET_SVC -->|Query Data| CLIENT_DB
    SUPERSET_SVC -->|Cache| REDIS_SVC
    
    FRONTEND_SVC -->|API Calls| BACKEND_SVC
    FRONTEND_SVC -->|Embed Dashboards| SUPERSET_SVC
    
    style REPO fill:#60A5FA
    style FRONTEND_TRIGGER fill:#34D399
    style BACKEND_TRIGGER fill:#34D399
    style SUPERSET_TRIGGER fill:#34D399
    style FRONTEND_SVC fill:#10B981
    style BACKEND_SVC fill:#F59E0B
    style SUPERSET_SVC fill:#EF4444
    style CLIENT_DB fill:#8B5CF6
    style SUPERSET_DB fill:#8B5CF6
    style REDIS_SVC fill:#EC4899
    style S3 fill:#3B82F6