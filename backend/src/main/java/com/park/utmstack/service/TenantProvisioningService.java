package com.park.utmstack.service;

import com.park.utmstack.domain.UtmTenant;
import com.park.utmstack.service.elasticsearch.MultiTenantElasticsearchService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.HashMap;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;

/**
 * Service for automated tenant provisioning and lifecycle management.
 * Handles zero-downtime tenant onboarding with complete resource setup.
 */
@Service
@Transactional
public class TenantProvisioningService {

    private static final Logger log = LoggerFactory.getLogger(TenantProvisioningService.class);

    private final TenantService tenantService;
    private final MultiTenantElasticsearchService elasticsearchService;
    private final TenantResourceQuotaService quotaService;

    public TenantProvisioningService(TenantService tenantService,
                                   MultiTenantElasticsearchService elasticsearchService,
                                   TenantResourceQuotaService quotaService) {
        this.tenantService = tenantService;
        this.elasticsearchService = elasticsearchService;
        this.quotaService = quotaService;
    }

    /**
     * Complete tenant provisioning with all required resources
     */
    public CompletableFuture<TenantProvisioningResult> provisionTenant(TenantProvisioningRequest request) {
        return CompletableFuture.supplyAsync(() -> {
            log.info("Starting tenant provisioning: name={}, subdomain={}, tier={}", 
                    request.getName(), request.getSubdomain(), request.getTier());

            TenantProvisioningResult result = new TenantProvisioningResult();
            result.setRequestId(UUID.randomUUID().toString());
            result.setStartTime(System.currentTimeMillis());

            try {
                // Phase 1: Create tenant record
                UtmTenant tenant = tenantService.createTenant(
                    request.getName(), 
                    request.getSubdomain(), 
                    request.getTier()
                );
                result.setTenantId(tenant.getId());
                result.addStep("tenant_created", true, "Tenant record created successfully");

                // Phase 2: Setup Elasticsearch indices
                setupElasticsearchIndices(tenant.getId(), result);

                // Phase 3: Initialize resource quotas
                initializeResourceQuotas(tenant.getId(), request.getTier(), result);

                // Phase 4: Create default configurations
                createDefaultConfigurations(tenant.getId(), request, result);

                // Phase 5: Validate setup
                validateTenantSetup(tenant.getId(), result);

                result.setStatus("SUCCESS");
                result.setEndTime(System.currentTimeMillis());
                log.info("Tenant provisioning completed successfully: tenantId={}, duration={}ms", 
                        tenant.getId(), result.getDurationMs());

            } catch (Exception e) {
                log.error("Tenant provisioning failed: {}", e.getMessage(), e);
                result.setStatus("FAILED");
                result.setError(e.getMessage());
                result.setEndTime(System.currentTimeMillis());
                
                // Attempt cleanup if tenant was created
                if (result.getTenantId() != null) {
                    cleanupFailedProvisioning(result.getTenantId());
                }
            }

            return result;
        });
    }

    /**
     * Deprovision tenant and cleanup all resources
     */
    public CompletableFuture<TenantDeprovisioningResult> deprovisionTenant(UUID tenantId, boolean preserveData) {
        return CompletableFuture.supplyAsync(() -> {
            log.info("Starting tenant deprovisioning: tenantId={}, preserveData={}", tenantId, preserveData);

            TenantDeprovisioningResult result = new TenantDeprovisioningResult();
            result.setRequestId(UUID.randomUUID().toString());
            result.setTenantId(tenantId);
            result.setStartTime(System.currentTimeMillis());

            try {
                // Phase 1: Deactivate tenant
                tenantService.updateTenantStatus(tenantId, "deactivating");
                result.addStep("tenant_deactivated", true, "Tenant deactivated");

                // Phase 2: Cleanup Elasticsearch indices
                if (!preserveData) {
                    cleanupElasticsearchIndices(tenantId, result);
                } else {
                    result.addStep("elasticsearch_preserved", true, "Elasticsearch data preserved");
                }

                // Phase 3: Release resource quotas
                releaseResourceQuotas(tenantId, result);

                // Phase 4: Archive or delete tenant data
                if (preserveData) {
                    tenantService.updateTenantStatus(tenantId, "archived");
                    result.addStep("tenant_archived", true, "Tenant archived");
                } else {
                    // Note: Actual deletion would require careful cascade handling
                    tenantService.updateTenantStatus(tenantId, "deleted");
                    result.addStep("tenant_deleted", true, "Tenant marked as deleted");
                }

                result.setStatus("SUCCESS");
                result.setEndTime(System.currentTimeMillis());
                log.info("Tenant deprovisioning completed: tenantId={}, duration={}ms", 
                        tenantId, result.getDurationMs());

            } catch (Exception e) {
                log.error("Tenant deprovisioning failed: {}", e.getMessage(), e);
                result.setStatus("FAILED");
                result.setError(e.getMessage());
                result.setEndTime(System.currentTimeMillis());
            }

            return result;
        });
    }

