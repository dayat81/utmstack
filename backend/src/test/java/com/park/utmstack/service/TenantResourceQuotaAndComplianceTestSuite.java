package com.park.utmstack.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.park.utmstack.domain.User;
import com.park.utmstack.domain.UtmDashboard;
import com.park.utmstack.domain.UtmTenant;
import com.park.utmstack.repository.UserRepository;
import com.park.utmstack.repository.UtmDashboardRepository;
import com.park.utmstack.repository.UtmTenantRepository;
import com.park.utmstack.security.TenantContext;
import com.park.utmstack.service.TenantProvisioningService.TenantProvisioningRequest;
import com.park.utmstack.service.compliance.ComplianceFrameworkService;
import com.park.utmstack.service.compliance.DataRetentionService;
import com.park.utmstack.service.compliance.GovernancePolicyService;
import org.junit.jupiter.api.*;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.security.test.context.support.WithMockUser;
import org.springframework.test.context.ActiveProfiles;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.*;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.stream.IntStream;

import static org.assertj.core.api.Assertions.*;

/**
 * Comprehensive test suite for tenant resource quota management and compliance features.
 * Tests quota enforcement, compliance monitoring, and governance policies.
 */
@SpringBootTest
@ActiveProfiles("test")
@TestMethodOrder(MethodOrderer.OrderAnnotation.class)
public class TenantResourceQuotaAndComplianceTestSuite {

    private static final Logger log = LoggerFactory.getLogger(TenantResourceQuotaAndComplianceTestSuite.class);

    @Autowired private TenantResourceQuotaService quotaService;
    @Autowired private ComplianceFrameworkService complianceService;
    @Autowired private DataRetentionService dataRetentionService;
    @Autowired private GovernancePolicyService governanceService;
    @Autowired private TenantProvisioningService tenantProvisioningService;
    @Autowired private UserRepository userRepository;
    @Autowired private UtmDashboardRepository dashboardRepository;
    @Autowired private UtmTenantRepository tenantRepository;
    @Autowired private ObjectMapper objectMapper;

    private final List<UUID> testTenantIds = new ArrayList<>();
    private final List<String> testUserIds = new ArrayList<>();

    @BeforeEach
    void setUp() {
        TenantContext.clear();
    }

    @AfterEach
    void tearDown() {
        cleanup();
        TenantContext.clear();
    }

    /**
     * Test 1: Basic resource quota management
     */
    @Test
    @Order(1)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test basic resource quota management")
    void testBasicResourceQuotaManagement() throws Exception {
        log.info("Testing basic resource quota management");

        UUID tenantId = createTestTenant("Quota Test", "quota-test");
        TenantContext.setCurrentTenant(tenantId);

        // Set initial quotas
        Map<String, Integer> quotas = new HashMap<>();
        quotas.put("maxUsers", 10);
        quotas.put("maxDashboards", 5);
        quotas.put("maxAlerts", 100);
        quotas.put("maxStorageGB", 50);

        quotaService.setTenantQuotas(tenantId, quotas);

        // Verify quotas were set
        Map<String, Integer> retrievedQuotas = quotaService.getTenantQuotas(tenantId);
        assertThat(retrievedQuotas.get("maxUsers")).isEqualTo(10);
        assertThat(retrievedQuotas.get("maxDashboards")).isEqualTo(5);
        assertThat(retrievedQuotas.get("maxAlerts")).isEqualTo(100);
        assertThat(retrievedQuotas.get("maxStorageGB")).isEqualTo(50);

        // Test quota usage tracking
        Map<String, Integer> initialUsage = quotaService.getTenantUsage(tenantId);
        assertThat(initialUsage.get("usedUsers")).isEqualTo(0);
        assertThat(initialUsage.get("usedDashboards")).isEqualTo(0);

        // Create resources and verify usage tracking
        User user1 = createTestUser(tenantId, "user1@test.com", "User", "One");
        User user2 = createTestUser(tenantId, "user2@test.com", "User", "Two");

        UtmDashboard dashboard1 = createTestDashboard(tenantId, "Dashboard 1", "Test Dashboard 1");

        // Check usage updated
        Map<String, Integer> updatedUsage = quotaService.getTenantUsage(tenantId);
        assertThat(updatedUsage.get("usedUsers")).isEqualTo(2);
        assertThat(updatedUsage.get("usedDashboards")).isEqualTo(1);

        // Test quota utilization reporting
        Map<String, Double> utilization = quotaService.getQuotaUtilization(tenantId);
        assertThat(utilization.get("users")).isEqualTo(20.0); // 2/10 = 20%
        assertThat(utilization.get("dashboards")).isEqualTo(20.0); // 1/5 = 20%
    }

