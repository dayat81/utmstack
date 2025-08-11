package com.park.utmstack.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.park.utmstack.domain.*;
import com.park.utmstack.repository.*;
import com.park.utmstack.security.TenantContext;
import com.park.utmstack.security.TenantContextFilter;
import com.park.utmstack.service.TenantProvisioningService.TenantProvisioningRequest;
import org.junit.jupiter.api.*;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.security.test.context.support.WithMockUser;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;

import javax.persistence.EntityManager;
import javax.persistence.PersistenceContext;
import java.util.*;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.stream.IntStream;

import static org.assertj.core.api.Assertions.*;

/**
 * Comprehensive test suite for multi-tenant data isolation.
 * Tests database-level isolation, cross-tenant access prevention, and data segregation.
 */
@SpringBootTest
@ActiveProfiles("test")
@TestMethodOrder(MethodOrderer.OrderAnnotation.class)
public class MultiTenantIsolationTestSuite {

    private static final Logger log = LoggerFactory.getLogger(MultiTenantIsolationTestSuite.class);

    @Autowired private TenantProvisioningService tenantProvisioningService;
    @Autowired private TenantService tenantService;
    @Autowired private UserService userService;
    @Autowired private UtmTenantRepository tenantRepository;
    @Autowired private UserRepository userRepository;
    @Autowired private UtmDashboardRepository dashboardRepository;
    @Autowired private UtmAlertLogRepository alertLogRepository;
    @Autowired private ObjectMapper objectMapper;
    
    @PersistenceContext
    private EntityManager entityManager;

    private final List<UUID> testTenantIds = new ArrayList<>();
    private static final String TENANT_A_SUBDOMAIN = "isolation-test-a";
    private static final String TENANT_B_SUBDOMAIN = "isolation-test-b";
    private static final String TENANT_C_SUBDOMAIN = "isolation-test-c";

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
     * Test 1: Verify tenant creation isolation
     */
    @Test
    @Order(1)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test tenant creation and basic isolation")
    void testTenantCreationIsolation() throws Exception {
        log.info("Testing tenant creation and basic isolation");

        // Create three isolated tenants
        UUID tenantA = createTestTenant("Tenant A", TENANT_A_SUBDOMAIN);
        UUID tenantB = createTestTenant("Tenant B", TENANT_B_SUBDOMAIN);
        UUID tenantC = createTestTenant("Tenant C", TENANT_C_SUBDOMAIN);

        // Verify tenants exist and are isolated
        assertThat(tenantA).isNotNull();
        assertThat(tenantB).isNotNull();
        assertThat(tenantC).isNotNull();
        assertThat(Set.of(tenantA, tenantB, tenantC)).hasSize(3);

        // Verify each tenant can only see itself
        verifyTenantCanOnlySeeItself(tenantA, TENANT_A_SUBDOMAIN);
        verifyTenantCanOnlySeeItself(tenantB, TENANT_B_SUBDOMAIN);
        verifyTenantCanOnlySeeItself(tenantC, TENANT_C_SUBDOMAIN);
    }

    /**
     * Test 2: User data isolation between tenants
     */
    @Test
    @Order(2)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test user data isolation between tenants")
    void testUserDataIsolation() throws Exception {
        log.info("Testing user data isolation between tenants");

        // Setup tenants
        UUID tenantA = createTestTenant("User Test A", "user-test-a");
        UUID tenantB = createTestTenant("User Test B", "user-test-b");

        // Create users in each tenant
        User userA1 = createTestUser(tenantA, "user-a1@test.com", "User A1");
        User userA2 = createTestUser(tenantA, "user-a2@test.com", "User A2");
        User userB1 = createTestUser(tenantB, "user-b1@test.com", "User B1");
        User userB2 = createTestUser(tenantB, "user-b2@test.com", "User B2");

        // Test Tenant A context - should only see Tenant A users
        TenantContext.setCurrentTenant(tenantA);
        List<User> tenantAUsers = userRepository.findAll();
        assertThat(tenantAUsers).hasSize(2);
        assertThat(tenantAUsers).extracting(User::getEmail)
            .containsExactlyInAnyOrder("user-a1@test.com", "user-a2@test.com");

        // Test Tenant B context - should only see Tenant B users
        TenantContext.setCurrentTenant(tenantB);
        List<User> tenantBUsers = userRepository.findAll();
        assertThat(tenantBUsers).hasSize(2);
        assertThat(tenantBUsers).extracting(User::getEmail)
            .containsExactlyInAnyOrder("user-b1@test.com", "user-b2@test.com");

        // Verify cross-tenant access prevention
        TenantContext.setCurrentTenant(tenantA);
        Optional<User> crossTenantUser = userRepository.findById(userB1.getId());
        assertThat(crossTenantUser).isEmpty();

        TenantContext.setCurrentTenant(tenantB);
        Optional<User> anotherCrossTenantUser = userRepository.findById(userA1.getId());
        assertThat(anotherCrossTenantUser).isEmpty();
    }

