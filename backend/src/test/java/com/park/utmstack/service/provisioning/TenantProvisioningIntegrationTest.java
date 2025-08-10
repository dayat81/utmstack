package com.park.utmstack.service.provisioning;

import com.park.utmstack.service.TenantProvisioningService;
import com.park.utmstack.service.TenantProvisioningService.*;
import com.park.utmstack.service.TenantResourceQuotaService;
import com.park.utmstack.service.TenantService;
import com.park.utmstack.service.elasticsearch.MultiTenantElasticsearchService;
import org.junit.jupiter.api.*;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.*;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;

/**
 * Comprehensive integration test suite for tenant provisioning workflows.
 * Tests end-to-end provisioning, validation, rollback, and edge cases.
 */
@SpringBootTest
@ActiveProfiles("test")
@TestMethodOrder(MethodOrderer.OrderAnnotation.class)
class TenantProvisioningIntegrationTest {

    private static final Logger log = LoggerFactory.getLogger(TenantProvisioningIntegrationTest.class);

    @Autowired
    private TenantProvisioningService provisioningService;

    @Autowired
    private TenantService tenantService;

    @Autowired
    private TenantResourceQuotaService quotaService;

    @Autowired
    private MultiTenantElasticsearchService elasticsearchService;

    private final ExecutorService executorService = Executors.newFixedThreadPool(10);
    private final List<UUID> createdTenantIds = new ArrayList<>();

    @BeforeEach
    void setUp() {
        log.info("Setting up integration test environment");
        // Clean up any existing test data
        cleanup();
    }

    @AfterEach
    void tearDown() {
        log.info("Tearing down integration test environment");
        cleanup();
    }

    @Test
    @Order(1)
    @DisplayName("Test successful single tenant provisioning")
    void testSuccessfulSingleTenantProvisioning() throws Exception {
        log.info("Testing successful single tenant provisioning");

        // Arrange
        TenantProvisioningRequest request = createValidProvisioningRequest("IntegTest-SingleTenant", "integtest-single");

        // Act
        CompletableFuture<TenantProvisioningResult> future = provisioningService.provisionTenant(request);
        TenantProvisioningResult result = future.get(30, TimeUnit.SECONDS);

        // Assert
        Assertions.assertEquals("SUCCESS", result.getStatus(), "Provisioning should succeed");
        Assertions.assertNotNull(result.getTenantId(), "Tenant ID should be generated");
        Assertions.assertTrue(result.getDurationMs() > 0, "Duration should be positive");
        Assertions.assertTrue(result.getSteps().containsKey("tenant_created"), "Should have tenant creation step");
        Assertions.assertTrue(result.getSteps().containsKey("elasticsearch_templates"), "Should have Elasticsearch setup");
        Assertions.assertTrue(result.getSteps().containsKey("resource_quotas"), "Should have resource quotas");
        Assertions.assertTrue(result.getSteps().containsKey("validation"), "Should have validation step");

        // Verify tenant exists and is active
        var tenant = tenantService.getTenant(result.getTenantId());
        Assertions.assertTrue(tenant.isPresent(), "Tenant should exist");
        Assertions.assertEquals("active", tenant.get().getStatus(), "Tenant should be active");

        // Verify quotas are configured
        Assertions.assertTrue(quotaService.areQuotasConfigured(result.getTenantId()), 
            "Quotas should be configured");

        // Track for cleanup
        createdTenantIds.add(result.getTenantId());

        log.info("Single tenant provisioning test completed successfully");
    }