    /**
     * Test 2: Quota enforcement and violations
     */
    @Test
    @Order(2)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test quota enforcement and violations")
    void testQuotaEnforcementAndViolations() throws Exception {
        log.info("Testing quota enforcement and violations");

        UUID tenantId = createTestTenant("Enforcement Test", "enforcement-test");
        TenantContext.setCurrentTenant(tenantId);

        // Set strict quotas
        Map<String, Integer> strictQuotas = new HashMap<>();
        strictQuotas.put("maxUsers", 2);
        strictQuotas.put("maxDashboards", 1);

        quotaService.setTenantQuotas(tenantId, strictQuotas);

        // Create resources up to quota
        User user1 = createTestUser(tenantId, "user1@enforcement.com", "User", "One");
        User user2 = createTestUser(tenantId, "user2@enforcement.com", "User", "Two");
        UtmDashboard dashboard1 = createTestDashboard(tenantId, "Dashboard 1", "Test Dashboard");

        // Verify quotas are being enforced
        assertThat(quotaService.canCreateResource(tenantId, "users")).isFalse();
        assertThat(quotaService.canCreateResource(tenantId, "dashboards")).isFalse();

        // Test quota violation detection
        List<String> violations = quotaService.checkQuotaViolations(tenantId);
        assertThat(violations).hasSize(2);
        assertThat(violations).contains("users quota reached", "dashboards quota reached");

        // Test quota exception when attempting to exceed limits
        assertThatThrownBy(() -> {
            quotaService.enforceQuota(tenantId, "users");
        }).isInstanceOf(TenantResourceQuotaService.QuotaExceededException.class);

        // Test quota warnings (80% threshold)
        quotaService.setTenantQuotas(tenantId, Map.of("maxUsers", 10, "maxDashboards", 10));
        
        // Create resources to 80% capacity
        for (int i = 3; i <= 8; i++) {
            createTestUser(tenantId, "user" + i + "@test.com", "User", String.valueOf(i));
        }

        List<String> warnings = quotaService.getQuotaWarnings(tenantId);
        assertThat(warnings).contains("users quota at 80%");
    }

    /**
     * Test 3: Compliance framework monitoring
     */
    @Test
    @Order(3)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test compliance framework monitoring")
    void testComplianceFrameworkMonitoring() throws Exception {
        log.info("Testing compliance framework monitoring");

        UUID tenantId = createTestTenant("Compliance Test", "compliance-test");
        TenantContext.setCurrentTenant(tenantId);

        // Test SOC2 compliance evaluation
        Map<String, Object> soc2Evaluation = complianceService.evaluateSOC2Compliance(tenantId);
        
        assertThat(soc2Evaluation).containsKeys("overall_score", "controls", "violations", "recommendations");
        assertThat(soc2Evaluation.get("overall_score")).isInstanceOf(Double.class);
        
        @SuppressWarnings("unchecked")
        Map<String, Object> controls = (Map<String, Object>) soc2Evaluation.get("controls");
        assertThat(controls).containsKeys("access_control", "data_encryption", "audit_logging", "incident_response");

        // Test ISO27001 compliance evaluation
        Map<String, Object> isoEvaluation = complianceService.evaluateISO27001Compliance(tenantId);
        
        assertThat(isoEvaluation).containsKeys("overall_score", "controls", "maturity_level");
        assertThat(isoEvaluation.get("maturity_level")).isIn("Initial", "Managed", "Defined", "Quantitatively Managed", "Optimizing");

        // Test GDPR compliance evaluation
        Map<String, Object> gdprEvaluation = complianceService.evaluateGDPRCompliance(tenantId);
        
        assertThat(gdprEvaluation).containsKeys("data_protection_score", "consent_management", "data_subject_rights", "breach_notification");

        // Test comprehensive compliance dashboard
        Map<String, Object> dashboard = complianceService.getComplianceDashboard(tenantId);
        
        assertThat(dashboard).containsKeys("soc2", "iso27001", "gdpr", "overall_compliance_score", "action_items");
        
        Double overallScore = (Double) dashboard.get("overall_compliance_score");
        assertThat(overallScore).isBetween(0.0, 100.0);

        // Test compliance violation tracking
        complianceService.reportComplianceViolation(tenantId, "GDPR", "DATA_BREACH", 
            "Unauthorized access to personal data", Map.of("affected_records", 100));

        List<Map<String, Object>> violations = complianceService.getComplianceViolations(tenantId, 
            Instant.now().minus(1, ChronoUnit.HOURS), Instant.now());
        
        assertThat(violations).hasSize(1);
        assertThat(violations.get(0).get("standard")).isEqualTo("GDPR");
        assertThat(violations.get(0).get("violation_type")).isEqualTo("DATA_BREACH");
    }