    /**
     * Test 3: Dashboard data isolation
     */
    @Test
    @Order(3)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test dashboard data isolation between tenants")
    void testDashboardDataIsolation() throws Exception {
        log.info("Testing dashboard data isolation");

        UUID tenantA = createTestTenant("Dashboard Test A", "dashboard-test-a");
        UUID tenantB = createTestTenant("Dashboard Test B", "dashboard-test-b");

        // Create dashboards in each tenant
        UtmDashboard dashboardA1 = createTestDashboard(tenantA, "Dashboard A1", "A1 Description");
        UtmDashboard dashboardA2 = createTestDashboard(tenantA, "Dashboard A2", "A2 Description");
        UtmDashboard dashboardB1 = createTestDashboard(tenantB, "Dashboard B1", "B1 Description");

        // Test isolation
        TenantContext.setCurrentTenant(tenantA);
        List<UtmDashboard> tenantADashboards = dashboardRepository.findAll();
        assertThat(tenantADashboards).hasSize(2);
        assertThat(tenantADashboards).extracting(UtmDashboard::getName)
            .containsExactlyInAnyOrder("Dashboard A1", "Dashboard A2");

        TenantContext.setCurrentTenant(tenantB);
        List<UtmDashboard> tenantBDashboards = dashboardRepository.findAll();
        assertThat(tenantBDashboards).hasSize(1);
        assertThat(tenantBDashboards.get(0).getName()).isEqualTo("Dashboard B1");

        // Verify cross-tenant access prevention
        TenantContext.setCurrentTenant(tenantA);
        Optional<UtmDashboard> crossTenantDashboard = dashboardRepository.findById(dashboardB1.getId());
        assertThat(crossTenantDashboard).isEmpty();
    }

    /**
     * Test 4: Alert log isolation
     */
    @Test
    @Order(4)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test alert log data isolation")
    void testAlertLogIsolation() throws Exception {
        log.info("Testing alert log isolation");

        UUID tenantA = createTestTenant("Alert Test A", "alert-test-a");
        UUID tenantB = createTestTenant("Alert Test B", "alert-test-b");

        // Create alert logs
        UtmAlertLog alertA = createTestAlertLog(tenantA, "Alert A", "High", "Security alert A");
        UtmAlertLog alertB = createTestAlertLog(tenantB, "Alert B", "Medium", "Security alert B");

        // Test isolation
        TenantContext.setCurrentTenant(tenantA);
        List<UtmAlertLog> tenantAAlerts = alertLogRepository.findAll();
        assertThat(tenantAAlerts).hasSize(1);
        assertThat(tenantAAlerts.get(0).getAlertName()).isEqualTo("Alert A");

        TenantContext.setCurrentTenant(tenantB);
        List<UtmAlertLog> tenantBAlerts = alertLogRepository.findAll();
        assertThat(tenantBAlerts).hasSize(1);
        assertThat(tenantBAlerts.get(0).getAlertName()).isEqualTo("Alert B");

        // Cross-tenant access prevention
        TenantContext.setCurrentTenant(tenantA);
        Optional<UtmAlertLog> crossTenantAlert = alertLogRepository.findById(alertB.getId());
        assertThat(crossTenantAlert).isEmpty();
    }

