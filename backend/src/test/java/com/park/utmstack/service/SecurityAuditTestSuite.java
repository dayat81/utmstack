package com.park.utmstack.service;

import com.park.utmstack.domain.User;
import com.park.utmstack.domain.UtmTenant;
import com.park.utmstack.domain.SecurityAuditEvent;
import com.park.utmstack.repository.SecurityAuditEventRepository;
import com.park.utmstack.repository.UserRepository;
import com.park.utmstack.repository.UtmTenantRepository;
import com.park.utmstack.security.TenantContext;
import com.park.utmstack.service.TenantProvisioningService.TenantProvisioningRequest;
import org.junit.jupiter.api.*;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.security.test.context.support.WithMockUser;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.*;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.stream.IntStream;

import static org.assertj.core.api.Assertions.*;

/**
 * Comprehensive test suite for security audit logging and monitoring.
 * Tests audit event creation, filtering, and security event detection.
 */
@SpringBootTest
@ActiveProfiles("test")
@TestMethodOrder(MethodOrderer.OrderAnnotation.class)
public class SecurityAuditTestSuite {

    private static final Logger log = LoggerFactory.getLogger(SecurityAuditTestSuite.class);

    @Autowired private SecurityAuditService securityAuditService;
    @Autowired private TenantProvisioningService tenantProvisioningService;
    @Autowired private UserService userService;
    @Autowired private SecurityAuditEventRepository auditEventRepository;
    @Autowired private UtmTenantRepository tenantRepository;
    @Autowired private UserRepository userRepository;

    private final List<UUID> testTenantIds = new ArrayList<>();
    private final List<String> testUserIds = new ArrayList<>();
    private final List<Long> testAuditEventIds = new ArrayList<>();

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
     * Test 1: Basic audit event creation
     */
    @Test
    @Order(1)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test basic audit event creation")
    void testBasicAuditEventCreation() throws Exception {
        log.info("Testing basic audit event creation");

        UUID tenantId = createTestTenant("Audit Test", "audit-test");
        User user = createTestUser(tenantId, "audit@test.com", "Audit", "User");

        TenantContext.setCurrentTenant(tenantId);

        // Test different types of audit events
        Map<String, Object> metadata = new HashMap<>();
        metadata.put("ip_address", "192.168.1.1");
        metadata.put("user_agent", "Test Browser");

        // Authentication events
        SecurityAuditEvent loginEvent = securityAuditService.createAuditEvent(
            SecurityAuditService.EventType.USER_LOGIN,
            user.getId(),
            "User logged in successfully",
            metadata
        );
        testAuditEventIds.add(loginEvent.getId());

        assertThat(loginEvent).isNotNull();
        assertThat(loginEvent.getEventType()).isEqualTo(SecurityAuditService.EventType.USER_LOGIN.name());
        assertThat(loginEvent.getTenantId()).isEqualTo(tenantId);
        assertThat(loginEvent.getUserId()).isEqualTo(user.getId());
        assertThat(loginEvent.getMetadata()).contains("ip_address");

        // Authorization events
        SecurityAuditEvent authFailEvent = securityAuditService.createAuditEvent(
            SecurityAuditService.EventType.AUTHORIZATION_FAILURE,
            user.getId(),
            "Access denied to restricted resource",
            metadata
        );
        testAuditEventIds.add(authFailEvent.getId());

        assertThat(authFailEvent.getEventType()).isEqualTo(SecurityAuditService.EventType.AUTHORIZATION_FAILURE.name());
        assertThat(authFailEvent.getSeverity()).isEqualTo("MEDIUM");

        // Data access events
        SecurityAuditEvent dataAccessEvent = securityAuditService.createAuditEvent(
            SecurityAuditService.EventType.DATA_ACCESS,
            user.getId(),
            "User accessed sensitive data",
            Map.of("resource", "user_list", "action", "read")
        );
        testAuditEventIds.add(dataAccessEvent.getId());

        assertThat(dataAccessEvent.getEventType()).isEqualTo(SecurityAuditService.EventType.DATA_ACCESS.name());
    }

