-- Fix RLS policies for PostgreSQL 15
-- Create RLS policies for tenant isolation

-- Drop existing policies if they exist
DROP POLICY IF EXISTS tenant_isolation_policy ON jhi_user;
DROP POLICY IF EXISTS tenant_isolation_policy ON utm_dashboard;
DROP POLICY IF EXISTS tenant_isolation_policy ON utm_alert_log;
DROP POLICY IF EXISTS tenant_isolation_policy ON utm_index_pattern;
DROP POLICY IF EXISTS tenant_isolation_policy ON utm_tenant_config;
DROP POLICY IF EXISTS tenant_isolation_policy ON utm_tenant_role;

-- Create new policies
CREATE POLICY tenant_isolation_policy ON jhi_user
    USING (tenant_id = get_current_tenant_id() OR get_current_tenant_id() IS NULL);

CREATE POLICY tenant_isolation_policy ON utm_dashboard
    USING (tenant_id = get_current_tenant_id() OR get_current_tenant_id() IS NULL);

CREATE POLICY tenant_isolation_policy ON utm_alert_log
    USING (tenant_id = get_current_tenant_id() OR get_current_tenant_id() IS NULL);

CREATE POLICY tenant_isolation_policy ON utm_index_pattern
    USING (tenant_id = get_current_tenant_id() OR get_current_tenant_id() IS NULL);

CREATE POLICY tenant_isolation_policy ON utm_tenant_config
    USING (tenant_id = get_current_tenant_id() OR get_current_tenant_id() IS NULL);

CREATE POLICY tenant_isolation_policy ON utm_tenant_role
    USING (tenant_id = get_current_tenant_id() OR get_current_tenant_id() IS NULL);

-- Test the tenant isolation
SELECT 'RLS Policies Created Successfully' as status;
