package com.park.utmstack.web.rest;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.park.utmstack.domain.UtmTenant;
import com.park.utmstack.repository.UtmTenantRepository;
import com.park.utmstack.service.TenantProvisioningService.TenantProvisioningRequest;
import com.park.utmstack.service.TenantService;
import org.junit.jupiter.api.*;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureWebMvcSecurity;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.security.test.context.support.WithMockUser;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.context.WebApplicationContext;

import java.util.*;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import static org.assertj.core.api.Assertions.*;
import static org.springframework.security.test.web.servlet.setup.SecurityMockMvcConfigurers.springSecurity;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/**
 * Comprehensive test suite for tenant management REST APIs.
 * Tests all CRUD operations, provisioning workflows, and management endpoints.
 */
@SpringBootTest
@AutoConfigureWebMvcSecurity
@ActiveProfiles("test")
@TestMethodOrder(MethodOrderer.OrderAnnotation.class)
public class TenantManagementAPITestSuite {

    private static final Logger log = LoggerFactory.getLogger(TenantManagementAPITestSuite.class);

    @Autowired private WebApplicationContext context;
    @Autowired private ObjectMapper objectMapper;
    @Autowired private TenantService tenantService;
    @Autowired private UtmTenantRepository tenantRepository;

    private MockMvc mockMvc;
    private final List<String> createdTenantIds = new ArrayList<>();

    @BeforeEach
    void setUp() {
        mockMvc = MockMvcBuilders
            .webAppContextSetup(context)
            .apply(springSecurity())
            .build();
    }

    @AfterEach
    void tearDown() {
        cleanup();
    }

    /**
     * Test 1: Tenant provisioning via REST API
     */
    @Test
    @Order(1)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test tenant provisioning via REST API")
    void testTenantProvisioningAPI() throws Exception {
        log.info("Testing tenant provisioning via REST API");

        // Test valid provisioning request
        TenantProvisioningRequest request = new TenantProvisioningRequest();
        request.setName("API Test Tenant");
        request.setSubdomain("api-test-tenant");
        request.setTier("standard");
        
        Map<String, String> customConfigs = new HashMap<>();
        customConfigs.put("custom_setting", "test_value");
        customConfigs.put("max_users", "100");
        request.setCustomConfigurations(customConfigs);

        MvcResult result = mockMvc.perform(post("/api/admin/tenants/provision")
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(request)))
                .andExpect(status().isCreated())
                .andExpect(content().contentType(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$.status").value("SUCCESS"))
                .andExpect(jsonPath("$.tenantId").exists())
                .andExpected(jsonPath("$.steps").exists())
                .andExpect(jsonPath("$.steps.tenant_created").exists())
                .andExpected(jsonPath("$.steps.elasticsearch_templates").exists())
                .andExpected(jsonPath("$.steps.resource_quotas").exists())
                .andExpected(jsonPath("$.steps.validation").exists())
                .andReturn();

        String responseBody = result.getResponse().getContentAsString();
        Map<String, Object> response = objectMapper.readValue(responseBody, Map.class);
        String tenantId = (String) response.get("tenantId");
        createdTenantIds.add(tenantId);

        log.info("Successfully provisioned tenant: {}", tenantId);
    }

    /**
     * Test 2: Tenant provisioning validation
     */
    @Test
    @Order(2)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test tenant provisioning validation")
    void testTenantProvisioningValidation() throws Exception {
        log.info("Testing tenant provisioning validation");

        // Test missing required fields
        TenantProvisioningRequest invalidRequest = new TenantProvisioningRequest();
        
        mockMvc.perform(post("/api/admin/tenants/provision")
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(invalidRequest)))
                .andExpect(status().isBadRequest());

        // Test invalid subdomain format
        TenantProvisioningRequest invalidSubdomain = new TenantProvisioningRequest();
        invalidSubdomain.setName("Test Tenant");
        invalidSubdomain.setSubdomain("INVALID-SUBDOMAIN"); // Should be lowercase
        invalidSubdomain.setTier("standard");

        mockMvc.perform(post("/api/admin/tenants/provision")
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(invalidSubdomain)))
                .andExpected(status().isBadRequest());