    /**
     * Test 2: Tenant isolation in audit events
     */
    @Test
    @Order(2)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test tenant isolation in audit events")
    void testTenantIsolationInAuditEvents() throws Exception {
        log.info("Testing tenant isolation in audit events");

        UUID tenantA = createTestTenant("Audit Tenant A", "audit-tenant-a");
        UUID tenantB = createTestTenant("Audit Tenant B", "audit-tenant-b");

        User userA = createTestUser(tenantA, "usera@test.com", "User", "A");
        User userB = createTestUser(tenantB, "userb@test.com", "User", "B");

        // Create events in tenant A
        TenantContext.setCurrentTenant(tenantA);
        SecurityAuditEvent eventA1 = securityAuditService.createAuditEvent(
            SecurityAuditService.EventType.USER_LOGIN,
            userA.getId(),
            "User A login",
            Map.of("tenant", "A")
        );
        SecurityAuditEvent eventA2 = securityAuditService.createAuditEvent(
            SecurityAuditService.EventType.DATA_ACCESS,
            userA.getId(),
            "User A data access",
            Map.of("tenant", "A")
        );
        testAuditEventIds.addAll(List.of(eventA1.getId(), eventA2.getId()));

        // Create events in tenant B
        TenantContext.setCurrentTenant(tenantB);
        SecurityAuditEvent eventB1 = securityAuditService.createAuditEvent(
            SecurityAuditService.EventType.USER_LOGIN,
            userB.getId(),
            "User B login",
            Map.of("tenant", "B")
        );
        testAuditEventIds.add(eventB1.getId());

        // Verify tenant A can only see its events
        TenantContext.setCurrentTenant(tenantA);
        List<SecurityAuditEvent> tenantAEvents = auditEventRepository.findAll();
        assertThat(tenantAEvents).hasSize(2);
        assertThat(tenantAEvents).allMatch(event -> event.getTenantId().equals(tenantA));
        assertThat(tenantAEvents).extracting(SecurityAuditEvent::getDescription)
            .containsExactlyInAnyOrder("User A login", "User A data access");

        // Verify tenant B can only see its events
        TenantContext.setCurrentTenant(tenantB);
        List<SecurityAuditEvent> tenantBEvents = auditEventRepository.findAll();
        assertThat(tenantBEvents).hasSize(1);
        assertThat(tenantBEvents.get(0).getTenantId()).isEqualTo(tenantB);
        assertThat(tenantBEvents.get(0).getDescription()).isEqualTo("User B login");

        // Verify cross-tenant access prevention
        TenantContext.setCurrentTenant(tenantA);
        Optional<SecurityAuditEvent> crossTenantEvent = auditEventRepository.findById(eventB1.getId());
        assertThat(crossTenantEvent).isEmpty();
    }

    /**
     * Test 3: Security event detection and alerting
     */
    @Test
    @Order(3)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test security event detection and alerting")
    void testSecurityEventDetectionAndAlerting() throws Exception {
        log.info("Testing security event detection and alerting");

        UUID tenantId = createTestTenant("Security Detection Test", "security-detection");
        User user = createTestUser(tenantId, "security@test.com", "Security", "User");

        TenantContext.setCurrentTenant(tenantId);

        // Test suspicious login patterns
        Map<String, Object> suspiciousMetadata = new HashMap<>();
        suspiciousMetadata.put("ip_address", "192.168.1.100");
        suspiciousMetadata.put("failed_attempts", 5);
        suspiciousMetadata.put("time_window_minutes", 1);

        SecurityAuditEvent suspiciousLogin = securityAuditService.createSecurityAlert(
            SecurityAuditService.EventType.AUTHENTICATION_FAILURE,
            user.getId(),
            "Multiple failed login attempts detected",
            suspiciousMetadata,
            "HIGH"
        );
        testAuditEventIds.add(suspiciousLogin.getId());

        assertThat(suspiciousLogin.getSeverity()).isEqualTo("HIGH");
        assertThat(suspiciousLogin.getMetadata()).contains("failed_attempts");

        // Test data breach indicators
        Map<String, Object> breachMetadata = new HashMap<>();
        breachMetadata.put("data_volume", "1000000");
        breachMetadata.put("access_time", "02:30:00");
        breachMetadata.put("unusual_pattern", true);

        SecurityAuditEvent breachEvent = securityAuditService.createSecurityAlert(
            SecurityAuditService.EventType.DATA_BREACH_ATTEMPT,
            user.getId(),
            "Unusual data access pattern detected",
            breachMetadata,
            "CRITICAL"
        );
        testAuditEventIds.add(breachEvent.getId());

        assertThat(breachEvent.getSeverity()).isEqualTo("CRITICAL");

        // Test privilege escalation detection
        SecurityAuditEvent privilegeEvent = securityAuditService.createSecurityAlert(
            SecurityAuditService.EventType.PRIVILEGE_ESCALATION,
            user.getId(),
            "Unauthorized privilege escalation attempt",
            Map.of("attempted_role", "ADMIN", "current_role", "USER"),
            "HIGH"
        );
        testAuditEventIds.add(privilegeEvent.getId());

        // Verify security alerts are properly flagged
        List<SecurityAuditEvent> securityAlerts = securityAuditService.findSecurityAlerts(
            tenantId, Instant.now().minus(1, ChronoUnit.HOURS), Instant.now()
        );

        assertThat(securityAlerts).hasSize(3);
        assertThat(securityAlerts).extracting(SecurityAuditEvent::getSeverity)
            .containsExactlyInAnyOrder("HIGH", "CRITICAL", "HIGH");
    }