    @Test
    @Order(2)
    @DisplayName("Test concurrent tenant provisioning")
    void testConcurrentTenantProvisioning() throws Exception {
        log.info("Testing concurrent tenant provisioning");

        // Arrange
        int concurrentTenants = 5;
        List<CompletableFuture<TenantProvisioningResult>> futures = new ArrayList<>();

        // Act
        for (int i = 0; i < concurrentTenants; i++) {
            TenantProvisioningRequest request = createValidProvisioningRequest(
                "IntegTest-Concurrent-" + i, "integtest-concurrent-" + i);
            futures.add(provisioningService.provisionTenant(request));
        }

        // Wait for all to complete
        List<TenantProvisioningResult> results = new ArrayList<>();
        for (CompletableFuture<TenantProvisioningResult> future : futures) {
            TenantProvisioningResult result = future.get(60, TimeUnit.SECONDS);
            results.add(result);
        }

        // Assert
        long successCount = results.stream().filter(r -> "SUCCESS".equals(r.getStatus())).count();
        Assertions.assertEquals(concurrentTenants, successCount, 
            "All concurrent provisioning operations should succeed");

        // Verify all tenants are unique and properly configured
        Set<UUID> tenantIds = new HashSet<>();
        for (TenantProvisioningResult result : results) {
            Assertions.assertNotNull(result.getTenantId(), "Each result should have a tenant ID");
            Assertions.assertTrue(tenantIds.add(result.getTenantId()), "Tenant IDs should be unique");
            
            // Verify tenant configuration
            var tenant = tenantService.getTenant(result.getTenantId());
            Assertions.assertTrue(tenant.isPresent(), "Tenant should exist");
            Assertions.assertEquals("active", tenant.get().getStatus(), "Tenant should be active");
            
            // Track for cleanup
            createdTenantIds.add(result.getTenantId());
        }

        log.info("Concurrent tenant provisioning test completed successfully");
    }

    @Test
    @Order(3)
    @DisplayName("Test tenant provisioning with different tiers")
    void testTenantProvisioningWithDifferentTiers() throws Exception {
        log.info("Testing tenant provisioning with different tiers");

        // Arrange
        String[] tiers = {"standard", "professional", "enterprise"};
        List<TenantProvisioningResult> results = new ArrayList<>();

        // Act
        for (int i = 0; i < tiers.length; i++) {
            TenantProvisioningRequest request = createValidProvisioningRequest(
                "IntegTest-Tier-" + tiers[i], "integtest-tier-" + i);
            request.setTier(tiers[i]);

            CompletableFuture<TenantProvisioningResult> future = provisioningService.provisionTenant(request);
            TenantProvisioningResult result = future.get(30, TimeUnit.SECONDS);
            results.add(result);
        }

        // Assert
        for (int i = 0; i < results.size(); i++) {
            TenantProvisioningResult result = results.get(i);
            Assertions.assertEquals("SUCCESS", result.getStatus(), 
                "Provisioning should succeed for tier: " + tiers[i]);

            var tenant = tenantService.getTenant(result.getTenantId());
            Assertions.assertTrue(tenant.isPresent(), "Tenant should exist");
            Assertions.assertEquals(tiers[i], tenant.get().getTier(), "Tier should match");

            // Verify tier-specific resource limits
            var quotaStatus = quotaService.getResourceQuotaStatus(result.getTenantId());
            Assertions.assertEquals(tiers[i], quotaStatus.getTier(), "Quota tier should match");

            // Track for cleanup
            createdTenantIds.add(result.getTenantId());
        }

        log.info("Tier-based provisioning test completed successfully");
    }

