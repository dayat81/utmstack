-- UTMStack Multi-Tenant Database Initialization Script
-- This script sets up the core multi-tenant schema

-- Create the main tenant table
CREATE TABLE IF NOT EXISTS utm_tenant (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    subdomain VARCHAR(100) UNIQUE NOT NULL,
    status VARCHAR(50) DEFAULT 'active',
    tier VARCHAR(50) DEFAULT 'standard',
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    settings JSONB DEFAULT '{}',
    resource_limits JSONB DEFAULT '{}',
    cpu_threshold DECIMAL DEFAULT 80.0,
    memory_threshold DECIMAL DEFAULT 85.0,
    error_rate_threshold DECIMAL DEFAULT 5.0
);

-- Create tenant configuration table
CREATE TABLE IF NOT EXISTS utm_tenant_config (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES utm_tenant(id) ON DELETE CASCADE,
    config_key VARCHAR(255) NOT NULL,
    config_value TEXT,
    config_type VARCHAR(50) DEFAULT 'string',
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(tenant_id, config_key)
);

-- Create tenant role table for RBAC
CREATE TABLE IF NOT EXISTS utm_tenant_role (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES utm_tenant(id) ON DELETE CASCADE,
    role_name VARCHAR(100) NOT NULL,
    permissions JSONB DEFAULT '[]',
    parent_role_id UUID REFERENCES utm_tenant_role(id),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(tenant_id, role_name)
);

-- Create user table with tenant support
CREATE TABLE IF NOT EXISTS jhi_user (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES utm_tenant(id),
    login VARCHAR(50) NOT NULL,
    password_hash VARCHAR(60) NOT NULL,
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    email VARCHAR(254),
    image_url VARCHAR(256),
    activated BOOLEAN DEFAULT false,
    lang_key VARCHAR(10),
    activation_key VARCHAR(20),
    reset_key VARCHAR(20),
    created_by VARCHAR(50) DEFAULT 'system',
    created_date TIMESTAMP DEFAULT NOW(),
    reset_date TIMESTAMP DEFAULT NULL,
    last_modified_by VARCHAR(50),
    last_modified_date TIMESTAMP DEFAULT NOW()
);