    /**
     * Test 4: Audit event search and filtering
     */
    @Test
    @Order(4)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test audit event search and filtering")
    void testAuditEventSearchAndFiltering() throws Exception {
        log.info("Testing audit event search and filtering");

        UUID tenantId = createTestTenant("Search Test", "search-test");
        User user1 = createTestUser(tenantId, "user1@test.com", "User", "One");
        User user2 = createTestUser(tenantId, "user2@test.com", "User", "Two");

        TenantContext.setCurrentTenant(tenantId);

        // Create various audit events
        Instant baseTime = Instant.now().minus(1, ChronoUnit.HOURS);
        
        SecurityAuditEvent event1 = securityAuditService.createAuditEvent(
            SecurityAuditService.EventType.USER_LOGIN,
            user1.getId(),
            "User 1 login",
            Map.of("ip", "192.168.1.1")
        );
        
        SecurityAuditEvent event2 = securityAuditService.createAuditEvent(
            SecurityAuditService.EventType.DATA_ACCESS,
            user2.getId(),
            "User 2 data access",
            Map.of("resource", "dashboards")
        );
        
        SecurityAuditEvent event3 = securityAuditService.createSecurityAlert(
            SecurityAuditService.EventType.AUTHORIZATION_FAILURE,
            user1.getId(),
            "Authorization failed",
            Map.of("resource", "admin_panel"),
            "MEDIUM"
        );

        testAuditEventIds.addAll(List.of(event1.getId(), event2.getId(), event3.getId()));

        // Test filtering by event type
        List<SecurityAuditEvent> loginEvents = securityAuditService.findEventsByType(
            tenantId, SecurityAuditService.EventType.USER_LOGIN, baseTime, Instant.now()
        );
        assertThat(loginEvents).hasSize(1);
        assertThat(loginEvents.get(0).getDescription()).isEqualTo("User 1 login");

        // Test filtering by user
        List<SecurityAuditEvent> user1Events = securityAuditService.findEventsByUser(
            tenantId, user1.getId(), baseTime, Instant.now()
        );
        assertThat(user1Events).hasSize(2);
        assertThat(user1Events).extracting(SecurityAuditEvent::getEventType)
            .containsExactlyInAnyOrder("USER_LOGIN", "AUTHORIZATION_FAILURE");

        // Test filtering by severity
        List<SecurityAuditEvent> mediumEvents = securityAuditService.findEventsBySeverity(
            tenantId, "MEDIUM", baseTime, Instant.now()
        );
        assertThat(mediumEvents).hasSize(1);
        assertThat(mediumEvents.get(0).getEventType()).isEqualTo("AUTHORIZATION_FAILURE");

        // Test time range filtering
        Instant midTime = baseTime.plus(30, ChronoUnit.MINUTES);
        List<SecurityAuditEvent> recentEvents = securityAuditService.findEventsByTimeRange(
            tenantId, midTime, Instant.now()
        );
        assertThat(recentEvents).hasSizeGreaterThanOrEqualTo(3);
    }