    /**
     * Test 4: Data retention policies
     */
    @Test
    @Order(4)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test data retention policies")
    void testDataRetentionPolicies() throws Exception {
        log.info("Testing data retention policies");

        UUID tenantId = createTestTenant("Retention Test", "retention-test");
        TenantContext.setCurrentTenant(tenantId);

        // Set retention policies
        Map<String, String> retentionPolicies = new HashMap<>();
        retentionPolicies.put("audit_logs", "7y");        // 7 years for audit logs
        retentionPolicies.put("user_data", "2y");         // 2 years for user data
        retentionPolicies.put("system_logs", "1y");       // 1 year for system logs
        retentionPolicies.put("temporary_data", "30d");   // 30 days for temporary data

        dataRetentionService.setRetentionPolicies(tenantId, retentionPolicies);

        // Verify policies were set
        Map<String, String> retrievedPolicies = dataRetentionService.getRetentionPolicies(tenantId);
        assertThat(retrievedPolicies.get("audit_logs")).isEqualTo("7y");
        assertThat(retrievedPolicies.get("user_data")).isEqualTo("2y");

        // Test retention calculation
        Instant now = Instant.now();
        Instant retentionDate = dataRetentionService.calculateRetentionDate("audit_logs", now);
        assertThat(retentionDate).isAfter(now.plus(6 * 365, ChronoUnit.DAYS)); // At least 6 years

        // Test data subject rights (GDPR)
        String dataSubjectId = "user123";
        
        // Right to access
        Map<String, Object> personalData = dataRetentionService.exportPersonalData(tenantId, dataSubjectId);
        assertThat(personalData).containsKeys("user_profile", "activity_logs", "preferences");

        // Right to erasure (right to be forgotten)
        Map<String, Object> erasureResult = dataRetentionService.executeRightToErasure(tenantId, dataSubjectId);
        assertThat(erasureResult.get("status")).isEqualTo("completed");
        assertThat(erasureResult.get("deleted_records")).isInstanceOf(Integer.class);

        // Data portability
        Map<String, Object> portabilityData = dataRetentionService.exportDataForPortability(tenantId, dataSubjectId, "JSON");
        assertThat(portabilityData).containsKeys("format", "data", "created_at");
        assertThat(portabilityData.get("format")).isEqualTo("JSON");

        // Test automatic cleanup scheduling
        dataRetentionService.scheduleRetentionCleanup(tenantId);
        
        List<Map<String, Object>> scheduledJobs = dataRetentionService.getScheduledCleanupJobs(tenantId);
        assertThat(scheduledJobs).isNotEmpty();
        
        for (Map<String, Object> job : scheduledJobs) {
            assertThat(job).containsKeys("data_type", "retention_period", "next_cleanup", "status");
        }

        // Test retention compliance reporting
        Map<String, Object> retentionReport = dataRetentionService.generateRetentionComplianceReport(tenantId);
        assertThat(retentionReport).containsKeys("policies_count", "compliant_data_types", "overdue_cleanups", "total_data_volume");
    }

