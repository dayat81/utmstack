-- Test tenant isolation
-- Set context to default tenant and create some data
SELECT set_tenant_context('00000000-0000-0000-0000-000000000001'::UUID);

INSERT INTO utm_dashboard (tenant_id, name, description) VALUES 
('00000000-0000-0000-0000-000000000001', 'Default Dashboard 1', 'Security Overview for Default Tenant'),
('00000000-0000-0000-0000-000000000001', 'Default Dashboard 2', 'Incident Response for Default Tenant');

INSERT INTO utm_alert_log (tenant_id, alert_name, alert_level, source_ip) VALUES
('00000000-0000-0000-0000-000000000001', 'Brute Force Attack', 'HIGH', '192.168.1.100'),
('00000000-0000-0000-0000-000000000001', 'Suspicious Login', 'MEDIUM', '10.0.0.50');

-- Switch to demo tenant and create different data
SELECT set_tenant_context('00000000-0000-0000-0000-000000000002'::UUID);

INSERT INTO utm_dashboard (tenant_id, name, description) VALUES 
('00000000-0000-0000-0000-000000000002', 'Demo Dashboard 1', 'Test Dashboard for Demo Tenant'),
('00000000-0000-0000-0000-000000000002', 'Demo Dashboard 2', 'Analytics Dashboard for Demo Tenant');

INSERT INTO utm_alert_log (tenant_id, alert_name, alert_level, source_ip) VALUES
('00000000-0000-0000-0000-000000000002', 'Demo Alert 1', 'LOW', '172.16.0.10'),
('00000000-0000-0000-0000-000000000002', 'Demo Alert 2', 'INFO', '172.16.0.20');

-- Test isolation: Query as default tenant
SELECT set_tenant_context('00000000-0000-0000-0000-000000000001'::UUID);
SELECT 'DEFAULT TENANT DASHBOARDS:' as info;
SELECT name, description FROM utm_dashboard;
SELECT 'DEFAULT TENANT ALERTS:' as info;
SELECT alert_name, alert_level, source_ip FROM utm_alert_log;

-- Test isolation: Query as demo tenant
SELECT set_tenant_context('00000000-0000-0000-0000-000000000002'::UUID);
SELECT 'DEMO TENANT DASHBOARDS:' as info;
SELECT name, description FROM utm_dashboard;
SELECT 'DEMO TENANT ALERTS:' as info;
SELECT alert_name, alert_level, source_ip FROM utm_alert_log;

-- Test without tenant context (should see all data)
RESET app.current_tenant_id;
SELECT 'ALL DATA (NO TENANT CONTEXT):' as info;
SELECT tenant_id, name FROM utm_dashboard ORDER BY tenant_id;
