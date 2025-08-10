-- Create test tenants for multi-tenant verification
-- Tenant 1: ACME Corporation
INSERT INTO utm_tenant (
    name, 
    subdomain, 
    status, 
    tier,
    settings,
    resource_limits,
    cpu_threshold,
    memory_threshold,
    error_rate_threshold
) VALUES (
    'ACME Corporation',
    'acme',
    'active',
    'premium',
    '{"timezone": "America/New_York", "dateFormat": "MM/dd/yyyy", "theme": "dark", "company": "ACME Corporation", "industry": "Technology"}',
    '{"maxUsers": 500, "maxStorage": "100GB", "maxElasticsearchIndices": 200, "maxDashboards": 100}',
    75.0,
    85.0,
    3.0
);

-- Tenant 2: Global Security Inc
INSERT INTO utm_tenant (
    name, 
    subdomain, 
    status, 
    tier,
    settings,
    resource_limits,
    cpu_threshold,
    memory_threshold,
    error_rate_threshold
) VALUES (
    'Global Security Inc',
    'globalsec',
    'active',
    'enterprise',
    '{"timezone": "Europe/London", "dateFormat": "dd/MM/yyyy", "theme": "light", "company": "Global Security Inc", "industry": "Security Services"}',
    '{"maxUsers": 1000, "maxStorage": "500GB", "maxElasticsearchIndices": 500, "maxDashboards": 200}',
    70.0,
    80.0,
    2.0
);

-- Get tenant IDs for configuration setup
DO $$
DECLARE
    acme_tenant_id UUID;
    globalsec_tenant_id UUID;
BEGIN
    -- Get tenant IDs
    SELECT id INTO acme_tenant_id FROM utm_tenant WHERE subdomain = 'acme';
    SELECT id INTO globalsec_tenant_id FROM utm_tenant WHERE subdomain = 'globalsec';
    
    -- Insert configuration for ACME Corporation
    INSERT INTO utm_tenant_config (tenant_id, config_key, config_value, config_type) VALUES
    (acme_tenant_id, 'max_users', '500', 'INTEGER'),
    (acme_tenant_id, 'max_storage_gb', '100', 'INTEGER'),
    (acme_tenant_id, 'elasticsearch_retention_days', '90', 'INTEGER'),
    (acme_tenant_id, 'log_level', 'DEBUG', 'STRING'),
    (acme_tenant_id, 'enable_monitoring', 'true', 'BOOLEAN'),
    (acme_tenant_id, 'enable_alerting', 'true', 'BOOLEAN'),
    (acme_tenant_id, 'alert_email', 'security@acme.corp', 'STRING'),
    (acme_tenant_id, 'siem_mode', 'advanced', 'STRING');
    
    -- Insert configuration for Global Security Inc
    INSERT INTO utm_tenant_config (tenant_id, config_key, config_value, config_type) VALUES
    (globalsec_tenant_id, 'max_users', '1000', 'INTEGER'),
    (globalsec_tenant_id, 'max_storage_gb', '500', 'INTEGER'),
    (globalsec_tenant_id, 'elasticsearch_retention_days', '365', 'INTEGER'),
    (globalsec_tenant_id, 'log_level', 'INFO', 'STRING'),
    (globalsec_tenant_id, 'enable_monitoring', 'true', 'BOOLEAN'),
    (globalsec_tenant_id, 'enable_alerting', 'true', 'BOOLEAN'),
    (globalsec_tenant_id, 'alert_email', 'ops@globalsecurity.com', 'STRING'),
    (globalsec_tenant_id, 'siem_mode', 'enterprise', 'STRING');
    
    -- Insert roles for ACME Corporation
    INSERT INTO utm_tenant_role (tenant_id, role_name, permissions) VALUES
    (acme_tenant_id, 'TENANT_ADMIN', '["READ", "WRITE", "DELETE", "ADMIN", "USER_MANAGEMENT", "SYSTEM_CONFIG", "ALERT_MANAGEMENT"]'),
    (acme_tenant_id, 'SECURITY_ANALYST', '["READ", "WRITE", "ALERT_MANAGEMENT", "INCIDENT_RESPONSE"]'),
    (acme_tenant_id, 'TENANT_USER', '["READ", "WRITE"]'),
    (acme_tenant_id, 'TENANT_VIEWER', '["READ"]');
    
    -- Insert roles for Global Security Inc
    INSERT INTO utm_tenant_role (tenant_id, role_name, permissions) VALUES
    (globalsec_tenant_id, 'TENANT_ADMIN', '["READ", "WRITE", "DELETE", "ADMIN", "USER_MANAGEMENT", "SYSTEM_CONFIG", "ALERT_MANAGEMENT", "COMPLIANCE_MANAGEMENT"]'),
    (globalsec_tenant_id, 'SOC_MANAGER', '["READ", "WRITE", "ALERT_MANAGEMENT", "INCIDENT_RESPONSE", "TEAM_MANAGEMENT"]'),
    (globalsec_tenant_id, 'SECURITY_ANALYST', '["READ", "WRITE", "ALERT_MANAGEMENT", "INCIDENT_RESPONSE"]'),
    (globalsec_tenant_id, 'TENANT_USER', '["READ", "WRITE"]'),
    (globalsec_tenant_id, 'TENANT_VIEWER', '["READ"]');
    
    RAISE NOTICE 'Test tenants created:';
    RAISE NOTICE 'ACME Corporation ID: %', acme_tenant_id;
    RAISE NOTICE 'Global Security Inc ID: %', globalsec_tenant_id;
END $$;