    /**
     * Test 5: Governance policies
     */
    @Test
    @Order(5)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test governance policies")
    void testGovernancePolicies() throws Exception {
        log.info("Testing governance policies");

        UUID tenantId = createTestTenant("Governance Test", "governance-test");
        TenantContext.setCurrentTenant(tenantId);

        // Create governance policies
        Map<String, Object> accessControlPolicy = new HashMap<>();
        accessControlPolicy.put("name", "Access Control Policy");
        accessControlPolicy.put("type", "ACCESS_CONTROL");
        accessControlPolicy.put("rules", List.of(
            Map.of("condition", "time_of_day", "operator", "between", "values", List.of("09:00", "17:00")),
            Map.of("condition", "user_role", "operator", "in", "values", List.of("ADMIN", "USER")),
            Map.of("condition", "data_classification", "operator", "equals", "values", List.of("PUBLIC", "INTERNAL"))
        ));

        String policyId1 = governanceService.createPolicy(tenantId, accessControlPolicy);

        Map<String, Object> dataClassificationPolicy = new HashMap<>();
        dataClassificationPolicy.put("name", "Data Classification Policy");
        dataClassificationPolicy.put("type", "DATA_CLASSIFICATION");
        dataClassificationPolicy.put("rules", List.of(
            Map.of("pattern", ".*@.*\\.com", "classification", "PII"),
            Map.of("pattern", "password|secret|key", "classification", "CONFIDENTIAL"),
            Map.of("pattern", "public", "classification", "PUBLIC")
        ));

        String policyId2 = governanceService.createPolicy(tenantId, dataClassificationPolicy);

        // Test policy evaluation
        Map<String, Object> context = new HashMap<>();
        context.put("user_role", "USER");
        context.put("time_of_day", "14:30");
        context.put("data_classification", "INTERNAL");

        boolean accessAllowed = governanceService.evaluatePolicy(tenantId, policyId1, context);
        assertThat(accessAllowed).isTrue();

        // Test policy violation
        context.put("time_of_day", "22:00"); // Outside business hours
        boolean accessDenied = governanceService.evaluatePolicy(tenantId, policyId1, context);
        assertThat(accessDenied).isFalse();

        // Test data classification
        String email = "user@example.com";
        String classification = governanceService.classifyData(tenantId, policyId2, email);
        assertThat(classification).isEqualTo("PII");

        // Test governance dashboard
        Map<String, Object> dashboard = governanceService.getGovernanceDashboard(tenantId);
        assertThat(dashboard).containsKeys("total_policies", "policy_violations", "compliance_score", "active_policies");
        assertThat(dashboard.get("total_policies")).isEqualTo(2);

        // Test policy effectiveness tracking
        governanceService.recordPolicyViolation(tenantId, policyId1, "Unauthorized access attempt outside business hours");
        
        Map<String, Object> effectiveness = governanceService.getPolicyEffectiveness(tenantId, policyId1);
        assertThat(effectiveness).containsKeys("total_evaluations", "violations", "effectiveness_score");
        assertThat(effectiveness.get("violations")).isEqualTo(1);

        // Test automated policy updates
        Map<String, Object> updatedRules = new HashMap<>();
        updatedRules.put("rules", List.of(
            Map.of("condition", "time_of_day", "operator", "between", "values", List.of("08:00", "18:00")) // Extended hours
        ));
        
        governanceService.updatePolicy(tenantId, policyId1, updatedRules);
        
        Map<String, Object> updatedPolicy = governanceService.getPolicy(tenantId, policyId1);
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> rules = (List<Map<String, Object>>) updatedPolicy.get("rules");
        @SuppressWarnings("unchecked")
        List<String> timeValues = (List<String>) rules.get(0).get("values");
        assertThat(timeValues).containsExactly("08:00", "18:00");
    }