    /**
     * Get provisioning status
     */
    public ProvisioningStatus getProvisioningStatus(UUID tenantId) {
        UtmTenant tenant = tenantService.getTenant(tenantId)
            .orElseThrow(() -> new IllegalArgumentException("Tenant not found: " + tenantId));

        ProvisioningStatus status = new ProvisioningStatus();
        status.setTenantId(tenantId);
        status.setStatus(tenant.getStatus());
        status.setElasticsearchReady(elasticsearchService.isIndexHealthy(tenantId));
        status.setQuotasConfigured(quotaService.areQuotasConfigured(tenantId));
        status.setOverallReady(isFullyProvisioned(tenantId));

        return status;
    }

    private void setupElasticsearchIndices(UUID tenantId, TenantProvisioningResult result) {
        try {
            log.debug("Setting up Elasticsearch indices for tenant: {}", tenantId);
            
            // Create tenant-specific index templates
            elasticsearchService.createTenantIndexTemplates(tenantId);
            result.addStep("elasticsearch_templates", true, "Index templates created");

            // Initialize default indices
            String[] defaultIndices = {"alerts", "logs", "incidents", "reports"};
            for (String indexType : defaultIndices) {
                elasticsearchService.createTenantIndex(tenantId, indexType);
            }
            result.addStep("elasticsearch_indices", true, "Default indices created");

        } catch (Exception e) {
            log.error("Failed to setup Elasticsearch indices for tenant: {}", tenantId, e);
            result.addStep("elasticsearch_setup", false, "Failed: " + e.getMessage());
            throw e;
        }
    }

    private void initializeResourceQuotas(UUID tenantId, String tier, TenantProvisioningResult result) {
        try {
            log.debug("Initializing resource quotas for tenant: {}, tier: {}", tenantId, tier);
            
            quotaService.initializeTenantQuotas(tenantId, tier);
            result.addStep("resource_quotas", true, "Resource quotas initialized");

        } catch (Exception e) {
            log.error("Failed to initialize resource quotas for tenant: {}", tenantId, e);
            result.addStep("resource_quotas", false, "Failed: " + e.getMessage());
            throw e;
        }
    }

    private void createDefaultConfigurations(UUID tenantId, TenantProvisioningRequest request, 
                                           TenantProvisioningResult result) {
        try {
            log.debug("Creating default configurations for tenant: {}", tenantId);

            // Additional custom configurations if provided
            if (request.getCustomConfigurations() != null) {
                for (Map.Entry<String, String> config : request.getCustomConfigurations().entrySet()) {
                    tenantService.setTenantConfigValue(tenantId, config.getKey(), config.getValue(), "STRING");
                }
            }

            result.addStep("default_config", true, "Default configurations created");

        } catch (Exception e) {
            log.error("Failed to create default configurations for tenant: {}", tenantId, e);
            result.addStep("default_config", false, "Failed: " + e.getMessage());
            throw e;
        }
    }

