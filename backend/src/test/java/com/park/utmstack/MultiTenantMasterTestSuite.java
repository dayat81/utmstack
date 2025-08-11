package com.park.utmstack;

import org.junit.platform.suite.api.SelectClasses;
import org.junit.platform.suite.api.Suite;

import com.park.utmstack.service.MultiTenantIsolationTestSuite;
import com.park.utmstack.security.MultiTenantAuthenticationTestSuite;
import com.park.utmstack.web.rest.TenantManagementAPITestSuite;
import com.park.utmstack.service.SecurityAuditTestSuite;
import com.park.utmstack.service.MultiTenantElasticsearchTestSuite;
import com.park.utmstack.service.TenantResourceQuotaAndComplianceTestSuite;

/**
 * Master test suite that runs all multi-tenant tests.
 * 
 * This suite includes comprehensive tests for:
 * - Tenant data isolation and security
 * - Authentication and authorization (JWT, RBAC)
 * - Tenant management APIs
 * - Security audit logging
 * - Multi-tenant Elasticsearch operations
 * - Resource quota management and compliance
 * 
 * Run with: mvn test -Dtest=MultiTenantMasterTestSuite
 */
@Suite
@SelectClasses({
    MultiTenantIsolationTestSuite.class,
    MultiTenantAuthenticationTestSuite.class,
    TenantManagementAPITestSuite.class,
    SecurityAuditTestSuite.class,
    MultiTenantElasticsearchTestSuite.class,
    TenantResourceQuotaAndComplianceTestSuite.class
})
public class MultiTenantMasterTestSuite {
    // This class serves as a test suite entry point
    // Individual test classes are executed in the order specified above
}
