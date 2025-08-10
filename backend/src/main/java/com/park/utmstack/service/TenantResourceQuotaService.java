package com.park.utmstack.service;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.park.utmstack.domain.UtmTenant;
import com.park.utmstack.repository.UtmTenantRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Service for managing tenant resource quotas and monitoring usage.
 * Enforces limits based on tier and tracks resource consumption.
 */
@Service
@Transactional
public class TenantResourceQuotaService {

    private static final Logger log = LoggerFactory.getLogger(TenantResourceQuotaService.class);

    private final UtmTenantRepository tenantRepository;
    private final ObjectMapper objectMapper;
    
    // In-memory cache for quota enforcement (would be Redis in production)
    private final Map<UUID, TenantResourceUsage> usageCache = new ConcurrentHashMap<>();

    public TenantResourceQuotaService(UtmTenantRepository tenantRepository) {
        this.tenantRepository = tenantRepository;
        this.objectMapper = new ObjectMapper();
    }

    /**
     * Initialize quotas for a new tenant based on tier
     */
    public void initializeTenantQuotas(UUID tenantId, String tier) {
        log.info("Initializing resource quotas for tenant: {}, tier: {}", tenantId, tier);

        UtmTenant tenant = tenantRepository.findById(tenantId)
            .orElseThrow(() -> new IllegalArgumentException("Tenant not found: " + tenantId));

        // Set resource limits based on tier
        String resourceLimits = generateResourceLimitsForTier(tier);
        tenant.setResourceLimits(resourceLimits);
        tenant.setUpdatedAt(Instant.now());
        tenantRepository.save(tenant);

        // Initialize usage tracking
        TenantResourceUsage usage = new TenantResourceUsage();
        usage.setTenantId(tenantId);
        usage.setLastUpdated(LocalDateTime.now());
        usageCache.put(tenantId, usage);

        log.info("Resource quotas initialized for tenant: {}", tenantId);
    }

    /**
     * Check if resource usage is within limits
     */
    public QuotaCheckResult checkResourceQuota(UUID tenantId, String resourceType, int requestedAmount) {
        try {
            UtmTenant tenant = tenantRepository.findById(tenantId)
                .orElseThrow(() -> new IllegalArgumentException("Tenant not found: " + tenantId));

            JsonNode limits = objectMapper.readTree(tenant.getResourceLimits());
            TenantResourceUsage usage = getOrCreateUsage(tenantId);

            return performQuotaCheck(limits, usage, resourceType, requestedAmount);

        } catch (Exception e) {
            log.error("Error checking resource quota for tenant: {}", tenantId, e);
            return QuotaCheckResult.error("Error checking quota: " + e.getMessage());
        }
    }

    /**
     * Record resource usage
     */
    public void recordResourceUsage(UUID tenantId, String resourceType, int amount) {
        try {
            TenantResourceUsage usage = getOrCreateUsage(tenantId);
            
            switch (resourceType.toLowerCase()) {
                case "users":
                    usage.setCurrentUsers(usage.getCurrentUsers() + amount);
                    break;
                case "dashboards":
                    usage.setCurrentDashboards(usage.getCurrentDashboards() + amount);
                    break;
                case "alerts":
                    usage.setAlertsToday(usage.getAlertsToday() + amount);
                    break;
                case "storage_mb":
                    usage.setStorageUsedMb(usage.getStorageUsedMb() + amount);
                    break;
                default:
                    log.warn("Unknown resource type: {}", resourceType);
                    return;
            }

            usage.setLastUpdated(LocalDateTime.now());
            usageCache.put(tenantId, usage);

            // Persist usage periodically or on significant changes
            if (shouldPersistUsage(usage)) {
                persistUsageMetrics(tenantId, usage);
            }

        } catch (Exception e) {
            log.error("Error recording resource usage for tenant: {}", tenantId, e);
        }
    }

    /**
     * Get current resource usage for tenant
     */
    public TenantResourceUsage getTenantResourceUsage(UUID tenantId) {
        return getOrCreateUsage(tenantId);
    }