    private void validateTenantSetup(UUID tenantId, TenantProvisioningResult result) {
        try {
            log.debug("Validating tenant setup: {}", tenantId);

            // Validate tenant record
            if (!tenantService.getTenant(tenantId).isPresent()) {
                throw new RuntimeException("Tenant validation failed: tenant not found");
            }

            // Validate Elasticsearch setup
            if (!elasticsearchService.isIndexHealthy(tenantId)) {
                throw new RuntimeException("Tenant validation failed: Elasticsearch not healthy");
            }

            // Validate quotas
            if (!quotaService.areQuotasConfigured(tenantId)) {
                throw new RuntimeException("Tenant validation failed: quotas not configured");
            }

            result.addStep("validation", true, "Tenant setup validated successfully");

        } catch (Exception e) {
            log.error("Tenant setup validation failed: {}", tenantId, e);
            result.addStep("validation", false, "Failed: " + e.getMessage());
            throw e;
        }
    }

    private void cleanupFailedProvisioning(UUID tenantId) {
        try {
            log.warn("Cleaning up failed tenant provisioning: {}", tenantId);
            
            // Update tenant status to failed
            tenantService.updateTenantStatus(tenantId, "failed");
            
            // Cleanup any created resources
            elasticsearchService.cleanupTenantIndices(tenantId);
            quotaService.cleanupTenantQuotas(tenantId);
            
        } catch (Exception e) {
            log.error("Failed to cleanup failed provisioning for tenant: {}", tenantId, e);
        }
    }

    private void cleanupElasticsearchIndices(UUID tenantId, TenantDeprovisioningResult result) {
        try {
            elasticsearchService.cleanupTenantIndices(tenantId);
            result.addStep("elasticsearch_cleanup", true, "Elasticsearch indices cleaned up");
        } catch (Exception e) {
            log.error("Failed to cleanup Elasticsearch indices: {}", tenantId, e);
            result.addStep("elasticsearch_cleanup", false, "Failed: " + e.getMessage());
            throw e;
        }
    }

    private void releaseResourceQuotas(UUID tenantId, TenantDeprovisioningResult result) {
        try {
            quotaService.cleanupTenantQuotas(tenantId);
            result.addStep("quota_cleanup", true, "Resource quotas released");
        } catch (Exception e) {
            log.error("Failed to release resource quotas: {}", tenantId, e);
            result.addStep("quota_cleanup", false, "Failed: " + e.getMessage());
            throw e;
        }
    }

    private boolean isFullyProvisioned(UUID tenantId) {
        try {
            return tenantService.getTenant(tenantId).isPresent() &&
                   elasticsearchService.isIndexHealthy(tenantId) &&
                   quotaService.areQuotasConfigured(tenantId);
        } catch (Exception e) {
            log.error("Error checking provisioning status: {}", tenantId, e);
            return false;
        }
    }

    // Inner classes for request/response models
    public static class TenantProvisioningRequest {
        private String name;
        private String subdomain;
        private String tier = "standard";
        private Map<String, String> customConfigurations = new HashMap<>();

        // Getters and setters
        public String getName() { return name; }
        public void setName(String name) { this.name = name; }

        public String getSubdomain() { return subdomain; }
        public void setSubdomain(String subdomain) { this.subdomain = subdomain; }

        public String getTier() { return tier; }
        public void setTier(String tier) { this.tier = tier; }

        public Map<String, String> getCustomConfigurations() { return customConfigurations; }
        public void setCustomConfigurations(Map<String, String> customConfigurations) { 
            this.customConfigurations = customConfigurations; 
        }
    }

    public static class TenantProvisioningResult {
        private String requestId;
        private UUID tenantId;
        private String status;
        private String error;
        private long startTime;
        private long endTime;
        private Map<String, ProvisioningStep> steps = new HashMap<>();

        public void addStep(String stepName, boolean success, String message) {
            steps.put(stepName, new ProvisioningStep(stepName, success, message, System.currentTimeMillis()));
        }

        public long getDurationMs() {
            return endTime > 0 ? endTime - startTime : System.currentTimeMillis() - startTime;
        }

