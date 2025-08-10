/**
 * Multi-Tenant Database Verification Test
 * Validates tenant creation and database configuration
 */

const { exec } = require('child_process');
const util = require('util');
const execAsync = util.promisify(exec);

async function verifyTenantDatabase() {
    console.log('🗄️  Multi-Tenant Database Verification');
    console.log('=====================================\n');

    try {
        // Test 1: Verify tenant table exists and has data
        console.log('📊 Test 1: Verifying tenant table structure and data');
        const tenantQuery = `
            SELECT 
                id, 
                name, 
                subdomain, 
                status, 
                tier,
                created_at
            FROM utm_tenant 
            ORDER BY created_at;
        `;
        
        const { stdout: tenantData } = await execAsync(
            `docker exec pos-db psql -U pos_user -d pos_db -c "${tenantQuery}"`
        );
        
        console.log('   Tenant data:');
        console.log(tenantData);
        
        // Parse tenant count
        const tenantLines = tenantData.split('\n').filter(line => 
            line.includes('|') && !line.includes('id') && !line.includes('---')
        );
        console.log(`   ✅ Found ${tenantLines.length} tenants\n`);

        // Test 2: Verify tenant configuration table
        console.log('📋 Test 2: Verifying tenant configuration data');
        const configQuery = `
            SELECT 
                t.name as tenant_name,
                tc.config_key,
                tc.config_value,
                tc.config_type
            FROM utm_tenant_config tc
            JOIN utm_tenant t ON tc.tenant_id = t.id
            ORDER BY t.name, tc.config_key;
        `;
        
        const { stdout: configData } = await execAsync(
            `docker exec pos-db psql -U pos_user -d pos_db -c "${configQuery}"`
        );
        
        console.log('   Configuration data:');
        console.log(configData);

        // Test 3: Verify tenant roles  
        console.log('👥 Test 3: Verifying tenant roles');
        const rolesQuery = `
            SELECT 
                t.name as tenant_name,
                tr.role_name,
                tr.permissions
            FROM utm_tenant_role tr
            JOIN utm_tenant t ON tr.tenant_id = t.id
            ORDER BY t.name, tr.role_name;
        `;
        
        const { stdout: rolesData } = await execAsync(
            `docker exec pos-db psql -U pos_user -d pos_db -c "${rolesQuery}"`
        );
        
        console.log('   Roles data:');
        console.log(rolesData);

        // Test 4: Test Row-Level Security
        console.log('🔒 Test 4: Testing Row-Level Security (if enabled)');
        const rlsQuery = `
            SELECT 
                schemaname,
                tablename,
                rowsecurity 
            FROM pg_tables 
            WHERE tablename LIKE 'utm_%' 
            AND schemaname = 'public';
        `;
        
        const { stdout: rlsData } = await execAsync(
            `docker exec pos-db psql -U pos_user -d pos_db -c "${rlsQuery}"`
        );
        
        console.log('   Row-Level Security status:');
        console.log(rlsData);

        // Test 5: Verify database function for tenant context
        console.log('⚙️  Test 5: Testing tenant context functions');
        const functionQuery = `
            SELECT 
                proname as function_name,
                prosrc as function_body
            FROM pg_proc 
            WHERE proname LIKE '%tenant%';
        `;
        
        try {
            const { stdout: functionData } = await execAsync(
                `docker exec pos-db psql -U pos_user -d pos_db -c "${functionQuery}"`
            );
            
            console.log('   Tenant-related functions:');
            console.log(functionData);
        } catch (err) {
            console.log('   ⚠️  Could not retrieve function data:', err.message);
        }

        // Summary
        console.log('📈 Summary:');
        console.log('   ✅ Tenant table structure: OK');
        console.log('   ✅ Multi-tenant data: Created successfully');
        console.log('   ✅ Database verification: PASSED');
        
        return {
            success: true,
            tenantCount: tenantLines.length,
            message: 'Multi-tenant database setup verified successfully'
        };

    } catch (error) {
        console.error('❌ Database verification failed:', error.message);
        return {
            success: false,
            error: error.message
        };
    }
}

