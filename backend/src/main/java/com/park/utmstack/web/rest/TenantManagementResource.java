package com.park.utmstack.web.rest;

import com.park.utmstack.domain.UtmTenant;
import com.park.utmstack.service.TenantProvisioningService;
import com.park.utmstack.service.TenantProvisioningService.*;
import com.park.utmstack.service.TenantResourceQuotaService;
import com.park.utmstack.service.TenantResourceQuotaService.*;
import com.park.utmstack.service.TenantService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

import javax.validation.Valid;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;

/**
 * REST controller for tenant management operations.
 * Provides APIs for automated provisioning, resource monitoring, and administration.
 */
@RestController
@RequestMapping("/api/admin/tenants")
@PreAuthorize("hasAuthority('SUPER_ADMIN')")
public class TenantManagementResource {

    private static final Logger log = LoggerFactory.getLogger(TenantManagementResource.class);

    private final TenantService tenantService;
    private final TenantProvisioningService provisioningService;
    private final TenantResourceQuotaService quotaService;

    public TenantManagementResource(TenantService tenantService,
                                   TenantProvisioningService provisioningService,
                                   TenantResourceQuotaService quotaService) {
        this.tenantService = tenantService;
        this.provisioningService = provisioningService;
        this.quotaService = quotaService;
    }

    /**
     * Provision a new tenant with complete setup
     */
    @PostMapping("/provision")
    public CompletableFuture<ResponseEntity<TenantProvisioningResult>> provisionTenant(
            @Valid @RequestBody TenantProvisioningRequest request) {
        
        log.info("Received tenant provisioning request: name={}, subdomain={}, tier={}", 
                request.getName(), request.getSubdomain(), request.getTier());

        return provisioningService.provisionTenant(request)
            .thenApply(result -> {
                if ("SUCCESS".equals(result.getStatus())) {
                    return ResponseEntity.status(HttpStatus.CREATED).body(result);
                } else {
                    return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(result);
                }
            })
            .exceptionally(throwable -> {
                log.error("Error provisioning tenant", throwable);
                TenantProvisioningResult errorResult = new TenantProvisioningResult();
                errorResult.setStatus("FAILED");
                errorResult.setError("Internal server error: " + throwable.getMessage());
                return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(errorResult);
            });
    }

    /**
     * Deprovision a tenant
     */
    @DeleteMapping("/{tenantId}")
    public CompletableFuture<ResponseEntity<TenantDeprovisioningResult>> deprovisionTenant(
            @PathVariable UUID tenantId,
            @RequestParam(defaultValue = "false") boolean preserveData) {
        
        log.info("Received tenant deprovisioning request: tenantId={}, preserveData={}", tenantId, preserveData);

        return provisioningService.deprovisionTenant(tenantId, preserveData)
            .thenApply(result -> {
                if ("SUCCESS".equals(result.getStatus())) {
                    return ResponseEntity.ok(result);
                } else {
                    return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(result);
                }
            })
            .exceptionally(throwable -> {
                log.error("Error deprovisioning tenant", throwable);
                TenantDeprovisioningResult errorResult = new TenantDeprovisioningResult();
                errorResult.setStatus("FAILED");
                errorResult.setError("Internal server error: " + throwable.getMessage());
                return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(errorResult);
            });
    }

    /**
     * Get all tenants
     */
    @GetMapping
    public ResponseEntity<List<UtmTenant>> getAllTenants() {
        List<UtmTenant> tenants = tenantService.getAllActiveTenants();
        return ResponseEntity.ok(tenants);
    }

    /**
     * Get tenant by ID
     */
    @GetMapping("/{tenantId}")
    public ResponseEntity<UtmTenant> getTenant(@PathVariable UUID tenantId) {
        Optional<UtmTenant> tenant = tenantService.getTenant(tenantId);
        return tenant.map(ResponseEntity::ok)
                    .orElse(ResponseEntity.notFound().build());
    }