    /**
     * Get resource quota status
     */
    public ResourceQuotaStatus getResourceQuotaStatus(UUID tenantId) {
        try {
            UtmTenant tenant = tenantRepository.findById(tenantId)
                .orElseThrow(() -> new IllegalArgumentException("Tenant not found: " + tenantId));

            JsonNode limits = objectMapper.readTree(tenant.getResourceLimits());
            TenantResourceUsage usage = getOrCreateUsage(tenantId);

            ResourceQuotaStatus status = new ResourceQuotaStatus();
            status.setTenantId(tenantId);
            status.setTier(tenant.getTier());

            // Calculate usage percentages
            status.setUserUsage(calculateUsagePercentage(usage.getCurrentUsers(), limits.get("max_users").asInt()));
            status.setDashboardUsage(calculateUsagePercentage(usage.getCurrentDashboards(), limits.get("max_dashboards").asInt()));
            status.setStorageUsage(calculateUsagePercentage(usage.getStorageUsedMb(), limits.get("storage_gb").asInt() * 1024));
            status.setDailyAlertUsage(calculateUsagePercentage(usage.getAlertsToday(), limits.get("max_alerts_per_day").asInt()));

            // Determine overall status
            double maxUsage = Math.max(Math.max(status.getUserUsage(), status.getDashboardUsage()),
                                     Math.max(status.getStorageUsage(), status.getDailyAlertUsage()));
            
            if (maxUsage >= 95) {
                status.setOverallStatus("CRITICAL");
            } else if (maxUsage >= 80) {
                status.setOverallStatus("WARNING");
            } else {
                status.setOverallStatus("OK");
            }

            return status;

        } catch (Exception e) {
            log.error("Error getting resource quota status for tenant: {}", tenantId, e);
            ResourceQuotaStatus errorStatus = new ResourceQuotaStatus();
            errorStatus.setTenantId(tenantId);
            errorStatus.setOverallStatus("ERROR");
            return errorStatus;
        }
    }

    /**
     * Check if quotas are properly configured for tenant
     */
    public boolean areQuotasConfigured(UUID tenantId) {
        try {
            UtmTenant tenant = tenantRepository.findById(tenantId).orElse(null);
            if (tenant == null || tenant.getResourceLimits() == null) {
                return false;
            }

            JsonNode limits = objectMapper.readTree(tenant.getResourceLimits());
            return limits.has("max_users") && limits.has("max_dashboards") && 
                   limits.has("max_alerts_per_day") && limits.has("storage_gb");

        } catch (Exception e) {
            log.error("Error checking quota configuration for tenant: {}", tenantId, e);
            return false;
        }
    }

    /**
     * Update tenant resource limits
     */
    public void updateTenantResourceLimits(UUID tenantId, Map<String, Integer> newLimits) {
        try {
            UtmTenant tenant = tenantRepository.findById(tenantId)
                .orElseThrow(() -> new IllegalArgumentException("Tenant not found: " + tenantId));

            JsonNode currentLimits = objectMapper.readTree(tenant.getResourceLimits());
            Map<String, Object> updatedLimits = objectMapper.convertValue(currentLimits, Map.class);
            
            newLimits.forEach(updatedLimits::put);
            
            String updatedLimitsJson = objectMapper.writeValueAsString(updatedLimits);
            tenant.setResourceLimits(updatedLimitsJson);
            tenant.setUpdatedAt(Instant.now());
            tenantRepository.save(tenant);

            log.info("Updated resource limits for tenant: {}", tenantId);

        } catch (Exception e) {
            log.error("Error updating resource limits for tenant: {}", tenantId, e);
            throw new RuntimeException("Failed to update resource limits", e);
        }
    }

    /**
     * Reset daily usage counters (called by scheduled job)
     */
    public void resetDailyUsageCounters() {
        log.info("Resetting daily usage counters for all tenants");
        
        usageCache.values().forEach(usage -> {
            usage.setAlertsToday(0);
            usage.setLastUpdated(LocalDateTime.now());
        });
    }

    /**
     * Cleanup tenant quotas during deprovisioning
     */
    public void cleanupTenantQuotas(UUID tenantId) {
        log.info("Cleaning up quotas for tenant: {}", tenantId);
        usageCache.remove(tenantId);
    }