        // Getters and setters
        public String getRequestId() { return requestId; }
        public void setRequestId(String requestId) { this.requestId = requestId; }

        public UUID getTenantId() { return tenantId; }
        public void setTenantId(UUID tenantId) { this.tenantId = tenantId; }

        public String getStatus() { return status; }
        public void setStatus(String status) { this.status = status; }

        public String getError() { return error; }
        public void setError(String error) { this.error = error; }

        public long getStartTime() { return startTime; }
        public void setStartTime(long startTime) { this.startTime = startTime; }

        public long getEndTime() { return endTime; }
        public void setEndTime(long endTime) { this.endTime = endTime; }

        public Map<String, ProvisioningStep> getSteps() { return steps; }
        public void setSteps(Map<String, ProvisioningStep> steps) { this.steps = steps; }
    }

    public static class TenantDeprovisioningResult extends TenantProvisioningResult {
        // Inherits from TenantProvisioningResult with same structure
    }

    public static class ProvisioningStep {
        private String stepName;
        private boolean success;
        private String message;
        private long timestamp;

        public ProvisioningStep(String stepName, boolean success, String message, long timestamp) {
            this.stepName = stepName;
            this.success = success;
            this.message = message;
            this.timestamp = timestamp;
        }

        // Getters and setters
        public String getStepName() { return stepName; }
        public void setStepName(String stepName) { this.stepName = stepName; }

        public boolean isSuccess() { return success; }
        public void setSuccess(boolean success) { this.success = success; }

        public String getMessage() { return message; }
        public void setMessage(String message) { this.message = message; }

        public long getTimestamp() { return timestamp; }
        public void setTimestamp(long timestamp) { this.timestamp = timestamp; }
    }

    public static class ProvisioningStatus {
        private UUID tenantId;
        private String status;
        private boolean elasticsearchReady;
        private boolean quotasConfigured;
        private boolean overallReady;

        // Getters and setters
        public UUID getTenantId() { return tenantId; }
        public void setTenantId(UUID tenantId) { this.tenantId = tenantId; }

        public String getStatus() { return status; }
        public void setStatus(String status) { this.status = status; }

        public boolean isElasticsearchReady() { return elasticsearchReady; }
        public void setElasticsearchReady(boolean elasticsearchReady) { this.elasticsearchReady = elasticsearchReady; }

        public boolean isQuotasConfigured() { return quotasConfigured; }
        public void setQuotasConfigured(boolean quotasConfigured) { this.quotasConfigured = quotasConfigured; }

        public boolean isOverallReady() { return overallReady; }
        public void setOverallReady(boolean overallReady) { this.overallReady = overallReady; }
    }

    // Event classes for tenant provisioning
    public static class TenantProvisionedEvent {
        private final UUID tenantId;
        private final long provisioningTimeMs;
        private final String tier;
        private final String subdomain;

        public TenantProvisionedEvent(UUID tenantId, long provisioningTimeMs, String tier, String subdomain) {
            this.tenantId = tenantId;
            this.provisioningTimeMs = provisioningTimeMs;
            this.tier = tier;
            this.subdomain = subdomain;
        }

        public UUID getTenantId() { return tenantId; }
        public long getProvisioningTimeMs() { return provisioningTimeMs; }
        public String getTier() { return tier; }
        public String getSubdomain() { return subdomain; }
    }

    public static class TenantProvisioningFailedEvent {
        private final String requestId;
        private final String reason;
        private final String subdomain;
        private final long failureTimeMs;

        public TenantProvisioningFailedEvent(String requestId, String reason, String subdomain, long failureTimeMs) {
            this.requestId = requestId;
            this.reason = reason;
            this.subdomain = subdomain;
            this.failureTimeMs = failureTimeMs;
        }

        public String getRequestId() { return requestId; }
        public String getReason() { return reason; }
        public String getSubdomain() { return subdomain; }
        public long getFailureTimeMs() { return failureTimeMs; }
    }
}