-- Create unique constraints for tenant-scoped users
CREATE UNIQUE INDEX IF NOT EXISTS jhi_user_email_tenant_idx ON jhi_user(email, tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS jhi_user_login_tenant_idx ON jhi_user(login, tenant_id);

-- Create other core multi-tenant tables
CREATE TABLE IF NOT EXISTS utm_dashboard (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES utm_tenant(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    config JSONB DEFAULT '{}',
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS utm_alert_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES utm_tenant(id) ON DELETE CASCADE,
    alert_name VARCHAR(255),
    alert_level VARCHAR(50),
    source_ip INET,
    dest_ip INET,
    alert_data JSONB DEFAULT '{}',
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS utm_index_pattern (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES utm_tenant(id) ON DELETE CASCADE,
    pattern VARCHAR(255) NOT NULL,
    pattern_type VARCHAR(50),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Create function to get current tenant ID from session variable
CREATE OR REPLACE FUNCTION get_current_tenant_id()
RETURNS UUID AS $$
BEGIN
    RETURN NULLIF(current_setting('app.current_tenant_id', true), '')::UUID;
EXCEPTION
    WHEN OTHERS THEN RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create function to set tenant context
CREATE OR REPLACE FUNCTION set_tenant_context(tenant_uuid UUID)
RETURNS void AS $$
BEGIN
    PERFORM set_config('app.current_tenant_id', tenant_uuid::TEXT, TRUE);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Enable Row-Level Security (RLS) on all tenant tables
ALTER TABLE jhi_user ENABLE ROW LEVEL SECURITY;
ALTER TABLE utm_dashboard ENABLE ROW LEVEL SECURITY;
ALTER TABLE utm_alert_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE utm_index_pattern ENABLE ROW LEVEL SECURITY;
ALTER TABLE utm_tenant_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE utm_tenant_role ENABLE ROW LEVEL SECURITY;

-- Create RLS policies for tenant isolation
CREATE POLICY IF NOT EXISTS tenant_isolation_policy ON jhi_user
    USING (tenant_id = get_current_tenant_id() OR get_current_tenant_id() IS NULL);

CREATE POLICY IF NOT EXISTS tenant_isolation_policy ON utm_dashboard
    USING (tenant_id = get_current_tenant_id() OR get_current_tenant_id() IS NULL);

CREATE POLICY IF NOT EXISTS tenant_isolation_policy ON utm_alert_log
    USING (tenant_id = get_current_tenant_id() OR get_current_tenant_id() IS NULL);

CREATE POLICY IF NOT EXISTS tenant_isolation_policy ON utm_index_pattern
    USING (tenant_id = get_current_tenant_id() OR get_current_tenant_id() IS NULL);

CREATE POLICY IF NOT EXISTS tenant_isolation_policy ON utm_tenant_config
    USING (tenant_id = get_current_tenant_id() OR get_current_tenant_id() IS NULL);

CREATE POLICY IF NOT EXISTS tenant_isolation_policy ON utm_tenant_role
    USING (tenant_id = get_current_tenant_id() OR get_current_tenant_id() IS NULL);

-- Create default tenant for existing single-tenant data
INSERT INTO utm_tenant (
    id, 
    name, 
    subdomain, 
    status, 
    tier, 
    settings, 
    resource_limits
) VALUES (
    '00000000-0000-0000-0000-000000000001',
    'Default Tenant',
    'default',
    'active',
    'enterprise',
    '{"theme": "dark", "timezone": "UTC"}',
    '{"max_users": 1000, "max_dashboards": 100, "storage_gb": 1000}'
) ON CONFLICT (subdomain) DO NOTHING;

-- Create demo tenant for testing
INSERT INTO utm_tenant (
    id,
    name,
    subdomain,
    status,
    tier,
    settings,
    resource_limits
) VALUES (
    '00000000-0000-0000-0000-000000000002',
    'Demo Tenant',
    'demo',
    'active',
    'standard',
    '{"theme": "light", "timezone": "UTC"}',
    '{"max_users": 50, "max_dashboards": 10, "storage_gb": 100}'
) ON CONFLICT (subdomain) DO NOTHING;

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_utm_tenant_config_tenant ON utm_tenant_config(tenant_id);
CREATE INDEX IF NOT EXISTS idx_utm_tenant_role_tenant ON utm_tenant_role(tenant_id);
CREATE INDEX IF NOT EXISTS idx_jhi_user_tenant ON jhi_user(tenant_id);
CREATE INDEX IF NOT EXISTS idx_utm_dashboard_tenant ON utm_dashboard(tenant_id);
CREATE INDEX IF NOT EXISTS idx_utm_alert_log_tenant ON utm_alert_log(tenant_id);
CREATE INDEX IF NOT EXISTS idx_utm_index_pattern_tenant ON utm_index_pattern(tenant_id);

-- Create default admin user for each tenant
-- Default tenant admin
INSERT INTO jhi_user (
    id,
    tenant_id,
    login,
    password_hash,
    first_name,
    last_name,
    email,
    activated,
    lang_key
) VALUES (
    gen_random_uuid(),
    '00000000-0000-0000-0000-000000000001',
    'admin',
    '$2a$10$gSAhZrxMllrbgj/kkK9UceBPpChGWJA7SYIb1Mqo.n5aNLq1/oRrC', -- secret
    'Administrator',
    'Default',
    'admin@default.utmstack.com',
    true,
    'en'
) ON CONFLICT (login, tenant_id) DO NOTHING;

-- Demo tenant admin
INSERT INTO jhi_user (
    id,
    tenant_id,
    login,
    password_hash,
    first_name,
    last_name,
    email,
    activated,
    lang_key
) VALUES (
    gen_random_uuid(),
    '00000000-0000-0000-0000-000000000002',
    'admin',
    '$2a$10$gSAhZrxMllrbgj/kkK9UceBPpChGWJA7SYIb1Mqo.n5aNLq1/oRrC', -- secret
    'Administrator',
    'Demo',
    'admin@demo.utmstack.com',
    true,
    'en'
) ON CONFLICT (login, tenant_id) DO NOTHING;

-- Grant permissions
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO utmstack_prod;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO utmstack_prod;

-- Show created tenants
SELECT id, name, subdomain, status, tier, created_at FROM utm_tenant;
