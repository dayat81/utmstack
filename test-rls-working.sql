-- Test RLS in a single session
BEGIN;

-- Set tenant context and test in same transaction
SELECT set_tenant_context('00000000-0000-0000-0000-000000000001'::UUID);
SELECT 'Current tenant:', current_setting('app.current_tenant_id', true);
SELECT 'Function result:', get_current_tenant_id();

-- This should only show default tenant data
SELECT 'DEFAULT TENANT ONLY - DASHBOARDS:' as test;
SELECT tenant_id, name FROM utm_dashboard WHERE tenant_id = get_current_tenant_id();

COMMIT;

BEGIN;
-- Set to demo tenant
SELECT set_tenant_context('00000000-0000-0000-0000-000000000002'::UUID);
SELECT 'Current tenant:', current_setting('app.current_tenant_id', true);
SELECT 'Function result:', get_current_tenant_id();

-- This should only show demo tenant data
SELECT 'DEMO TENANT ONLY - DASHBOARDS:' as test;
SELECT tenant_id, name FROM utm_dashboard WHERE tenant_id = get_current_tenant_id();

COMMIT;
