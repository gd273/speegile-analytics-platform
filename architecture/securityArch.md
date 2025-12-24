graph TB
    subgraph "Security Layers"
        subgraph "Transport Security"
            HTTPS[HTTPS/TLS<br/>All connections encrypted]
        end
        
        subgraph "Authentication"
            SESSION[Flask Session-based Auth<br/>Redis storage<br/>HttpOnly cookies<br/>SameSite=None, Secure=True]
            GUEST_TOKEN[Superset Guest Tokens<br/>JWT with HS256<br/>5-minute expiry<br/>Shared secret validation]
        end
        
        subgraph "Authorization"
            RBAC[Role-Based Access Control<br/>Admin, Analyst, Viewer]
            TENANT_ISO[Tenant Isolation<br/>Separate PostgreSQL schemas<br/>No cross-tenant access]
        end
        
        subgraph "Data Protection"
            DB_ACCESS[Database Access Control<br/>Dedicated users per database<br/>Connection string encryption]
            S3_IAM[S3 IAM Policies<br/>Restricted bucket access<br/>Encryption at rest]
            AUDIT[Audit Logging<br/>load_master tracking<br/>load_errors logging]
        end
        
        subgraph "API Security"
            CORS[CORS Policy<br/>Explicit origin whitelist<br/>Credentials support]
            CSRF[CSRF Protection<br/>WTF_CSRF_ENABLED<br/>Token validation]
            RATE_LIMIT[Rate Limiting<br/>To be implemented]
        end
    end
    
    USER[User Request] --> HTTPS
    HTTPS --> SESSION
    SESSION --> RBAC
    RBAC --> TENANT_ISO
    
    TENANT_ISO --> DB_ACCESS
    TENANT_ISO --> S3_IAM
    
    SESSION --> GUEST_TOKEN
    GUEST_TOKEN --> CORS
    CORS --> CSRF
    
    DB_ACCESS --> AUDIT
    S3_IAM --> AUDIT
    
    style HTTPS fill:#60A5FA
    style SESSION fill:#34D399
    style GUEST_TOKEN fill:#FBBF24
    style RBAC fill:#F87171
    style TENANT_ISO fill:#FB923C
    style DB_ACCESS fill:#A78BFA
    style S3_IAM fill:#EC4899
    style AUDIT fill:#10B981
    style CORS fill:#8B5CF6
    style CSRF fill:#3B82F6
    style RATE_LIMIT fill:#EF4444,stroke:#DC2626,stroke-width:2px,stroke-dasharray: 5 5