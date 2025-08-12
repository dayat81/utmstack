package com.park.utmstack.service;

import com.park.utmstack.domain.UtmTenant;
import com.park.utmstack.domain.UtmTenantConfig;
import com.park.utmstack.repository.UtmTenantRepository;
import com.park.utmstack.repository.UtmTenantConfigRepository;
import com.park.utmstack.service.dto.tenant.QuotaCheckResult;
import com.park.utmstack.service.dto.tenant.ResourceQuotaStatus;
import com.park.utmstack.service.dto.tenant.TenantResourceUsage;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.HashMap;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

@Service
@Transactional
public class TenantResourceQuotaService {

    private static final Logger log = LoggerFactory.getLogger(TenantResourceQuotaService.class);

    @Autowired
    private UtmTenantRepository tenantRepository;

    @Autowired
    private UtmTenantConfigRepository tenantConfigRepository;

    // In-memory cache for resource usage tracking
    private final Map<UUID, Map<String, Integer>> resourceUsageCache = new ConcurrentHashMap<>();

    private static final Map<String, Integer> DEFAULT_QUOTAS = Map.of(
        "max_users", 100,
        "max_dashboards", 50,
        "max_alerts", 1000,
        "max_storage_gb", 10
    );

    public static class QuotaExceededException extends RuntimeException {
        public QuotaExceededException(String message) {
            super(message);
        }
    }

    public static class QuotaViolationEvent {
        private UUID tenantId;
        private String resource;
        private int currentUsage;
        private int limit;

        public QuotaViolationEvent(UUID tenantId, String resource, int currentUsage, int limit) {
            this.tenantId = tenantId;
            this.resource = resource;
            this.currentUsage = currentUsage;
            this.limit = limit;
        }

        public UUID getTenantId() { return tenantId; }
        public String getResource() { return resource; }
        public int getCurrentUsage() { return currentUsage; }
        public int getLimit() { return limit; }
    }

    public ResourceQuotaStatus getResourceQuotaStatus(UUID tenantId) {
        try {
            UtmTenant tenant = tenantRepository.findById(tenantId).orElse(null);
            if (tenant == null) {
                ResourceQuotaStatus status = new ResourceQuotaStatus();
                status.setOverallStatus("TENANT_NOT_FOUND");
                return status;
            }

            Map<String, Integer> usage = getTenantResourceUsage(tenantId).getUsage();
            Map<String, Integer> limits = getTenantResourceLimits(tenantId);

            boolean withinLimits = true;
            for (String resource : usage.keySet()) {
                int currentUsage = usage.get(resource);
                int limit = limits.getOrDefault(resource, DEFAULT_QUOTAS.getOrDefault(resource, Integer.MAX_VALUE));
                if (currentUsage > limit) {
                    withinLimits = false;
                    break;
                }
            }

            ResourceQuotaStatus status = new ResourceQuotaStatus();
            status.setOverallStatus(withinLimits ? "WITHIN_LIMITS" : "QUOTA_EXCEEDED");
            status.setUsage(usage);
            status.setLimits(limits);
            return status;

        } catch (Exception e) {
            log.error("Failed to get resource quota status for tenant: {}", tenantId, e);
            ResourceQuotaStatus status = new ResourceQuotaStatus();
            status.setOverallStatus("ERROR");
            return status;
        }
    }

    public void updateTenantResourceLimits(UUID tenantId, Map<String, Integer> resourceLimits) {
        try {
            UtmTenant tenant = tenantRepository.findById(tenantId).orElse(null);
            if (tenant == null) {
                throw new RuntimeException("Tenant not found: " + tenantId);
            }

            for (Map.Entry<String, Integer> entry : resourceLimits.entrySet()) {
                String configKey = entry.getKey();
                String configValue = entry.getValue().toString();

                UtmTenantConfig config = tenantConfigRepository
                    .findByTenantIdAndConfigKey(tenantId, configKey)
                    .orElse(new UtmTenantConfig());

                config.setTenant(tenant);
                config.setConfigKey(configKey);
                config.setConfigValue(configValue);
                config.setConfigType("LIMIT");

                tenantConfigRepository.save(config);
            }

            log.info("Updated resource limits for tenant: {}", tenantId);
        } catch (Exception e) {
            log.error("Failed to update resource limits for tenant: {}", tenantId, e);
            throw new RuntimeException("Failed to update resource limits", e);
        }
    }