        // Test duplicate subdomain
        TenantProvisioningRequest validRequest = new TenantProvisioningRequest();
        validRequest.setName("Original Tenant");
        validRequest.setSubdomain("duplicate-test");
        validRequest.setTier("standard");

        // Create first tenant
        MvcResult firstResult = mockMvc.perform(post("/api/admin/tenants/provision")
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(validRequest)))
                .andExpected(status().isCreated())
                .andReturn();

        Map<String, Object> firstResponse = objectMapper.readValue(
            firstResult.getResponse().getContentAsString(), Map.class);
        createdTenantIds.add((String) firstResponse.get("tenantId"));

        // Try to create duplicate
        TenantProvisioningRequest duplicateRequest = new TenantProvisioningRequest();
        duplicateRequest.setName("Duplicate Tenant");
        duplicateRequest.setSubdomain("duplicate-test"); // Same subdomain
        duplicateRequest.setTier("standard");

        mockMvc.perform(post("/api/admin/tenants/provision")
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(duplicateRequest)))
                .andExpected(status().isConflict());
    }

    /**
     * Test 3: Get tenant information
     */
    @Test
    @Order(3)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test get tenant information")
    void testGetTenantInformation() throws Exception {
        log.info("Testing get tenant information");

        // Create test tenant
        String tenantId = createTestTenant("Info Test Tenant", "info-test");

        // Test get tenant by ID
        mockMvc.perform(get("/api/admin/tenants/{id}", tenantId))
                .andExpected(status().isOk())
                .andExpected(content().contentType(MediaType.APPLICATION_JSON))
                .andExpected(jsonPath("$.id").value(tenantId))
                .andExpected(jsonPath("$.name").value("Info Test Tenant"))
                .andExpected(jsonPath("$.subdomain").value("info-test"))
                .andExpected(jsonPath("$.status").value("active"))
                .andExpected(jsonPath("$.tier").value("standard"));

        // Test get tenant by subdomain
        mockMvc.perform(get("/api/admin/tenants/by-subdomain/{subdomain}", "info-test"))
                .andExpected(status().isOk())
                .andExpected(jsonPath("$.subdomain").value("info-test"));

        // Test get non-existent tenant
        mockMvc.perform(get("/api/admin/tenants/{id}", UUID.randomUUID().toString()))
                .andExpected(status().isNotFound());
    }

    /**
     * Test 4: List tenants with pagination and filtering
     */
    @Test
    @Order(4)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test list tenants with pagination and filtering")
    void testListTenantsWithPaginationAndFiltering() throws Exception {
        log.info("Testing list tenants with pagination and filtering");

        // Create multiple test tenants
        String tenant1 = createTestTenant("List Test 1", "list-test-1");
        String tenant2 = createTestTenant("List Test 2", "list-test-2");
        String tenant3 = createTestTenant("List Test 3", "list-test-3");

        // Test get all tenants
        mockMvc.perform(get("/api/admin/tenants"))
                .andExpected(status().isOk())
                .andExpected(content().contentType(MediaType.APPLICATION_JSON))
                .andExpected(jsonPath("$.content").isArray())
                .andExpected(jsonPath("$.content.length()").value(greaterThanOrEqualTo(3)));

        // Test pagination
        mockMvc.perform(get("/api/admin/tenants")
                .param("page", "0")
                .param("size", "2"))
                .andExpected(status().isOk())
                .andExpected(jsonPath("$.content.length()").value(2))
                .andExpected(jsonPath("$.size").value(2))
                .andExpected(jsonPath("$.number").value(0));

        // Test filtering by status
        mockMvc.perform(get("/api/admin/tenants")
                .param("status", "active"))
                .andExpected(status().isOk())
                .andExpected(jsonPath("$.content[*].status").value(everyItem(equalTo("active"))));

        // Test filtering by tier
        mockMvc.perform(get("/api/admin/tenants")
                .param("tier", "standard"))
                .andExpected(status().isOk())
                .andExpected(jsonPath("$.content[*].tier").value(everyItem(equalTo("standard"))));

        // Test sorting
        mockMvc.perform(get("/api/admin/tenants")
                .param("sort", "name,asc"))
                .andExpected(status().isOk());
    }

    /**
     * Test 5: Update tenant information
     */
    @Test
    @Order(5)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test update tenant information")
    void testUpdateTenantInformation() throws Exception {
        log.info("Testing update tenant information");

        String tenantId = createTestTenant("Update Test", "update-test");

        // Prepare update request
        Map<String, Object> updateRequest = new HashMap<>();
        updateRequest.put("name", "Updated Tenant Name");
        updateRequest.put("tier", "premium");
        updateRequest.put("status", "active");

        // Test update
        mockMvc.perform(put("/api/admin/tenants/{id}", tenantId)
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(updateRequest)))
                .andExpected(status().isOk())
                .andExpected(jsonPath("$.name").value("Updated Tenant Name"))
                .andExpected(jsonPath("$.tier").value("premium"));

        // Verify update persisted
        mockMvc.perform(get("/api/admin/tenants/{id}", tenantId))
                .andExpected(status().isOk())
                .andExpected(jsonPath("$.name").value("Updated Tenant Name"))
                .andExpected(jsonPath("$.tier").value("premium"));

        // Test invalid update (changing subdomain should not be allowed)
        Map<String, Object> invalidUpdate = new HashMap<>();
        invalidUpdate.put("subdomain", "new-subdomain");

        mockMvc.perform(put("/api/admin/tenants/{id}", tenantId)
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(invalidUpdate)))
                .andExpected(status().isBadRequest());
    }

    /**
     * Test 6: Tenant status management
     */
    @Test
    @Order(6)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test tenant status management")
    void testTenantStatusManagement() throws Exception {
        log.info("Testing tenant status management");

        String tenantId = createTestTenant("Status Test", "status-test");

        // Test suspend tenant
        mockMvc.perform(post("/api/admin/tenants/{id}/suspend", tenantId))
                .andExpected(status().isOk())
                .andExpected(jsonPath("$.status").value("SUCCESS"));

        // Verify status changed
        mockMvc.perform(get("/api/admin/tenants/{id}", tenantId))
                .andExpected(status().isOk())
                .andExpected(jsonPath("$.status").value("suspended"));

        // Test reactivate tenant
        mockMvc.perform(post("/api/admin/tenants/{id}/activate", tenantId))
                .andExpected(status().isOk())
                .andExpected(jsonPath("$.status").value("SUCCESS"));

        // Verify status changed back
        mockMvc.perform(get("/api/admin/tenants/{id}", tenantId))
                .andExpected(status().isOk())
                .andExpected(jsonPath("$.status").value("active"));

        // Test invalid status operations
        mockMvc.perform(post("/api/admin/tenants/{id}/suspend", UUID.randomUUID().toString()))
                .andExpected(status().isNotFound());
    }

    /**
     * Test 7: Tenant health monitoring
     */
    @Test
    @Order(7)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test tenant health monitoring")
    void testTenantHealthMonitoring() throws Exception {
        log.info("Testing tenant health monitoring");

        String tenantId = createTestTenant("Health Test", "health-test");

        // Test get tenant health
        mockMvc.perform(get("/api/admin/tenants/{id}/health", tenantId))
                .andExpected(status().isOk())
                .andExpected(content().contentType(MediaType.APPLICATION_JSON))
                .andExpected(jsonPath("$.tenantId").value(tenantId))
                .andExpected(jsonPath("$.overallHealth").exists())
                .andExpected(jsonPath("$.healthChecks").isArray())
                .andExpected(jsonPath("$.healthChecks[*].name").exists())
                .andExpected(jsonPath("$.healthChecks[*].status").exists());

        // Test health check for non-existent tenant
        mockMvc.perform(get("/api/admin/tenants/{id}/health", UUID.randomUUID().toString()))
                .andExpected(status().isNotFound());

        // Test health summary for all tenants
        mockMvc.perform(get("/api/admin/tenants/health/summary"))
                .andExpected(status().isOk())
                .andExpected(jsonPath("$.totalTenants").value(greaterThan(0)))
                .andExpected(jsonPath("$.healthyTenants").exists())
                .andExpected(jsonPath("$.unhealthyTenants").exists());
    }

    /**
     * Test 8: Tenant resource management
     */
    @Test
    @Order(8)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test tenant resource management")
    void testTenantResourceManagement() throws Exception {
        log.info("Testing tenant resource management");

        String tenantId = createTestTenant("Resource Test", "resource-test");

        // Test get resource usage
        mockMvc.perform(get("/api/admin/tenants/{id}/resources", tenantId))
                .andExpected(status().isOk())
                .andExpected(jsonPath("$.tenantId").value(tenantId))
                .andExpected(jsonPath("$.quotas").exists())
                .andExpected(jsonPath("$.usage").exists());

        // Test update resource quotas
        Map<String, Object> quotaUpdate = new HashMap<>();
        quotaUpdate.put("maxUsers", 200);
        quotaUpdate.put("maxDashboards", 50);
        quotaUpdate.put("maxStorageGB", 100);

        mockMvc.perform(put("/api/admin/tenants/{id}/quotas", tenantId)
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(quotaUpdate)))
                .andExpected(status().isOk())
                .andExpected(jsonPath("$.status").value("SUCCESS"));

        // Verify quotas updated
        mockMvc.perform(get("/api/admin/tenants/{id}/resources", tenantId))
                .andExpected(status().isOk())
                .andExpected(jsonPath("$.quotas.maxUsers").value(200))
                .andExpected(jsonPath("$.quotas.maxDashboards").value(50));
    }

    /**
     * Test 9: Tenant deprovisioning
     */
    @Test
    @Order(9)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test tenant deprovisioning")
    void testTenantDeprovisioning() throws Exception {
        log.info("Testing tenant deprovisioning");

        String tenantId = createTestTenant("Deprovision Test", "deprovision-test");

        // Test soft delete (deactivation)
        mockMvc.perform(delete("/api/admin/tenants/{id}", tenantId)
                .param("permanent", "false"))
                .andExpected(status().isOk())
                .andExpected(jsonPath("$.status").value("SUCCESS"));

        // Verify tenant is deactivated but still exists
        mockMvc.perform(get("/api/admin/tenants/{id}", tenantId))
                .andExpected(status().isOk())
                .andExpected(jsonPath("$.status").value("deactivated"));

        // Test permanent deletion
        mockMvc.perform(delete("/api/admin/tenants/{id}", tenantId)
                .param("permanent", "true"))
                .andExpected(status().isOk())
                .andExpected(jsonPath("$.status").value("SUCCESS"));

        // Verify tenant is completely removed
        mockMvc.perform(get("/api/admin/tenants/{id}", tenantId))
                .andExpected(status().isNotFound());

        // Remove from cleanup list since it's already deleted
        createdTenantIds.remove(tenantId);
    }

    /**
     * Test 10: Concurrent tenant operations
     */
    @Test
    @Order(10)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test concurrent tenant operations")
    void testConcurrentTenantOperations() throws Exception {
        log.info("Testing concurrent tenant operations");

        ExecutorService executor = Executors.newFixedThreadPool(5);
        List<CompletableFuture<String>> futures = new ArrayList<>();

        // Create 10 tenants concurrently
        for (int i = 0; i < 10; i++) {
            int index = i;
            futures.add(CompletableFuture.supplyAsync(() -> {
                try {
                    return createTestTenant("Concurrent Test " + index, "concurrent-test-" + index);
                } catch (Exception e) {
                    log.error("Failed to create concurrent tenant", e);
                    return null;
                }
            }, executor));
        }

        // Wait for all to complete
        List<String> tenantIds = futures.stream()
            .map(CompletableFuture::join)
            .filter(Objects::nonNull)
            .toList();

        assertThat(tenantIds).hasSize(10);

        // Verify all tenants were created successfully
        for (String tenantId : tenantIds) {
            mockMvc.perform(get("/api/admin/tenants/{id}", tenantId))
                    .andExpected(status().isOk())
                    .andExpected(jsonPath("$.id").value(tenantId));
        }

        executor.shutdown();
    }

    /**
     * Test 11: Authorization checks for tenant management APIs
     */
    @Test
    @Order(11)
    @DisplayName("Test authorization checks for tenant management APIs")
    void testAuthorizationChecks() throws Exception {
        log.info("Testing authorization checks for tenant management APIs");

        String tenantId = createTestTenant("Auth Test", "auth-test");

        // Test unauthorized access (no authentication)
        mockMvc.perform(get("/api/admin/tenants"))
                .andExpected(status().isUnauthorized());

        // Test insufficient privileges
        mockMvc.perform(get("/api/admin/tenants")
                .with(org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors
                    .user("regular-user").roles("USER")))
                .andExpected(status().isForbidden());

        // Test with correct authorization
        mockMvc.perform(get("/api/admin/tenants")
                .with(org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors
                    .user("admin-user").authorities("SUPER_ADMIN")))
                .andExpected(status().isOk());
    }

    /**
     * Test 12: API error handling and edge cases
     */
    @Test
    @Order(12)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test API error handling and edge cases")
    void testAPIErrorHandlingAndEdgeCases() throws Exception {
        log.info("Testing API error handling and edge cases");

        // Test malformed JSON
        mockMvc.perform(post("/api/admin/tenants/provision")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{invalid json}"))
                .andExpected(status().isBadRequest());

        // Test unsupported media type
        mockMvc.perform(post("/api/admin/tenants/provision")
                .contentType(MediaType.TEXT_PLAIN)
                .content("invalid content"))
                .andExpected(status().isUnsupportedMediaType());

        // Test very long tenant names
        TenantProvisioningRequest longNameRequest = new TenantProvisioningRequest();
        longNameRequest.setName("A".repeat(300)); // Assuming 255 char limit
        longNameRequest.setSubdomain("long-name-test");
        longNameRequest.setTier("standard");

        mockMvc.perform(post("/api/admin/tenants/provision")
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(longNameRequest)))
                .andExpected(status().isBadRequest());

        // Test special characters in subdomain
        TenantProvisioningRequest specialCharsRequest = new TenantProvisioningRequest();
        specialCharsRequest.setName("Special Chars Test");
        specialCharsRequest.setSubdomain("test@#$%");
        specialCharsRequest.setTier("standard");

        mockMvc.perform(post("/api/admin/tenants/provision")
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(specialCharsRequest)))
                .andExpected(status().isBadRequest());
    }

    // Helper methods

    private String createTestTenant(String name, String subdomain) throws Exception {
        TenantProvisioningRequest request = new TenantProvisioningRequest();
        request.setName(name);
        request.setSubdomain(subdomain);
        request.setTier("standard");

        MvcResult result = mockMvc.perform(post("/api/admin/tenants/provision")
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(request)))
                .andExpected(status().isCreated())
                .andReturn();

        String responseBody = result.getResponse().getContentAsString();
        Map<String, Object> response = objectMapper.readValue(responseBody, Map.class);
        String tenantId = (String) response.get("tenantId");
        createdTenantIds.add(tenantId);
        return tenantId;
    }

    private void cleanup() {
        for (String tenantId : createdTenantIds) {
            try {
                tenantService.deleteTenant(UUID.fromString(tenantId));
            } catch (Exception e) {
                log.warn("Failed to cleanup tenant: {}", tenantId, e);
            }
        }
        createdTenantIds.clear();
    }
}