    /**
     * Test 5: Compliance audit reporting
     */
    @Test
    @Order(5)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test compliance audit reporting")
    void testComplianceAuditReporting() throws Exception {
        log.info("Testing compliance audit reporting");

        UUID tenantId = createTestTenant("Compliance Test", "compliance-test");
        User user = createTestUser(tenantId, "compliance@test.com", "Compliance", "User");

        TenantContext.setCurrentTenant(tenantId);

        // Create compliance-relevant events
        SecurityAuditEvent dataAccessEvent = securityAuditService.createAuditEvent(
            SecurityAuditService.EventType.DATA_ACCESS,
            user.getId(),
            "PII data accessed",
            Map.of("data_type", "PII", "record_count", 100, "purpose", "user_management")
        );

        SecurityAuditEvent dataExportEvent = securityAuditService.createAuditEvent(
            SecurityAuditService.EventType.DATA_EXPORT,
            user.getId(),
            "Customer data exported",
            Map.of("export_format", "CSV", "record_count", 1000, "destination", "email")
        );

        SecurityAuditEvent configChangeEvent = securityAuditService.createAuditEvent(
            SecurityAuditService.EventType.CONFIGURATION_CHANGE,
            user.getId(),
            "Security settings modified",
            Map.of("setting", "password_policy", "old_value", "basic", "new_value", "strict")
        );

        testAuditEventIds.addAll(List.of(
            dataAccessEvent.getId(),
            dataExportEvent.getId(),
            configChangeEvent.getId()
        ));

        // Generate compliance report
        Map<String, Object> complianceReport = securityAuditService.generateComplianceReport(
            tenantId,
            Instant.now().minus(1, ChronoUnit.HOURS),
            Instant.now(),
            List.of("GDPR", "SOX", "HIPAA")
        );

        assertThat(complianceReport).isNotNull();
        assertThat(complianceReport.get("tenant_id")).isEqualTo(tenantId.toString());
        assertThat(complianceReport.get("total_events")).isNotNull();
        assertThat(complianceReport.get("data_access_events")).isNotNull();
        assertThat(complianceReport.get("export_events")).isNotNull();
        assertThat(complianceReport.get("configuration_changes")).isNotNull();

        // Test GDPR-specific reporting
        Map<String, Object> gdprReport = securityAuditService.generateGDPRReport(
            tenantId,
            Instant.now().minus(1, ChronoUnit.HOURS),
            Instant.now()
        );

        assertThat(gdprReport).containsKeys("personal_data_access", "data_exports", "consent_changes");
    }

    /**
     * Test 6: Real-time security monitoring
     */
    @Test
    @Order(6)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test real-time security monitoring")
    void testRealTimeSecurityMonitoring() throws Exception {
        log.info("Testing real-time security monitoring");

        UUID tenantId = createTestTenant("Monitoring Test", "monitoring-test");
        User user = createTestUser(tenantId, "monitor@test.com", "Monitor", "User");

        TenantContext.setCurrentTenant(tenantId);

        // Test threshold-based alerting
        // Simulate multiple failed login attempts
        for (int i = 0; i < 6; i++) {
            SecurityAuditEvent failedLogin = securityAuditService.createAuditEvent(
                SecurityAuditService.EventType.AUTHENTICATION_FAILURE,
                user.getId(),
                "Failed login attempt " + (i + 1),
                Map.of("ip_address", "192.168.1.100", "attempt_number", i + 1)
            );
            testAuditEventIds.add(failedLogin.getId());
        }

        // Check if security threshold was triggered
        boolean thresholdTriggered = securityAuditService.checkSecurityThresholds(
            tenantId,
            SecurityAuditService.EventType.AUTHENTICATION_FAILURE,
            Instant.now().minus(5, ChronoUnit.MINUTES),
            5
        );

        assertThat(thresholdTriggered).isTrue();

        // Test anomaly detection
        // Simulate unusual access pattern
        for (int i = 0; i < 3; i++) {
            SecurityAuditEvent unusualAccess = securityAuditService.createAuditEvent(
                SecurityAuditService.EventType.DATA_ACCESS,
                user.getId(),
                "Unusual time access",
                Map.of("access_time", "03:00:00", "resource", "sensitive_data_" + i)
            );
            testAuditEventIds.add(unusualAccess.getId());
        }

        // Check anomaly detection
        List<SecurityAuditEvent> anomalies = securityAuditService.detectAnomalies(
            tenantId,
            Instant.now().minus(10, ChronoUnit.MINUTES),
            Instant.now()
        );

        assertThat(anomalies).isNotEmpty();
    }