    @Test
    @Order(4)
    @DisplayName("Test tenant provisioning failure scenarios")
    void testTenantProvisioningFailureScenarios() throws Exception {
        log.info("Testing tenant provisioning failure scenarios");

        // Test 1: Duplicate subdomain
        TenantProvisioningRequest originalRequest = createValidProvisioningRequest(
            "IntegTest-Original", "integtest-duplicate");
        
        CompletableFuture<TenantProvisioningResult> originalFuture = 
            provisioningService.provisionTenant(originalRequest);
        TenantProvisioningResult originalResult = originalFuture.get(30, TimeUnit.SECONDS);
        
        Assertions.assertEquals("SUCCESS", originalResult.getStatus(), 
            "Original provisioning should succeed");
        createdTenantIds.add(originalResult.getTenantId());

        // Try to create tenant with same subdomain
        TenantProvisioningRequest duplicateRequest = createValidProvisioningRequest(
            "IntegTest-Duplicate", "integtest-duplicate");
        
        CompletableFuture<TenantProvisioningResult> duplicateFuture = 
            provisioningService.provisionTenant(duplicateRequest);
        TenantProvisioningResult duplicateResult = duplicateFuture.get(30, TimeUnit.SECONDS);
        
        Assertions.assertEquals("FAILED", duplicateResult.getStatus(), 
            "Duplicate subdomain should fail");
        Assertions.assertNotNull(duplicateResult.getError(), "Should have error message");
        Assertions.assertNull(duplicateResult.getTenantId(), "Should not have tenant ID on failure");

        // Test 2: Invalid tier
        TenantProvisioningRequest invalidTierRequest = createValidProvisioningRequest(
            "IntegTest-InvalidTier", "integtest-invalidtier");
        invalidTierRequest.setTier("invalid-tier");
        
        CompletableFuture<TenantProvisioningResult> invalidTierFuture = 
            provisioningService.provisionTenant(invalidTierRequest);
        TenantProvisioningResult invalidTierResult = invalidTierFuture.get(30, TimeUnit.SECONDS);
        
        Assertions.assertEquals("FAILED", invalidTierResult.getStatus(), 
            "Invalid tier should fail");

        log.info("Failure scenario tests completed successfully");
    }

    @Test
    @Order(5)
    @DisplayName("Test tenant deprovisioning")
    void testTenantDeprovisioning() throws Exception {
        log.info("Testing tenant deprovisioning");

        // Arrange - Create a tenant first
        TenantProvisioningRequest request = createValidProvisioningRequest(
            "IntegTest-Deprovision", "integtest-deprovision");
        
        CompletableFuture<TenantProvisioningResult> provisionFuture = 
            provisioningService.provisionTenant(request);
        TenantProvisioningResult provisionResult = provisionFuture.get(30, TimeUnit.SECONDS);
        
        Assertions.assertEquals("SUCCESS", provisionResult.getStatus(), 
            "Provisioning should succeed");
        UUID tenantId = provisionResult.getTenantId();

        // Act - Deprovision the tenant
        CompletableFuture<TenantDeprovisioningResult> deprovisionFuture = 
            provisioningService.deprovisionTenant(tenantId, false);
        TenantDeprovisioningResult deprovisionResult = deprovisionFuture.get(30, TimeUnit.SECONDS);

        // Assert
        Assertions.assertEquals("SUCCESS", deprovisionResult.getStatus(), 
            "Deprovisioning should succeed");
        Assertions.assertTrue(deprovisionResult.getSteps().containsKey("tenant_deactivated"), 
            "Should have deactivation step");
        Assertions.assertTrue(deprovisionResult.getSteps().containsKey("elasticsearch_cleanup"), 
            "Should have Elasticsearch cleanup step");
        Assertions.assertTrue(deprovisionResult.getSteps().containsKey("quota_cleanup"), 
            "Should have quota cleanup step");

        // Verify tenant status
        var tenant = tenantService.getTenant(tenantId);
        Assertions.assertTrue(tenant.isPresent(), "Tenant should still exist");
        Assertions.assertEquals("deleted", tenant.get().getStatus(), "Tenant should be marked as deleted");

        log.info("Tenant deprovisioning test completed successfully");
    }

    @Test
    @Order(6)
    @DisplayName("Test provisioning status monitoring")
    void testProvisioningStatusMonitoring() throws Exception {
        log.info("Testing provisioning status monitoring");

        // Arrange
        TenantProvisioningRequest request = createValidProvisioningRequest(
            "IntegTest-Status", "integtest-status");

        // Act - Start provisioning
        CompletableFuture<TenantProvisioningResult> future = provisioningService.provisionTenant(request);
        
        // Monitor status during provisioning (simulate async monitoring)
        Thread.sleep(100); // Allow provisioning to start
        
        TenantProvisioningResult result = future.get(30, TimeUnit.SECONDS);
        UUID tenantId = result.getTenantId();

        // Check final status
        ProvisioningStatus status = provisioningService.getProvisioningStatus(tenantId);

        // Assert
        Assertions.assertNotNull(status, "Status should not be null");
        Assertions.assertEquals(tenantId, status.getTenantId(), "Tenant ID should match");
        Assertions.assertTrue(status.isOverallReady(), "Should be fully provisioned");
        Assertions.assertTrue(status.isElasticsearchReady(), "Elasticsearch should be ready");
        Assertions.assertTrue(status.isQuotasConfigured(), "Quotas should be configured");

        // Track for cleanup
        createdTenantIds.add(tenantId);

        log.info("Provisioning status monitoring test completed successfully");
    }