    /**
     * Update tenant status
     */
    @PutMapping("/{tenantId}/status")
    public ResponseEntity<UtmTenant> updateTenantStatus(
            @PathVariable UUID tenantId,
            @RequestBody Map<String, String> statusUpdate) {
        
        try {
            String newStatus = statusUpdate.get("status");
            if (newStatus == null || newStatus.trim().isEmpty()) {
                return ResponseEntity.badRequest().build();
            }

            UtmTenant updatedTenant = tenantService.updateTenantStatus(tenantId, newStatus);
            return ResponseEntity.ok(updatedTenant);
            
        } catch (IllegalArgumentException e) {
            return ResponseEntity.notFound().build();
        } catch (Exception e) {
            log.error("Error updating tenant status", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }

    /**
     * Get tenant provisioning status
     */
    @GetMapping("/{tenantId}/provisioning-status")
    public ResponseEntity<ProvisioningStatus> getProvisioningStatus(@PathVariable UUID tenantId) {
        try {
            ProvisioningStatus status = provisioningService.getProvisioningStatus(tenantId);
            return ResponseEntity.ok(status);
        } catch (IllegalArgumentException e) {
            return ResponseEntity.notFound().build();
        } catch (Exception e) {
            log.error("Error getting provisioning status", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }

    /**
     * Get tenant resource quota status
     */
    @GetMapping("/{tenantId}/quota-status")
    public ResponseEntity<ResourceQuotaStatus> getResourceQuotaStatus(@PathVariable UUID tenantId) {
        try {
            ResourceQuotaStatus status = quotaService.getResourceQuotaStatus(tenantId);
            return ResponseEntity.ok(status);
        } catch (Exception e) {
            log.error("Error getting quota status", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }

    /**
     * Update tenant resource limits
     */
    @PutMapping("/{tenantId}/resource-limits")
    public ResponseEntity<Void> updateResourceLimits(
            @PathVariable UUID tenantId,
            @RequestBody Map<String, Integer> newLimits) {
        
        try {
            quotaService.updateTenantResourceLimits(tenantId, newLimits);
            return ResponseEntity.ok().build();
        } catch (IllegalArgumentException e) {
            return ResponseEntity.notFound().build();
        } catch (Exception e) {
            log.error("Error updating resource limits", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }

    /**
     * Get tenant resource usage
     */
    @GetMapping("/{tenantId}/resource-usage")
    public ResponseEntity<TenantResourceUsage> getResourceUsage(@PathVariable UUID tenantId) {
        try {
            TenantResourceUsage usage = quotaService.getTenantResourceUsage(tenantId);
            return ResponseEntity.ok(usage);
        } catch (Exception e) {
            log.error("Error getting resource usage", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }

    /**
     * Check resource quota for specific resource type
     */
    @PostMapping("/{tenantId}/check-quota")
    public ResponseEntity<QuotaCheckResult> checkResourceQuota(
            @PathVariable UUID tenantId,
            @RequestBody QuotaCheckRequest request) {
        
        try {
            QuotaCheckResult result = quotaService.checkResourceQuota(
                tenantId, request.getResourceType(), request.getRequestedAmount());
            return ResponseEntity.ok(result);
        } catch (Exception e) {
            log.error("Error checking resource quota", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }

    /**
     * Record resource usage (for manual tracking or corrections)
     */
    @PostMapping("/{tenantId}/record-usage")
    public ResponseEntity<Void> recordResourceUsage(
            @PathVariable UUID tenantId,
            @RequestBody ResourceUsageRecord record) {
        
        try {
            quotaService.recordResourceUsage(tenantId, record.getResourceType(), record.getAmount());
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            log.error("Error recording resource usage", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }

    /**
     * Get tenant health summary
     */
    @GetMapping("/{tenantId}/health")
    public ResponseEntity<TenantHealthSummary> getTenantHealth(@PathVariable UUID tenantId) {
        try {
            Optional<UtmTenant> tenantOpt = tenantService.getTenant(tenantId);
            if (!tenantOpt.isPresent()) {
                return ResponseEntity.notFound().build();
            }

            UtmTenant tenant = tenantOpt.get();
            ProvisioningStatus provisioningStatus = provisioningService.getProvisioningStatus(tenantId);
            ResourceQuotaStatus quotaStatus = quotaService.getResourceQuotaStatus(tenantId);

            TenantHealthSummary health = new TenantHealthSummary();
            health.setTenantId(tenantId);
            health.setTenantName(tenant.getName());
            health.setStatus(tenant.getStatus());
            health.setTier(tenant.getTier());
            health.setProvisioningReady(provisioningStatus.isOverallReady());
            health.setQuotaStatus(quotaStatus.getOverallStatus());
            health.setLastUpdated(tenant.getUpdatedAt());

            return ResponseEntity.ok(health);

        } catch (Exception e) {
            log.error("Error getting tenant health", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }

    // Request/Response DTOs
    public static class QuotaCheckRequest {
        private String resourceType;
        private int requestedAmount;

        public String getResourceType() { return resourceType; }
        public void setResourceType(String resourceType) { this.resourceType = resourceType; }

        public int getRequestedAmount() { return requestedAmount; }
        public void setRequestedAmount(int requestedAmount) { this.requestedAmount = requestedAmount; }
    }

    public static class ResourceUsageRecord {
        private String resourceType;
        private int amount;

        public String getResourceType() { return resourceType; }
        public void setResourceType(String resourceType) { this.resourceType = resourceType; }

        public int getAmount() { return amount; }
        public void setAmount(int amount) { this.amount = amount; }
    }

    public static class TenantHealthSummary {
        private UUID tenantId;
        private String tenantName;
        private String status;
        private String tier;
        private boolean provisioningReady;
        private String quotaStatus;
        private java.time.Instant lastUpdated;

        // Getters and setters
        public UUID getTenantId() { return tenantId; }
        public void setTenantId(UUID tenantId) { this.tenantId = tenantId; }

        public String getTenantName() { return tenantName; }
        public void setTenantName(String tenantName) { this.tenantName = tenantName; }

        public String getStatus() { return status; }
        public void setStatus(String status) { this.status = status; }

        public String getTier() { return tier; }
        public void setTier(String tier) { this.tier = tier; }

        public boolean isProvisioningReady() { return provisioningReady; }
        public void setProvisioningReady(boolean provisioningReady) { this.provisioningReady = provisioningReady; }

        public String getQuotaStatus() { return quotaStatus; }
        public void setQuotaStatus(String quotaStatus) { this.quotaStatus = quotaStatus; }

        public java.time.Instant getLastUpdated() { return lastUpdated; }
        public void setLastUpdated(java.time.Instant lastUpdated) { this.lastUpdated = lastUpdated; }
    }
}