    /**
     * Test 7: Concurrent audit logging
     */
    @Test
    @Order(7)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test concurrent audit logging")
    void testConcurrentAuditLogging() throws Exception {
        log.info("Testing concurrent audit logging");

        UUID tenantId = createTestTenant("Concurrent Audit Test", "concurrent-audit");
        User user = createTestUser(tenantId, "concurrent@test.com", "Concurrent", "User");

        TenantContext.setCurrentTenant(tenantId);

        ExecutorService executor = Executors.newFixedThreadPool(10);
        List<CompletableFuture<SecurityAuditEvent>> futures = new ArrayList<>();

        // Create 50 concurrent audit events
        IntStream.range(0, 50).forEach(i -> {
            futures.add(CompletableFuture.supplyAsync(() -> {
                TenantContext.setCurrentTenant(tenantId);
                try {
                    return securityAuditService.createAuditEvent(
                        SecurityAuditService.EventType.DATA_ACCESS,
                        user.getId(),
                        "Concurrent access " + i,
                        Map.of("thread", Thread.currentThread().getName(), "index", i)
                    );
                } catch (Exception e) {
                    log.error("Failed to create audit event", e);
                    return null;
                } finally {
                    TenantContext.clear();
                }
            }, executor));
        });

        // Wait for all events to be created
        List<SecurityAuditEvent> events = futures.stream()
            .map(CompletableFuture::join)
            .filter(Objects::nonNull)
            .toList();

        assertThat(events).hasSize(50);

        // Verify all events were persisted correctly
        TenantContext.setCurrentTenant(tenantId);
        List<SecurityAuditEvent> persistedEvents = auditEventRepository.findAll();
        assertThat(persistedEvents).hasSizeGreaterThanOrEqualTo(50);

        // Clean up
        testAuditEventIds.addAll(events.stream().map(SecurityAuditEvent::getId).toList());
        executor.shutdown();
    }

    /**
     * Test 8: Audit event metadata validation
     */
    @Test
    @Order(8)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test audit event metadata validation")
    void testAuditEventMetadataValidation() throws Exception {
        log.info("Testing audit event metadata validation");

        UUID tenantId = createTestTenant("Metadata Test", "metadata-test");
        User user = createTestUser(tenantId, "metadata@test.com", "Metadata", "User");

        TenantContext.setCurrentTenant(tenantId);

        // Test valid metadata
        Map<String, Object> validMetadata = new HashMap<>();
        validMetadata.put("ip_address", "192.168.1.1");
        validMetadata.put("user_agent", "Mozilla/5.0");
        validMetadata.put("session_id", UUID.randomUUID().toString());
        validMetadata.put("timestamp", Instant.now().toString());

        SecurityAuditEvent validEvent = securityAuditService.createAuditEvent(
            SecurityAuditService.EventType.USER_LOGIN,
            user.getId(),
            "Valid metadata test",
            validMetadata
        );
        testAuditEventIds.add(validEvent.getId());

        assertThat(validEvent).isNotNull();
        assertThat(validEvent.getMetadata()).contains("ip_address", "user_agent");

        // Test metadata size limits
        Map<String, Object> largeMetadata = new HashMap<>();
        largeMetadata.put("large_field", "x".repeat(10000)); // Very large string

        SecurityAuditEvent largeEvent = securityAuditService.createAuditEvent(
            SecurityAuditService.EventType.DATA_ACCESS,
            user.getId(),
            "Large metadata test",
            largeMetadata
        );
        testAuditEventIds.add(largeEvent.getId());

        // Verify the event was created (service should handle large metadata appropriately)
        assertThat(largeEvent).isNotNull();

        // Test special characters in metadata
        Map<String, Object> specialCharMetadata = new HashMap<>();
        specialCharMetadata.put("special_chars", "Test with émojis 🚀 and unicode ∑");
        specialCharMetadata.put("json_string", "{\"nested\": \"value\"}");

        SecurityAuditEvent specialEvent = securityAuditService.createAuditEvent(
            SecurityAuditService.EventType.CONFIGURATION_CHANGE,
            user.getId(),
            "Special characters test",
            specialCharMetadata
        );
        testAuditEventIds.add(specialEvent.getId());

        assertThat(specialEvent).isNotNull();
        assertThat(specialEvent.getMetadata()).contains("special_chars");
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

    private void cleanup() {
        try {
            TenantContext.clear();

            // Cleanup audit events
            for (Long eventId : testAuditEventIds) {
                try {
                    auditEventRepository.deleteById(eventId);
                } catch (Exception e) {
                    log.warn("Failed to cleanup audit event: {}", eventId, e);
                }
            }
            testAuditEventIds.clear();

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