    private TenantResourceUsage getOrCreateUsage(UUID tenantId) {
        return usageCache.computeIfAbsent(tenantId, id -> {
            TenantResourceUsage usage = new TenantResourceUsage();
            usage.setTenantId(id);
            usage.setLastUpdated(LocalDateTime.now());
            return usage;
        });
    }

    private QuotaCheckResult performQuotaCheck(JsonNode limits, TenantResourceUsage usage, 
                                             String resourceType, int requestedAmount) {
        switch (resourceType.toLowerCase()) {
            case "users":
                int maxUsers = limits.get("max_users").asInt();
                int currentUsers = usage.getCurrentUsers();
                if (currentUsers + requestedAmount > maxUsers) {
                    return QuotaCheckResult.denied("User limit exceeded", maxUsers, currentUsers);
                }
                break;
                
            case "dashboards":
                int maxDashboards = limits.get("max_dashboards").asInt();
                int currentDashboards = usage.getCurrentDashboards();
                if (currentDashboards + requestedAmount > maxDashboards) {
                    return QuotaCheckResult.denied("Dashboard limit exceeded", maxDashboards, currentDashboards);
                }
                break;
                
            case "alerts":
                int maxAlerts = limits.get("max_alerts_per_day").asInt();
                int currentAlerts = usage.getAlertsToday();
                if (currentAlerts + requestedAmount > maxAlerts) {
                    return QuotaCheckResult.denied("Daily alert limit exceeded", maxAlerts, currentAlerts);
                }
                break;
                
            case "storage_mb":
                int maxStorageGb = limits.get("storage_gb").asInt();
                int maxStorageMb = maxStorageGb * 1024;
                int currentStorageMb = usage.getStorageUsedMb();
                if (currentStorageMb + requestedAmount > maxStorageMb) {
                    return QuotaCheckResult.denied("Storage limit exceeded", maxStorageMb, currentStorageMb);
                }
                break;
                
            default:
                return QuotaCheckResult.error("Unknown resource type: " + resourceType);
        }
        
        return QuotaCheckResult.allowed();
    }

    private String generateResourceLimitsForTier(String tier) {
        Map<String, Integer> limits = new HashMap<>();
        
        switch (tier.toLowerCase()) {
            case "enterprise":
                limits.put("max_users", 1000);
                limits.put("max_dashboards", 100);
                limits.put("max_alerts_per_day", 1000000);
                limits.put("storage_gb", 1000);
                break;
            case "professional":
                limits.put("max_users", 100);
                limits.put("max_dashboards", 50);
                limits.put("max_alerts_per_day", 100000);
                limits.put("storage_gb", 100);
                break;
            case "standard":
            default:
                limits.put("max_users", 25);
                limits.put("max_dashboards", 10);
                limits.put("max_alerts_per_day", 10000);
                limits.put("storage_gb", 10);
                break;
        }
        
        try {
            return objectMapper.writeValueAsString(limits);
        } catch (JsonProcessingException e) {
            log.error("Error serializing resource limits", e);
            return "{}";
        }
    }

    private double calculateUsagePercentage(int current, int max) {
        if (max == 0) return 0.0;
        return (double) current / max * 100.0;
    }

    private boolean shouldPersistUsage(TenantResourceUsage usage) {
        // Persist every 5 minutes or on significant changes
        return usage.getLastUpdated().isBefore(LocalDateTime.now().minusMinutes(5));
    }

    private void persistUsageMetrics(UUID tenantId, TenantResourceUsage usage) {
        // In production, this would persist to database or metrics store
        log.debug("Persisting usage metrics for tenant: {} - Users: {}, Dashboards: {}, Storage: {}MB, Alerts: {}",
                tenantId, usage.getCurrentUsers(), usage.getCurrentDashboards(), 
                usage.getStorageUsedMb(), usage.getAlertsToday());
    }

    // Inner classes for data models
    public static class TenantResourceUsage {
        private UUID tenantId;
        private int currentUsers = 0;
        private int currentDashboards = 0;
        private int alertsToday = 0;
        private int storageUsedMb = 0;
        private LocalDateTime lastUpdated;

