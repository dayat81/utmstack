-- Create multi-tenant foundation tables
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create tenant management table
CREATE TABLE utm_tenant (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    subdomain VARCHAR(100) NOT NULL UNIQUE,
    status VARCHAR(50) NOT NULL DEFAULT 'active',
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    settings JSONB DEFAULT '{}',
    resource_limits JSONB DEFAULT '{}',
    tier VARCHAR(50) NOT NULL DEFAULT 'standard',
    cpu_threshold DECIMAL(5,2) NOT NULL DEFAULT 80.0,
    memory_threshold DECIMAL(5,2) NOT NULL DEFAULT 80.0,
    error_rate_threshold DECIMAL(5,2) NOT NULL DEFAULT 5.0
);

-- Create tenant configuration table
CREATE TABLE utm_tenant_config (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL,
    config_key VARCHAR(255) NOT NULL,
    config_value TEXT,
    config_type VARCHAR(50) NOT NULL DEFAULT 'STRING',
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- Create tenant role table for RBAC
CREATE TABLE utm_tenant_role (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL,
    role_name VARCHAR(100) NOT NULL,
    permissions JSONB DEFAULT '[]',
    parent_role_id UUID,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- Add foreign key constraints
ALTER TABLE utm_tenant_config 
ADD CONSTRAINT fk_tenant_config_tenant_id 
FOREIGN KEY (tenant_id) REFERENCES utm_tenant(id) ON DELETE CASCADE;

ALTER TABLE utm_tenant_role 
ADD CONSTRAINT fk_tenant_role_tenant_id 
FOREIGN KEY (tenant_id) REFERENCES utm_tenant(id) ON DELETE CASCADE;

ALTER TABLE utm_tenant_role 
ADD CONSTRAINT fk_tenant_role_parent_id 
FOREIGN KEY (parent_role_id) REFERENCES utm_tenant_role(id) ON DELETE SET NULL;

-- Create indexes for performance
CREATE INDEX idx_utm_tenant_subdomain ON utm_tenant(subdomain);
CREATE INDEX idx_utm_tenant_status ON utm_tenant(status);
CREATE INDEX idx_utm_tenant_config_tenant_key ON utm_tenant_config(tenant_id, config_key);
CREATE INDEX idx_utm_tenant_role_tenant ON utm_tenant_role(tenant_id);

-- Create unique constraints
ALTER TABLE utm_tenant_config 
ADD CONSTRAINT uk_tenant_config_key UNIQUE (tenant_id, config_key);

ALTER TABLE utm_tenant_role 
ADD CONSTRAINT uk_tenant_role_name UNIQUE (tenant_id, role_name);

-- Insert default tenant
INSERT INTO utm_tenant (
    name, 
    subdomain, 
    status, 
    tier,
    settings,
    resource_limits
) VALUES (
    'Default Organization',
    'default',
    'active',
    'standard',
    '{"timezone": "UTC", "dateFormat": "yyyy-MM-dd", "theme": "light"}',
    '{"maxUsers": 100, "maxStorage": "10GB", "maxElasticsearchIndices": 50}'
);

-- Get the tenant ID for further operations
DO $$
DECLARE
    tenant_uuid UUID;
BEGIN
    SELECT id INTO tenant_uuid FROM utm_tenant WHERE subdomain = 'default';
    
    -- Insert default tenant configuration
    INSERT INTO utm_tenant_config (tenant_id, config_key, config_value, config_type) VALUES
    (tenant_uuid, 'max_users', '100', 'INTEGER'),
    (tenant_uuid, 'max_storage_gb', '10', 'INTEGER'),
    (tenant_uuid, 'elasticsearch_retention_days', '30', 'INTEGER'),
    (tenant_uuid, 'log_level', 'INFO', 'STRING'),
    (tenant_uuid, 'enable_monitoring', 'true', 'BOOLEAN'),
    (tenant_uuid, 'enable_alerting', 'true', 'BOOLEAN');
    
    -- Insert default tenant roles
    INSERT INTO utm_tenant_role (tenant_id, role_name, permissions) VALUES
    (tenant_uuid, 'TENANT_ADMIN', '["READ", "WRITE", "DELETE", "ADMIN", "USER_MANAGEMENT", "SYSTEM_CONFIG"]'),
    (tenant_uuid, 'TENANT_USER', '["READ", "WRITE"]'),
    (tenant_uuid, 'TENANT_VIEWER', '["READ"]');
    
    RAISE NOTICE 'Default tenant created with ID: %', tenant_uuid;
END $$;