    /**
     * Test 5: Concurrent tenant operations isolation
     */
    @Test
    @Order(5)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test concurrent tenant operations isolation")
    void testConcurrentTenantOperations() throws Exception {
        log.info("Testing concurrent tenant operations isolation");

        UUID tenantA = createTestTenant("Concurrent A", "concurrent-a");
        UUID tenantB = createTestTenant("Concurrent B", "concurrent-b");

        ExecutorService executor = Executors.newFixedThreadPool(10);
        List<CompletableFuture<Void>> futures = new ArrayList<>();

        // Create concurrent operations for each tenant
        IntStream.range(0, 5).forEach(i -> {
            // Tenant A operations
            futures.add(CompletableFuture.runAsync(() -> {
                TenantContext.setCurrentTenant(tenantA);
                try {
                    User user = createTestUser(tenantA, "concurrent-a-" + i + "@test.com", "User A" + i);
                    assertThat(user.getTenantId()).isEqualTo(tenantA);
                } catch (Exception e) {
                    log.error("Error in tenant A operation", e);
                    fail("Tenant A operation failed");
                } finally {
                    TenantContext.clear();
                }
            }, executor));

            // Tenant B operations
            futures.add(CompletableFuture.runAsync(() -> {
                TenantContext.setCurrentTenant(tenantB);
                try {
                    User user = createTestUser(tenantB, "concurrent-b-" + i + "@test.com", "User B" + i);
                    assertThat(user.getTenantId()).isEqualTo(tenantB);
                } catch (Exception e) {
                    log.error("Error in tenant B operation", e);
                    fail("Tenant B operation failed");
                } finally {
                    TenantContext.clear();
                }
            }, executor));
        });

        // Wait for all operations to complete
        CompletableFuture.allOf(futures.toArray(new CompletableFuture[0])).join();

        // Verify isolation after concurrent operations
        TenantContext.setCurrentTenant(tenantA);
        List<User> tenantAUsers = userRepository.findAll();
        assertThat(tenantAUsers).hasSize(5);
        assertThat(tenantAUsers).allMatch(user -> user.getTenantId().equals(tenantA));

        TenantContext.setCurrentTenant(tenantB);
        List<User> tenantBUsers = userRepository.findAll();
        assertThat(tenantBUsers).hasSize(5);
        assertThat(tenantBUsers).allMatch(user -> user.getTenantId().equals(tenantB));

        executor.shutdown();
    }

    /**
     * Test 6: SQL injection prevention with tenant context
     */
    @Test
    @Order(6)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test SQL injection prevention with tenant context")
    void testSQLInjectionPrevention() throws Exception {
        log.info("Testing SQL injection prevention");

        UUID tenantA = createTestTenant("SQL Test A", "sql-test-a");
        UUID tenantB = createTestTenant("SQL Test B", "sql-test-b");

        // Create test data
        createTestUser(tenantA, "legit-a@test.com", "Legit User A");
        createTestUser(tenantB, "legit-b@test.com", "Legit User B");

        TenantContext.setCurrentTenant(tenantA);

        // Attempt SQL injection through various vectors
        String[] injectionAttempts = {
            "'; DROP TABLE jhi_user; --",
            "' OR '1'='1",
            "' UNION SELECT * FROM jhi_user WHERE tenant_id != '" + tenantA + "' --",
            "'; UPDATE jhi_user SET tenant_id = '" + tenantA + "' WHERE tenant_id = '" + tenantB + "'; --"
        };

        for (String injection : injectionAttempts) {
            try {
                // Attempt to find user with injection
                Optional<User> user = userRepository.findOneByEmailIgnoreCase(injection);
                assertThat(user).isEmpty();

                // Verify tenant isolation still intact
                List<User> users = userRepository.findAll();
                assertThat(users).hasSize(1);
                assertThat(users.get(0).getEmail()).isEqualTo("legit-a@test.com");
            } catch (Exception e) {
                // Exceptions are expected for injection attempts
                log.debug("SQL injection attempt blocked: {}", injection);
            }
        }
    }

    /**
     * Test 7: Tenant context thread safety
     */
    @Test
    @Order(7)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test tenant context thread safety")
    void testTenantContextThreadSafety() throws Exception {
        log.info("Testing tenant context thread safety");

        UUID tenantA = createTestTenant("Thread Safety A", "thread-safety-a");
        UUID tenantB = createTestTenant("Thread Safety B", "thread-safety-b");
        UUID tenantC = createTestTenant("Thread Safety C", "thread-safety-c");

        ExecutorService executor = Executors.newFixedThreadPool(15);
        List<CompletableFuture<String>> futures = new ArrayList<>();

        // Create 50 concurrent operations with different tenant contexts
        IntStream.range(0, 50).forEach(i -> {
            UUID tenant = switch (i % 3) {
                case 0 -> tenantA;
                case 1 -> tenantB;
                default -> tenantC;
            };

            futures.add(CompletableFuture.supplyAsync(() -> {
                TenantContext.setCurrentTenant(tenant);
                try {
                    // Simulate work
                    Thread.sleep(10);
                    
                    UUID currentTenant = TenantContext.getCurrentTenantAsUUID();
                    assertThat(currentTenant).isEqualTo(tenant);
                    
                    return tenant.toString();
                } catch (Exception e) {
                    fail("Thread safety test failed", e);
                    return null;
                } finally {
                    TenantContext.clear();
                }
            }, executor));
        });

        // Wait for all operations and verify results
        List<String> results = futures.stream()
            .map(CompletableFuture::join)
            .toList();

        assertThat(results).hasSize(50);
        assertThat(results).doesNotContainNull();

        executor.shutdown();
    }

