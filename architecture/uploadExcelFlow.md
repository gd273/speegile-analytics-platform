sequenceDiagram
    participant U as User
    participant F as Frontend
    participant B as Backend API
    participant DB as client-analytics-db
    participant S3 as AWS S3
    
    U->>F: 1. Select Excel file<br/>Click Upload
    F->>B: 2. POST /upload-excel<br/>multipart/form-data<br/>(with session cookie)
    
    B->>B: 3. Verify session<br/>Get tenant context<br/>(tenant_id, tenant_schema)
    
    B->>DB: 4. BEGIN TRANSACTION<br/>INSERT INTO load_master<br/>(tenant_id, user_id, filename)<br/>VALUES (1, 1, 'sales.xlsx')<br/>RETURNING id
    DB-->>B: 5. load_id = 42
    
    B->>B: 6. Parse Excel with Pandas<br/>pd.ExcelFile(file)
    
    alt Validation Errors Found
        B->>DB: 7a. INSERT INTO load_errors<br/>(load_id, row_number, error_msg)
        B->>DB: 8a. UPDATE load_master<br/>SET status='Fail'<br/>WHERE id=42
        DB-->>B: COMMIT
        B-->>F: 9a. 400 Bad Request<br/>{error: "Validation failed"}
        F-->>U: Show error details
    else Validation Success
        B->>B: 7b. Generate S3 key:<br/>"tenant_green_energy/<br/>1_42_20251224_143022.xlsx"
        
        B->>S3: 8b. upload_fileobj()<br/>Bucket: client-analytics-data-storage<br/>Key: tenant_schema/filename
        S3-->>B: 9b. Upload successful
        
        loop For each sheet in Excel
            B->>B: 10. Clean column names<br/>Add load_id column<br/>Generate table name
            B->>DB: 11. df.to_sql(<br/>  table_name,<br/>  schema=tenant_schema,<br/>  if_exists='replace'<br/>)
        end
        
        B->>DB: 12. UPDATE load_master<br/>SET status='Pass'<br/>WHERE id=42
        DB-->>B: COMMIT
        
        B-->>F: 13. 200 OK<br/>{success: true, load_id: 42,<br/>message: "Processed & Archived"}
        F-->>U: Show success message
    end
    
    Note over DB: New tables now available<br/>in tenant_green_energy schema:<br/>- sales_data (load_id=42)<br/>- inventory_q1 (load_id=42)
    
    Note over S3: Archived file:<br/>tenant_green_energy/<br/>1_42_20251224_143022.xlsx
    
    rect rgb(200, 220, 255)
        Note over U,S3: Superset can now query<br/>the new data for dashboards
    end