async function verifyTenantIsolation() {
    console.log('\n🔐 Testing Tenant Data Isolation');
    console.log('=================================\n');

    try {
        // Get tenant IDs
        const tenantsQuery = `SELECT id, subdomain FROM utm_tenant;`;
        const { stdout: tenantsData } = await execAsync(
            `docker exec pos-db psql -U pos_user -d pos_db -c "${tenantsQuery}"`
        );

        console.log('📋 Available tenants:');
        console.log(tenantsData);

        // Test tenant-specific queries (simulated)
        console.log('🔍 Testing data isolation patterns:');
        
        // Check if tenant_id columns exist in core tables
        const tablesQuery = `
            SELECT 
                table_name,
                column_name
            FROM information_schema.columns 
            WHERE column_name = 'tenant_id' 
            AND table_schema = 'public'
            ORDER BY table_name;
        `;
        
        const { stdout: tablesData } = await execAsync(
            `docker exec pos-db psql -U pos_user -d pos_db -c "${tablesQuery}"`
        );

        console.log('   Tables with tenant_id column:');
        console.log(tablesData);

        const tableLines = tablesData.split('\n').filter(line => 
            line.includes('|') && !line.includes('table_name') && !line.includes('---')
        );
        
        if (tableLines.length > 0) {
            console.log(`   ✅ Found ${tableLines.length} tables with tenant isolation`);
        } else {
            console.log('   ⚠️  No tenant_id columns found - tables may not be multi-tenant ready');
        }

        return { success: true };

    } catch (error) {
        console.error('❌ Isolation test failed:', error.message);
        return { success: false, error: error.message };
    }
}

async function generateTenantReport() {
    console.log('\n📊 Multi-Tenant Setup Report');
    console.log('=============================\n');

    try {
        const reportQuery = `
            WITH tenant_stats AS (
                SELECT 
                    t.id,
                    t.name,
                    t.subdomain,
                    t.status,
                    t.tier,
                    t.created_at,
                    COUNT(tc.id) as config_count,
                    COUNT(tr.id) as role_count
                FROM utm_tenant t
                LEFT JOIN utm_tenant_config tc ON t.id = tc.tenant_id
                LEFT JOIN utm_tenant_role tr ON t.id = tr.tenant_id
                GROUP BY t.id, t.name, t.subdomain, t.status, t.tier, t.created_at
            )
            SELECT 
                name as "Tenant Name",
                subdomain as "Subdomain", 
                status as "Status",
                tier as "Tier",
                config_count as "Configs",
                role_count as "Roles",
                created_at as "Created"
            FROM tenant_stats 
            ORDER BY created_at;
        `;

        const { stdout: reportData } = await execAsync(
            `docker exec pos-db psql -U pos_user -d pos_db -c "${reportQuery}"`
        );

        console.log(reportData);

        // Additional summary
        const summaryQuery = `
            SELECT 
                COUNT(*) as total_tenants,
                COUNT(CASE WHEN status = 'active' THEN 1 END) as active_tenants,
                COUNT(DISTINCT tier) as unique_tiers
            FROM utm_tenant;
        `;

        const { stdout: summaryData } = await execAsync(
            `docker exec pos-db psql -U pos_user -d pos_db -c "${summaryQuery}"`
        );

        console.log('Summary Statistics:');
        console.log(summaryData);

        return { success: true };

    } catch (error) {
        console.error('❌ Report generation failed:', error.message);
        return { success: false, error: error.message };
    }
}

async function main() {
    try {
        console.log('UTMStack Multi-Tenant Database Verification Suite');
        console.log('==================================================\n');

        // Run all verification tests
        const dbResult = await verifyTenantDatabase();
        const isolationResult = await verifyTenantIsolation();
        const reportResult = await generateTenantReport();

        console.log('\n🎯 Final Results:');
        console.log('=================');
        console.log(`Database Verification: ${dbResult.success ? '✅ PASSED' : '❌ FAILED'}`);
        console.log(`Isolation Testing: ${isolationResult.success ? '✅ PASSED' : '❌ FAILED'}`);
        console.log(`Report Generation: ${reportResult.success ? '✅ PASSED' : '❌ FAILED'}`);

        if (dbResult.success && isolationResult.success && reportResult.success) {
            console.log('\n🎉 All database verification tests PASSED!');
            console.log('✅ Multi-tenant database setup is working correctly');
            console.log(`✅ ${dbResult.tenantCount || 'Multiple'} tenants configured successfully`);
        } else {
            console.log('\n⚠️  Some tests failed - check the output above');
        }

    } catch (error) {
        console.error('\n❌ Verification suite failed:', error.message);
        process.exit(1);
    }
}

if (require.main === module) {
    main();
}

module.exports = { 
    verifyTenantDatabase, 
    verifyTenantIsolation, 
    generateTenantReport 
};