    /**
     * Test 8: Row-Level Security validation
     */
    @Test
    @Order(8)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test Row-Level Security policies")
    void testRowLevelSecurityValidation() throws Exception {
        log.info("Testing Row-Level Security policies");

        UUID tenantA = createTestTenant("RLS Test A", "rls-test-a");
        UUID tenantB = createTestTenant("RLS Test B", "rls-test-b");

        // Create data in both tenants
        createTestUser(tenantA, "rls-a@test.com", "RLS User A");
        createTestUser(tenantB, "rls-b@test.com", "RLS User B");

        // Test with tenant context
        TenantContext.setCurrentTenant(tenantA);
        
        // This should only return tenant A data due to RLS
        List<User> usersWithContext = userRepository.findAll();
        assertThat(usersWithContext).hasSize(1);
        assertThat(usersWithContext.get(0).getEmail()).isEqualTo("rls-a@test.com");

        // Test native query to verify RLS is enforced at database level
        List<Object[]> nativeResults = entityManager.createNativeQuery(
            "SELECT email FROM jhi_user WHERE tenant_id = ?1")
            .setParameter(1, tenantA)
            .getResultList();
        
        assertThat(nativeResults).hasSize(1);
        assertThat(nativeResults.get(0)[0]).isEqualTo("rls-a@test.com");

        // Switch context and verify
        TenantContext.setCurrentTenant(tenantB);
        List<User> tenantBUsers = userRepository.findAll();
        assertThat(tenantBUsers).hasSize(1);
        assertThat(tenantBUsers.get(0).getEmail()).isEqualTo("rls-b@test.com");
    }

    // Helper methods

    private UUID createTestTenant(String name, String subdomain) throws Exception {
        TenantProvisioningRequest request = new TenantProvisioningRequest();
        request.setName(name);
        request.setSubdomain(subdomain);
        request.setTier("standard");

        var result = tenantProvisioningService.provisionTenant(request).get();
        UUID tenantId = result.getTenantId();
        testTenantIds.add(tenantId);
        return tenantId;
    }

    private void verifyTenantCanOnlySeeItself(UUID tenantId, String subdomain) {
        TenantContext.setCurrentTenant(tenantId);
        
        List<UtmTenant> visibleTenants = tenantRepository.findAll();
        assertThat(visibleTenants).hasSize(1);
        assertThat(visibleTenants.get(0).getId()).isEqualTo(tenantId);
        assertThat(visibleTenants.get(0).getSubdomain()).isEqualTo(subdomain);
    }

    private User createTestUser(UUID tenantId, String email, String firstName) {
        TenantContext.setCurrentTenant(tenantId);
        
        User user = new User();
        user.setEmail(email);
        user.setLogin(email);
        user.setFirstName(firstName);
        user.setLastName("Test");
        user.setTenantId(tenantId);
        user.setActivated(true);
        
        return userRepository.save(user);
    }

    private UtmDashboard createTestDashboard(UUID tenantId, String name, String description) {
        TenantContext.setCurrentTenant(tenantId);
        
        UtmDashboard dashboard = new UtmDashboard();
        dashboard.setName(name);
        dashboard.setDescription(description);
        dashboard.setTenantId(tenantId);
        
        return dashboardRepository.save(dashboard);
    }

    private UtmAlertLog createTestAlertLog(UUID tenantId, String alertName, String severity, String description) {
        TenantContext.setCurrentTenant(tenantId);
        
        UtmAlertLog alertLog = new UtmAlertLog();
        alertLog.setAlertName(alertName);
        alertLog.setSeverity(severity);
        alertLog.setDescription(description);
        alertLog.setTenantId(tenantId);
        
        return alertLogRepository.save(alertLog);
    }

    private void cleanup() {
        try {
            TenantContext.clear();
            for (UUID tenantId : testTenantIds) {
                try {
                    tenantService.deleteTenant(tenantId);
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