    /**
     * Test 6: Resource monitoring and alerting
     */
    @Test
    @Order(6)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test resource monitoring and alerting")
    void testResourceMonitoringAndAlerting() throws Exception {
        log.info("Testing resource monitoring and alerting");

        UUID tenantId = createTestTenant("Monitoring Test", "monitoring-test");
        TenantContext.setCurrentTenant(tenantId);

        // Set up monitoring thresholds
        Map<String, Integer> thresholds = new HashMap<>();
        thresholds.put("cpu_usage", 80);
        thresholds.put("memory_usage", 85);
        thresholds.put("disk_usage", 90);
        thresholds.put("user_quota_usage", 80);

        quotaService.setMonitoringThresholds(tenantId, thresholds);

        // Simulate resource usage
        quotaService.setTenantQuotas(tenantId, Map.of("maxUsers", 10));
        
        // Create users to reach 80% of quota
        for (int i = 1; i <= 8; i++) {
            createTestUser(tenantId, "user" + i + "@monitoring.com", "User", String.valueOf(i));
        }

        // Test threshold monitoring
        Map<String, Object> resourceStatus = quotaService.getResourceStatus(tenantId);
        assertThat(resourceStatus.get("user_quota_percentage")).isEqualTo(80.0);

        List<String> activeAlerts = quotaService.getActiveAlerts(tenantId);
        assertThat(activeAlerts).contains("User quota threshold exceeded (80%)");

        // Test automatic alerting
        List<Map<String, Object>> alerts = quotaService.generateResourceAlerts(tenantId);
        assertThat(alerts).isNotEmpty();
        
        Map<String, Object> userQuotaAlert = alerts.stream()
            .filter(alert -> "USER_QUOTA_WARNING".equals(alert.get("type")))
            .findFirst()
            .orElse(null);
        
        assertThat(userQuotaAlert).isNotNull();
        assertThat(userQuotaAlert.get("severity")).isEqualTo("WARNING");
        assertThat(userQuotaAlert.get("threshold")).isEqualTo(80);

        // Test historical monitoring data
        Map<String, Object> historicalData = quotaService.getHistoricalUsage(tenantId, 
            Instant.now().minus(1, ChronoUnit.HOURS), Instant.now());
        
        assertThat(historicalData).containsKeys("timestamps", "user_usage", "dashboard_usage");
        
        @SuppressWarnings("unchecked")
        List<Integer> userUsage = (List<Integer>) historicalData.get("user_usage");
        assertThat(userUsage).isNotEmpty();
        assertThat(userUsage.get(userUsage.size() - 1)).isEqualTo(8);
    }

    /**
     * Test 7: Tier-based quota management
     */
    @Test
    @Order(7)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test tier-based quota management")
    void testTierBasedQuotaManagement() throws Exception {
        log.info("Testing tier-based quota management");

        // Create tenants with different tiers
        UUID basicTenantId = createTestTenantWithTier("Basic Tenant", "basic-tenant", "basic");
        UUID standardTenantId = createTestTenantWithTier("Standard Tenant", "standard-tenant", "standard");
        UUID premiumTenantId = createTestTenantWithTier("Premium Tenant", "premium-tenant", "premium");

        // Verify tier-specific quotas are applied
        TenantContext.setCurrentTenant(basicTenantId);
        Map<String, Integer> basicQuotas = quotaService.getTenantQuotas(basicTenantId);
        assertThat(basicQuotas.get("maxUsers")).isEqualTo(5);
        assertThat(basicQuotas.get("maxDashboards")).isEqualTo(3);
        assertThat(basicQuotas.get("maxStorageGB")).isEqualTo(10);

        TenantContext.setCurrentTenant(standardTenantId);
        Map<String, Integer> standardQuotas = quotaService.getTenantQuotas(standardTenantId);
        assertThat(standardQuotas.get("maxUsers")).isEqualTo(25);
        assertThat(standardQuotas.get("maxDashboards")).isEqualTo(10);
        assertThat(standardQuotas.get("maxStorageGB")).isEqualTo(50);

        TenantContext.setCurrentTenant(premiumTenantId);
        Map<String, Integer> premiumQuotas = quotaService.getTenantQuotas(premiumTenantId);
        assertThat(premiumQuotas.get("maxUsers")).isEqualTo(100);
        assertThat(premiumQuotas.get("maxDashboards")).isEqualTo(50);
        assertThat(premiumQuotas.get("maxStorageGB")).isEqualTo(500);

        // Test tier upgrade
        quotaService.upgradeTenantTier(basicTenantId, "standard");
        
        TenantContext.setCurrentTenant(basicTenantId);
        Map<String, Integer> upgradedQuotas = quotaService.getTenantQuotas(basicTenantId);
        assertThat(upgradedQuotas.get("maxUsers")).isEqualTo(25);
        assertThat(upgradedQuotas.get("maxDashboards")).isEqualTo(10);

        // Verify tier upgrade history
        List<Map<String, Object>> tierHistory = quotaService.getTierUpgradeHistory(basicTenantId);
        assertThat(tierHistory).hasSize(1);
        assertThat(tierHistory.get(0).get("from_tier")).isEqualTo("basic");
        assertThat(tierHistory.get(0).get("to_tier")).isEqualTo("standard");
    }