    @Test
    @Order(7)
    @DisplayName("Test resource quota validation during provisioning")
    void testResourceQuotaValidationDuringProvisioning() throws Exception {
        log.info("Testing resource quota validation during provisioning");

        // Arrange
        TenantProvisioningRequest request = createValidProvisioningRequest(
            "IntegTest-Quota", "integtest-quota");
        request.setTier("standard");

        // Act
        CompletableFuture<TenantProvisioningResult> future = provisioningService.provisionTenant(request);
        TenantProvisioningResult result = future.get(30, TimeUnit.SECONDS);

        // Assert
        Assertions.assertEquals("SUCCESS", result.getStatus(), "Provisioning should succeed");
        UUID tenantId = result.getTenantId();

        // Verify quota configuration
        var quotaStatus = quotaService.getResourceQuotaStatus(tenantId);
        Assertions.assertNotNull(quotaStatus, "Quota status should not be null");
        Assertions.assertEquals("standard", quotaStatus.getTier(), "Tier should be standard");
        Assertions.assertEquals("OK", quotaStatus.getOverallStatus(), "Quota status should be OK");

        // Test quota enforcement
        var quotaCheck = quotaService.checkResourceQuota(tenantId, "users", 30); // Above standard limit
        Assertions.assertFalse(quotaCheck.isAllowed(), "Should deny request above quota");

        quotaCheck = quotaService.checkResourceQuota(tenantId, "users", 20); // Within standard limit
        Assertions.assertTrue(quotaCheck.isAllowed(), "Should allow request within quota");

        // Track for cleanup
        createdTenantIds.add(tenantId);

        log.info("Resource quota validation test completed successfully");
    }

    @Test
    @Order(8)
    @DisplayName("Test tenant isolation after provisioning")
    void testTenantIsolationAfterProvisioning() throws Exception {
        log.info("Testing tenant isolation after provisioning");

        // Arrange - Create two tenants
        TenantProvisioningRequest request1 = createValidProvisioningRequest(
            "IntegTest-Isolation-1", "integtest-isolation-1");
        TenantProvisioningRequest request2 = createValidProvisioningRequest(
            "IntegTest-Isolation-2", "integtest-isolation-2");

        CompletableFuture<TenantProvisioningResult> future1 = provisioningService.provisionTenant(request1);
        CompletableFuture<TenantProvisioningResult> future2 = provisioningService.provisionTenant(request2);

        TenantProvisioningResult result1 = future1.get(30, TimeUnit.SECONDS);
        TenantProvisioningResult result2 = future2.get(30, TimeUnit.SECONDS);

        Assertions.assertEquals("SUCCESS", result1.getStatus(), "First tenant provisioning should succeed");
        Assertions.assertEquals("SUCCESS", result2.getStatus(), "Second tenant provisioning should succeed");

        UUID tenantId1 = result1.getTenantId();
        UUID tenantId2 = result2.getTenantId();

        // Act & Assert - Test isolation
        
        // Test configuration isolation
        var configs1 = tenantService.getTenantConfigurations(tenantId1);
        var configs2 = tenantService.getTenantConfigurations(tenantId2);
        
        Assertions.assertNotEquals(configs1, configs2, "Configurations should be isolated");

        // Test quota isolation
        var quota1 = quotaService.getResourceQuotaStatus(tenantId1);
        var quota2 = quotaService.getResourceQuotaStatus(tenantId2);
        
        Assertions.assertEquals(tenantId1, quota1.getTenantId(), "Quota should be for correct tenant");
        Assertions.assertEquals(tenantId2, quota2.getTenantId(), "Quota should be for correct tenant");
        Assertions.assertNotEquals(quota1.getTenantId(), quota2.getTenantId(), "Quotas should be isolated");

        // Track for cleanup
        createdTenantIds.add(tenantId1);
        createdTenantIds.add(tenantId2);

        log.info("Tenant isolation test completed successfully");
    }

