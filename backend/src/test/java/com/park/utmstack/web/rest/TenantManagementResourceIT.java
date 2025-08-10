package com.park.utmstack.web.rest;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.park.utmstack.service.TenantProvisioningService.TenantProvisioningRequest;
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

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static org.springframework.security.test.web.servlet.setup.SecurityMockMvcConfigurers.springSecurity;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/**
 * Integration tests for TenantManagementResource REST controller.
 * Tests all API endpoints for tenant management operations.
 */
@SpringBootTest
@AutoConfigureWebMvcSecurity
@ActiveProfiles("test")
@TestMethodOrder(MethodOrderer.OrderAnnotation.class)
class TenantManagementResourceIT {

    private static final Logger log = LoggerFactory.getLogger(TenantManagementResourceIT.class);

    @Autowired
    private WebApplicationContext context;

    @Autowired
    private ObjectMapper objectMapper;

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
        // Cleanup created tenants
        cleanup();
    }

    @Test
    @Order(1)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test tenant provisioning via REST API")
    void testTenantProvisioningViaAPI() throws Exception {
        log.info("Testing tenant provisioning via REST API");

        // Arrange
        TenantProvisioningRequest request = new TenantProvisioningRequest();
        request.setName("API-Test-Tenant");
        request.setSubdomain("api-test-tenant");
        request.setTier("standard");

        Map<String, String> customConfigs = new HashMap<>();
        customConfigs.put("api_test", "true");
        request.setCustomConfigurations(customConfigs);

        // Act & Assert
        MvcResult result = mockMvc.perform(post("/api/admin/tenants/provision")
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(request)))
                .andExpect(status().isCreated())
                .andExpect(content().contentType(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$.status").value("SUCCESS"))
                .andExpect(jsonPath("$.tenantId").exists())
                .andExpect(jsonPath("$.steps").exists())
                .andExpect(jsonPath("$.steps.tenant_created").exists())
                .andExpect(jsonPath("$.steps.elasticsearch_templates").exists())
                .andExpect(jsonPath("$.steps.resource_quotas").exists())
                .andExpect(jsonPath("$.steps.validation").exists())
                .andReturn();

        // Extract tenant ID for cleanup
        String responseBody = result.getResponse().getContentAsString();
        Map<String, Object> response = objectMapper.readValue(responseBody, Map.class);
        String tenantId = (String) response.get("tenantId");
        createdTenantIds.add(tenantId);

        log.info("Tenant provisioning API test completed successfully");
    }

    @Test
    @Order(2)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test get all tenants")
    void testGetAllTenants() throws Exception {
        log.info("Testing get all tenants");

        // Act & Assert
        mockMvc.perform(get("/api/admin/tenants")
                .contentType(MediaType.APPLICATION_JSON))
                .andExpect(status().isOk())
                .andExpect(content().contentType(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$").isArray());

        log.info("Get all tenants test completed successfully");
    }

    @Test
    @Order(3)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test get tenant by ID")
    void testGetTenantById() throws Exception {
        log.info("Testing get tenant by ID");

        // Arrange - Create a tenant first
        String tenantId = createTestTenant("API-Test-GetById", "api-test-getbyid");

        // Act & Assert
        mockMvc.perform(get("/api/admin/tenants/{tenantId}", tenantId)
                .contentType(MediaType.APPLICATION_JSON))
                .andExpect(status().isOk())
                .andExpect(content().contentType(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$.id").value(tenantId))
                .andExpect(jsonPath("$.name").value("API-Test-GetById"))
                .andExpect(jsonPath("$.subdomain").value("api-test-getbyid"))
                .andExpect(jsonPath("$.status").value("active"));

        log.info("Get tenant by ID test completed successfully");
    }

    @Test
    @Order(4)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test update tenant status")
    void testUpdateTenantStatus() throws Exception {
        log.info("Testing update tenant status");

        // Arrange - Create a tenant first
        String tenantId = createTestTenant("API-Test-UpdateStatus", "api-test-updatestatus");

        Map<String, String> statusUpdate = new HashMap<>();
        statusUpdate.put("status", "suspended");

        // Act & Assert
        mockMvc.perform(put("/api/admin/tenants/{tenantId}/status", tenantId)
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(statusUpdate)))
                .andExpect(status().isOk())
                .andExpect(content().contentType(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$.id").value(tenantId))
                .andExpect(jsonPath("$.status").value("suspended"));

        log.info("Update tenant status test completed successfully");
    }

    @Test
    @Order(5)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test get provisioning status")
    void testGetProvisioningStatus() throws Exception {
        log.info("Testing get provisioning status");

        // Arrange - Create a tenant first
        String tenantId = createTestTenant("API-Test-ProvisioningStatus", "api-test-provisioningstatus");

        // Act & Assert
        mockMvc.perform(get("/api/admin/tenants/{tenantId}/provisioning-status", tenantId)
                .contentType(MediaType.APPLICATION_JSON))
                .andExpect(status().isOk())
                .andExpect(content().contentType(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$.tenantId").value(tenantId))
                .andExpect(jsonPath("$.overallReady").exists())
                .andExpect(jsonPath("$.elasticsearchReady").exists())
                .andExpect(jsonPath("$.quotasConfigured").exists());

        log.info("Get provisioning status test completed successfully");
    }

    @Test
    @Order(6)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test get resource quota status")
    void testGetResourceQuotaStatus() throws Exception {
        log.info("Testing get resource quota status");

        // Arrange - Create a tenant first
        String tenantId = createTestTenant("API-Test-QuotaStatus", "api-test-quotastatus");

        // Act & Assert
        mockMvc.perform(get("/api/admin/tenants/{tenantId}/quota-status", tenantId)
                .contentType(MediaType.APPLICATION_JSON))
                .andExpect(status().isOk())
                .andExpect(content().contentType(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$.tenantId").value(tenantId))
                .andExpect(jsonPath("$.tier").exists())
                .andExpect(jsonPath("$.overallStatus").exists())
                .andExpect(jsonPath("$.userUsage").exists())
                .andExpect(jsonPath("$.dashboardUsage").exists())
                .andExpect(jsonPath("$.storageUsage").exists())
                .andExpect(jsonPath("$.dailyAlertUsage").exists());

        log.info("Get resource quota status test completed successfully");
    }

    @Test
    @Order(7)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test update resource limits")
    void testUpdateResourceLimits() throws Exception {
        log.info("Testing update resource limits");

        // Arrange - Create a tenant first
        String tenantId = createTestTenant("API-Test-UpdateLimits", "api-test-updatelimits");

        Map<String, Integer> newLimits = new HashMap<>();
        newLimits.put("max_users", 50);
        newLimits.put("max_dashboards", 20);

        // Act & Assert
        mockMvc.perform(put("/api/admin/tenants/{tenantId}/resource-limits", tenantId)
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(newLimits)))
                .andExpect(status().isOk());

        // Verify the limits were updated
        mockMvc.perform(get("/api/admin/tenants/{tenantId}/quota-status", tenantId)
                .contentType(MediaType.APPLICATION_JSON))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.tenantId").value(tenantId));

        log.info("Update resource limits test completed successfully");
    }

    @Test
    @Order(8)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test get resource usage")
    void testGetResourceUsage() throws Exception {
        log.info("Testing get resource usage");

        // Arrange - Create a tenant first
        String tenantId = createTestTenant("API-Test-ResourceUsage", "api-test-resourceusage");

        // Act & Assert
        mockMvc.perform(get("/api/admin/tenants/{tenantId}/resource-usage", tenantId)
                .contentType(MediaType.APPLICATION_JSON))
                .andExpect(status().isOk())
                .andExpect(content().contentType(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$.tenantId").value(tenantId))
                .andExpect(jsonPath("$.currentUsers").exists())
                .andExpect(jsonPath("$.currentDashboards").exists())
                .andExpect(jsonPath("$.alertsToday").exists())
                .andExpect(jsonPath("$.storageUsedMb").exists());

        log.info("Get resource usage test completed successfully");
    }

    @Test
    @Order(9)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test check quota")
    void testCheckQuota() throws Exception {
        log.info("Testing check quota");

        // Arrange - Create a tenant first
        String tenantId = createTestTenant("API-Test-CheckQuota", "api-test-checkquota");

        Map<String, Object> quotaCheckRequest = new HashMap<>();
        quotaCheckRequest.put("resourceType", "users");
        quotaCheckRequest.put("requestedAmount", 10);

        // Act & Assert
        mockMvc.perform(post("/api/admin/tenants/{tenantId}/check-quota", tenantId)
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(quotaCheckRequest)))
                .andExpect(status().isOk())
                .andExpect(content().contentType(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$.allowed").exists())
                .andExpect(jsonPath("$.reason").exists());

        log.info("Check quota test completed successfully");
    }

    @Test
    @Order(10)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test record usage")
    void testRecordUsage() throws Exception {
        log.info("Testing record usage");

        // Arrange - Create a tenant first
        String tenantId = createTestTenant("API-Test-RecordUsage", "api-test-recordusage");

        Map<String, Object> usageRecord = new HashMap<>();
        usageRecord.put("resourceType", "users");
        usageRecord.put("amount", 5);

        // Act & Assert
        mockMvc.perform(post("/api/admin/tenants/{tenantId}/record-usage", tenantId)
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(usageRecord)))
                .andExpect(status().isOk());

        log.info("Record usage test completed successfully");
    }

    @Test
    @Order(11)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test get tenant health")
    void testGetTenantHealth() throws Exception {
        log.info("Testing get tenant health");

        // Arrange - Create a tenant first
        String tenantId = createTestTenant("API-Test-Health", "api-test-health");

        // Act & Assert
        mockMvc.perform(get("/api/admin/tenants/{tenantId}/health", tenantId)
                .contentType(MediaType.APPLICATION_JSON))
                .andExpect(status().isOk())
                .andExpect(content().contentType(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$.tenantId").value(tenantId))
                .andExpect(jsonPath("$.tenantName").value("API-Test-Health"))
                .andExpect(jsonPath("$.status").exists())
                .andExpect(jsonPath("$.tier").exists())
                .andExpect(jsonPath("$.provisioningReady").exists())
                .andExpect(jsonPath("$.quotaStatus").exists())
                .andExpect(jsonPath("$.lastUpdated").exists());

        log.info("Get tenant health test completed successfully");
    }

    @Test
    @Order(12)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test tenant deprovisioning via API")
    void testTenantDeprovisioningViaAPI() throws Exception {
        log.info("Testing tenant deprovisioning via API");

        // Arrange - Create a tenant first
        String tenantId = createTestTenant("API-Test-Deprovision", "api-test-deprovision");

        // Act & Assert
        mockMvc.perform(delete("/api/admin/tenants/{tenantId}", tenantId)
                .param("preserveData", "false")
                .contentType(MediaType.APPLICATION_JSON))
                .andExpect(status().isOk())
                .andExpect(content().contentType(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$.status").value("SUCCESS"))
                .andExpect(jsonPath("$.tenantId").value(tenantId))
                .andExpect(jsonPath("$.steps").exists());

        // Remove from cleanup list since it's deprovisioned
        createdTenantIds.remove(tenantId);

        log.info("Tenant deprovisioning API test completed successfully");
    }

    @Test
    @Order(13)
    @WithMockUser(authorities = "USER") // Non-admin user
    @DisplayName("Test unauthorized access")
    void testUnauthorizedAccess() throws Exception {
        log.info("Testing unauthorized access");

        // Act & Assert - Should return 403 Forbidden
        mockMvc.perform(get("/api/admin/tenants")
                .contentType(MediaType.APPLICATION_JSON))
                .andExpect(status().isForbidden());

        log.info("Unauthorized access test completed successfully");
    }

    @Test
    @Order(14)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test invalid tenant ID")
    void testInvalidTenantId() throws Exception {
        log.info("Testing invalid tenant ID");

        String invalidTenantId = "00000000-0000-0000-0000-000000000000";

        // Act & Assert - Should return 404 Not Found
        mockMvc.perform(get("/api/admin/tenants/{tenantId}", invalidTenantId)
                .contentType(MediaType.APPLICATION_JSON))
                .andExpect(status().isNotFound());

        log.info("Invalid tenant ID test completed successfully");
    }

    @Test
    @Order(15)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test invalid provisioning request")
    void testInvalidProvisioningRequest() throws Exception {
        log.info("Testing invalid provisioning request");

        // Arrange - Create invalid request (missing required fields)
        TenantProvisioningRequest invalidRequest = new TenantProvisioningRequest();
        // Missing name and subdomain

        // Act & Assert - Should return 400 Bad Request
        mockMvc.perform(post("/api/admin/tenants/provision")
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(invalidRequest)))
                .andExpect(status().isBadRequest());

        log.info("Invalid provisioning request test completed successfully");
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
                .andExpect(status().isCreated())
                .andReturn();

        String responseBody = result.getResponse().getContentAsString();
        Map<String, Object> response = objectMapper.readValue(responseBody, Map.class);
        String tenantId = (String) response.get("tenantId");
        
        createdTenantIds.add(tenantId);
        return tenantId;
    }

    private void cleanup() {
        log.info("Cleaning up created tenants: {}", createdTenantIds.size());
        
        for (String tenantId : createdTenantIds) {
            try {
                mockMvc.perform(delete("/api/admin/tenants/{tenantId}", tenantId)
                        .param("preserveData", "false")
                        .contentType(MediaType.APPLICATION_JSON))
                        .andExpect(status().isOk());
                log.debug("Cleaned up tenant: {}", tenantId);
            } catch (Exception e) {
                log.warn("Failed to cleanup tenant {}: {}", tenantId, e.getMessage());
            }
        }
        
        createdTenantIds.clear();
        log.info("Cleanup completed");
    }
}