    /**
     * Test 8: Concurrent quota operations
     */
    @Test
    @Order(8)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test concurrent quota operations")
    void testConcurrentQuotaOperations() throws Exception {
        log.info("Testing concurrent quota operations");

        UUID tenantId = createTestTenant("Concurrent Quota Test", "concurrent-quota");
        TenantContext.setCurrentTenant(tenantId);

        quotaService.setTenantQuotas(tenantId, Map.of("maxUsers", 20, "maxDashboards", 10));

        ExecutorService executor = Executors.newFixedThreadPool(10);
        List<CompletableFuture<Boolean>> futures = new ArrayList<>();

        // Create concurrent resource creation operations
        IntStream.range(0, 15).forEach(i -> {
            futures.add(CompletableFuture.supplyAsync(() -> {
                TenantContext.setCurrentTenant(tenantId);
                try {
                    if (quotaService.canCreateResource(tenantId, "users")) {
                        User user = createTestUser(tenantId, "concurrent" + i + "@test.com", "User", String.valueOf(i));
                        return user != null;
                    }
                    return false;
                } catch (Exception e) {
                    log.error("Concurrent quota operation failed", e);
                    return false;
                } finally {
                    TenantContext.clear();
                }
            }, executor));
        });

        // Wait for all operations to complete
        List<Boolean> results = futures.stream()
            .map(CompletableFuture::join)
            .toList();

        // Verify quota enforcement worked correctly
        long successfulCreations = results.stream().mapToLong(b -> b ? 1 : 0).sum();
        assertThat(successfulCreations).isLessThanOrEqualTo(20);

        // Verify usage tracking is accurate
        TenantContext.setCurrentTenant(tenantId);
        Map<String, Integer> finalUsage = quotaService.getTenantUsage(tenantId);
        assertThat(finalUsage.get("usedUsers")).isEqualTo((int) successfulCreations);

        executor.shutdown();
    }

    // Helper methods

    private UUID createTestTenant(String name, String subdomain) throws Exception {
        return createTestTenantWithTier(name, subdomain, "standard");
    }

    private UUID createTestTenantWithTier(String name, String subdomain, String tier) throws Exception {
        TenantProvisioningRequest request = new TenantProvisioningRequest();
        request.setName(name);
        request.setSubdomain(subdomain);
        request.setTier(tier);

        var result = tenantProvisioningService.provisionTenant(request).get();
        UUID tenantId = result.getTenantId();
        testTenantIds.add(tenantId);
        return tenantId;
    }

    private User createTestUser(UUID tenantId, String email, String firstName, String lastName) {
        TenantContext.setCurrentTenant(tenantId);
        
        User user = new User();
        user.setEmail(email);
        user.setLogin(email);
        user.setFirstName(firstName);
        user.setLastName(lastName);
        user.setTenantId(tenantId);
        user.setActivated(true);
        
        User savedUser = userRepository.save(user);
        testUserIds.add(savedUser.getId());
        return savedUser;
    }

    private UtmDashboard createTestDashboard(UUID tenantId, String name, String description) {
        TenantContext.setCurrentTenant(tenantId);
        
        UtmDashboard dashboard = new UtmDashboard();
        dashboard.setName(name);
        dashboard.setDescription(description);
        dashboard.setTenantId(tenantId);
        
        return dashboardRepository.save(dashboard);
    }

    private void cleanup() {
        try {
            TenantContext.clear();

            // Cleanup users
            for (String userId : testUserIds) {
                try {
                    userRepository.deleteById(userId);
                } catch (Exception e) {
                    log.warn("Failed to cleanup user: {}", userId, e);
                }
            }
            testUserIds.clear();

            // Cleanup tenants
            for (UUID tenantId : testTenantIds) {
                try {
                    tenantRepository.deleteById(tenantId);
                } catch (Exception e) {
                    log.warn("Failed to cleanup tenant: {}", tenantId, e);
                }
            }
            testTenantIds.clear();
        } catch (Exception e) {
            log.error("Error during cleanup", e);
        }
    }
}