    @Test
    @Order(9)
    @DisplayName("Test stress testing with rapid provisioning")
    void testStressTestingWithRapidProvisioning() throws Exception {
        log.info("Testing stress scenarios with rapid provisioning");

        // Arrange
        int rapidProvisioningCount = 10;
        List<CompletableFuture<TenantProvisioningResult>> futures = new ArrayList<>();

        long startTime = System.currentTimeMillis();

        // Act - Rapid provisioning
        for (int i = 0; i < rapidProvisioningCount; i++) {
            TenantProvisioningRequest request = createValidProvisioningRequest(
                "IntegTest-Stress-" + i, "integtest-stress-" + i);
            futures.add(provisioningService.provisionTenant(request));
        }

        // Wait for all to complete
        List<TenantProvisioningResult> results = new ArrayList<>();
        for (CompletableFuture<TenantProvisioningResult> future : futures) {
            TenantProvisioningResult result = future.get(120, TimeUnit.SECONDS); // Increased timeout for stress test
            results.add(result);
        }

        long duration = System.currentTimeMillis() - startTime;

        // Assert
        long successCount = results.stream().filter(r -> "SUCCESS".equals(r.getStatus())).count();
        Assertions.assertEquals(rapidProvisioningCount, successCount, 
            "All rapid provisioning operations should succeed");

        double throughput = (double) rapidProvisioningCount / (duration / 1000.0);
        log.info("Rapid provisioning throughput: {} tenants/second", throughput);
        
        // Reasonable expectation: should handle at least 0.1 tenants/second under stress
        Assertions.assertTrue(throughput > 0.05, "Throughput should be reasonable under stress");

        // Verify all tenants are properly configured
        for (TenantProvisioningResult result : results) {
            Assertions.assertTrue(quotaService.areQuotasConfigured(result.getTenantId()), 
                "All tenants should have quotas configured");
            
            var tenant = tenantService.getTenant(result.getTenantId());
            Assertions.assertTrue(tenant.isPresent(), "All tenants should exist");
            Assertions.assertEquals("active", tenant.get().getStatus(), "All tenants should be active");
            
            // Track for cleanup
            createdTenantIds.add(result.getTenantId());
        }

        log.info("Stress testing completed successfully");
    }

    // Helper methods
    private TenantProvisioningRequest createValidProvisioningRequest(String name, String subdomain) {
        TenantProvisioningRequest request = new TenantProvisioningRequest();
        request.setName(name);
        request.setSubdomain(subdomain);
        request.setTier("standard");
        
        // Add some custom configurations
        Map<String, String> customConfigs = new HashMap<>();
        customConfigs.put("test_config", "test_value");
        customConfigs.put("integration_test", "true");
        request.setCustomConfigurations(customConfigs);
        
        return request;
    }

    private void cleanup() {
        log.info("Cleaning up test tenants: {}", createdTenantIds.size());
        
        for (UUID tenantId : createdTenantIds) {
            try {
                // Attempt to deprovision (cleanup)
                CompletableFuture<TenantDeprovisioningResult> future = 
                    provisioningService.deprovisionTenant(tenantId, false);
                future.get(30, TimeUnit.SECONDS);
                log.debug("Cleaned up tenant: {}", tenantId);
            } catch (Exception e) {
                log.warn("Failed to cleanup tenant {}: {}", tenantId, e.getMessage());
            }
        }
        
        createdTenantIds.clear();
        log.info("Cleanup completed");
    }

    /**
     * Custom test configuration for integration tests
     */
    @TestConfiguration
    static class IntegrationTestConfiguration {
        // Could add test-specific beans here if needed
    }
}