        // Getters and setters
        public UUID getTenantId() { return tenantId; }
        public void setTenantId(UUID tenantId) { this.tenantId = tenantId; }

        public int getCurrentUsers() { return currentUsers; }
        public void setCurrentUsers(int currentUsers) { this.currentUsers = currentUsers; }

        public int getCurrentDashboards() { return currentDashboards; }
        public void setCurrentDashboards(int currentDashboards) { this.currentDashboards = currentDashboards; }

        public int getAlertsToday() { return alertsToday; }
        public void setAlertsToday(int alertsToday) { this.alertsToday = alertsToday; }

        public int getStorageUsedMb() { return storageUsedMb; }
        public void setStorageUsedMb(int storageUsedMb) { this.storageUsedMb = storageUsedMb; }

        public LocalDateTime getLastUpdated() { return lastUpdated; }
        public void setLastUpdated(LocalDateTime lastUpdated) { this.lastUpdated = lastUpdated; }
    }

    public static class QuotaCheckResult {
        private boolean allowed;
        private String reason;
        private int limit;
        private int current;

        public static QuotaCheckResult allowed() {
            QuotaCheckResult result = new QuotaCheckResult();
            result.allowed = true;
            return result;
        }

        public static QuotaCheckResult denied(String reason, int limit, int current) {
            QuotaCheckResult result = new QuotaCheckResult();
            result.allowed = false;
            result.reason = reason;
            result.limit = limit;
            result.current = current;
            return result;
        }

        public static QuotaCheckResult error(String reason) {
            QuotaCheckResult result = new QuotaCheckResult();
            result.allowed = false;
            result.reason = reason;
            return result;
        }

        // Getters and setters
        public boolean isAllowed() { return allowed; }
        public void setAllowed(boolean allowed) { this.allowed = allowed; }

        public String getReason() { return reason; }
        public void setReason(String reason) { this.reason = reason; }

        public int getLimit() { return limit; }
        public void setLimit(int limit) { this.limit = limit; }

        public int getCurrent() { return current; }
        public void setCurrent(int current) { this.current = current; }
    }

    public static class ResourceQuotaStatus {
        private UUID tenantId;
        private String tier;
        private String overallStatus;
        private double userUsage;
        private double dashboardUsage;
        private double storageUsage;
        private double dailyAlertUsage;

        // Getters and setters
        public UUID getTenantId() { return tenantId; }
        public void setTenantId(UUID tenantId) { this.tenantId = tenantId; }

        public String getTier() { return tier; }
        public void setTier(String tier) { this.tier = tier; }

        public String getOverallStatus() { return overallStatus; }
        public void setOverallStatus(String overallStatus) { this.overallStatus = overallStatus; }

        public double getUserUsage() { return userUsage; }
        public void setUserUsage(double userUsage) { this.userUsage = userUsage; }

        public double getDashboardUsage() { return dashboardUsage; }
        public void setDashboardUsage(double dashboardUsage) { this.dashboardUsage = dashboardUsage; }

        public double getStorageUsage() { return storageUsage; }
        public void setStorageUsage(double storageUsage) { this.storageUsage = storageUsage; }

        public double getDailyAlertUsage() { return dailyAlertUsage; }
        public void setDailyAlertUsage(double dailyAlertUsage) { this.dailyAlertUsage = dailyAlertUsage; }
    }

    // Event class for quota violations
    public static class QuotaViolationEvent {
        private final UUID tenantId;
        private final String resourceType;
        private final long currentUsage;
        private final long quotaLimit;
        private final double usagePercentage;

        public QuotaViolationEvent(UUID tenantId, String resourceType, long currentUsage, long quotaLimit, double usagePercentage) {
            this.tenantId = tenantId;
            this.resourceType = resourceType;
            this.currentUsage = currentUsage;
            this.quotaLimit = quotaLimit;
            this.usagePercentage = usagePercentage;
        }

        public UUID getTenantId() { return tenantId; }
        public String getResourceType() { return resourceType; }
        public long getCurrentUsage() { return currentUsage; }
        public long getQuotaLimit() { return quotaLimit; }
        public double getUsagePercentage() { return usagePercentage; }
    }
}