    public TenantResourceUsage getTenantResourceUsage(UUID tenantId) {
        try {
            Map<String, Integer> usage = resourceUsageCache.getOrDefault(tenantId, new HashMap<>());
            
            // Initialize with zero usage if not exists
            for (String resource : DEFAULT_QUOTAS.keySet()) {
                usage.putIfAbsent(resource, 0);
            }

            TenantResourceUsage resourceUsage = new TenantResourceUsage();
            resourceUsage.setUsage(usage);
            return resourceUsage;

        } catch (Exception e) {
            log.error("Failed to get resource usage for tenant: {}", tenantId, e);
            TenantResourceUsage resourceUsage = new TenantResourceUsage();
            resourceUsage.setUsage(new HashMap<>());
            return resourceUsage;
        }
    }

    public QuotaCheckResult checkResourceQuota(UUID tenantId, String resource, int amount) {
        try {
            Map<String, Integer> usage = getTenantResourceUsage(tenantId).getUsage();
            Map<String, Integer> limits = getTenantResourceLimits(tenantId);

            int currentUsage = usage.getOrDefault(resource, 0);
            int limit = limits.getOrDefault(resource, DEFAULT_QUOTAS.getOrDefault(resource, Integer.MAX_VALUE));

            boolean allowed = (currentUsage + amount) <= limit;

            QuotaCheckResult result = new QuotaCheckResult();
            result.setAllowed(allowed);
            result.setCurrentUsage(currentUsage);
            result.setLimit(limit);
            result.setRequestedAmount(amount);

            if (!allowed) {
                log.warn("Quota check failed for tenant {} resource {}: current={}, requested={}, limit={}", 
                    tenantId, resource, currentUsage, amount, limit);
            }

            return result;

        } catch (Exception e) {
            log.error("Failed to check resource quota for tenant: {} resource: {}", tenantId, resource, e);
            QuotaCheckResult result = new QuotaCheckResult();
            result.setAllowed(false);
            return result;
        }
    }

    public void recordResourceUsage(UUID tenantId, String resource, int amount) {
        try {
            resourceUsageCache.computeIfAbsent(tenantId, k -> new ConcurrentHashMap<>());
            resourceUsageCache.get(tenantId).merge(resource, amount, Integer::sum);

            log.debug("Recorded resource usage for tenant {} resource {}: +{}", tenantId, resource, amount);

        } catch (Exception e) {
            log.error("Failed to record resource usage for tenant: {} resource: {}", tenantId, resource, e);
        }
    }

    private Map<String, Integer> getTenantResourceLimits(UUID tenantId) {
        Map<String, Integer> limits = new HashMap<>(DEFAULT_QUOTAS);

        try {
            var configs = tenantConfigRepository.findByTenantIdAndConfigType(tenantId, "LIMIT");
            for (UtmTenantConfig config : configs) {
                try {
                    int value = Integer.parseInt(config.getConfigValue());
                    limits.put(config.getConfigKey(), value);
                } catch (NumberFormatException e) {
                    log.warn("Invalid limit value for tenant {} config {}: {}", 
                        tenantId, config.getConfigKey(), config.getConfigValue());
                }
            }
        } catch (Exception e) {
            log.error("Failed to get resource limits for tenant: {}", tenantId, e);
        }

        return limits;
    }

    public void incrementResourceUsage(UUID tenantId, String resource) {
        recordResourceUsage(tenantId, resource, 1);
    }

    public void decrementResourceUsage(UUID tenantId, String resource) {
        recordResourceUsage(tenantId, resource, -1);
    }

    public boolean enforceQuota(UUID tenantId, String resource, int amount) {
        QuotaCheckResult result = checkResourceQuota(tenantId, resource, amount);
        if (!result.isAllowed()) {
            throw new QuotaExceededException(
                String.format("Quota exceeded for resource %s: current=%d, requested=%d, limit=%d",
                    resource, result.getCurrentUsage(), amount, result.getLimit()));
        }
        recordResourceUsage(tenantId, resource, amount);
        return true;
    }
}