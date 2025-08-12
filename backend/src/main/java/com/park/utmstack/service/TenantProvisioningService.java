package com.park.utmstack.service;

import com.park.utmstack.domain.UtmTenant;
import com.park.utmstack.domain.UtmTenantConfig;
import com.park.utmstack.repository.UtmTenantRepository;
import com.park.utmstack.repository.UtmTenantConfigRepository;
import com.park.utmstack.web.rest.ProvisioningStatus;
import com.park.utmstack.web.rest.TenantDeprovisioningResult;
import com.park.utmstack.web.rest.TenantProvisioningResult;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;

@Service
@Transactional
public class TenantProvisioningService {

    private static final Logger log = LoggerFactory.getLogger(TenantProvisioningService.class);

    public static class TenantProvisioningRequest {
        private String name;
        private String subdomain;
        private String tier;

        public String getName() {
            return name;
        }

        public void setName(String name) {
            this.name = name;
        }

        public String getSubdomain() {
            return subdomain;
        }

        public void setSubdomain(String subdomain) {
            this.subdomain = subdomain;
        }

        public String getTier() {
            return tier;
        }

        public void setTier(String tier) {
            this.tier = tier;
        }
    }

    @Autowired
    private UtmTenantRepository tenantRepository;

    @Autowired
    private UtmTenantConfigRepository tenantConfigRepository;

    public CompletableFuture<TenantProvisioningResult> provisionTenant(TenantProvisioningRequest request) {
        return CompletableFuture.supplyAsync(() -> {
            try {
                log.info("Starting tenant provisioning for: {}", request.getName());
                
                // Create tenant entity
                UtmTenant tenant = new UtmTenant();
                tenant.setId(UUID.randomUUID());
                tenant.setName(request.getName());
                tenant.setSubdomain(request.getSubdomain());
                tenant.setStatus("ACTIVE");
                tenant.setTier(request.getTier() != null ? request.getTier() : "BASIC");
                tenant.setCreatedAt(Instant.now());
                
                // Save tenant
                tenant = tenantRepository.save(tenant);
                
                // Create default tenant config
                UtmTenantConfig config = new UtmTenantConfig();
                config.setId(UUID.randomUUID());
                config.setTenant(tenant);
                config.setConfigKey("max_users");
                config.setConfigValue("100");
                config.setConfigType("LIMIT");
                tenantConfigRepository.save(config);
                
                // Create success result
                TenantProvisioningResult result = new TenantProvisioningResult();
                result.setStatus("SUCCESS");
                
                log.info("Successfully provisioned tenant: {} with ID: {}", request.getName(), tenant.getId());
                return result;
                
            } catch (Exception e) {
                log.error("Failed to provision tenant: {}", request.getName(), e);
                TenantProvisioningResult result = new TenantProvisioningResult();
                result.setStatus("FAILED");
                result.setError(e.getMessage());
                return result;
            }
        });
    }

    public CompletableFuture<TenantDeprovisioningResult> deprovisionTenant(UUID tenantId, boolean forceDelete) {
        return CompletableFuture.supplyAsync(() -> {
            try {
                log.info("Starting tenant deprovisioning for: {}", tenantId);
                
                // Find tenant
                UtmTenant tenant = tenantRepository.findById(tenantId).orElse(null);
                if (tenant == null) {
                    TenantDeprovisioningResult result = new TenantDeprovisioningResult();
                    result.setStatus("NOT_FOUND");
                    result.setError("Tenant not found: " + tenantId);
                    return result;
                }
                
                // Delete tenant configs
                tenantConfigRepository.deleteByTenantId(tenantId);
                
                // Delete tenant
                tenantRepository.delete(tenant);
                
                TenantDeprovisioningResult result = new TenantDeprovisioningResult();
                result.setStatus("SUCCESS");
                
                log.info("Successfully deprovisioned tenant: {}", tenantId);
                return result;
                
            } catch (Exception e) {
                log.error("Failed to deprovision tenant: {}", tenantId, e);
                TenantDeprovisioningResult result = new TenantDeprovisioningResult();
                result.setStatus("FAILED");
                result.setError(e.getMessage());
                return result;
            }
        });
    }

    public ProvisioningStatus getProvisioningStatus(UUID tenantId) {
        try {
            UtmTenant tenant = tenantRepository.findById(tenantId).orElse(null);
            ProvisioningStatus status = new ProvisioningStatus();
            status.setOverallReady(tenant != null && "ACTIVE".equals(tenant.getStatus()));
            return status;
        } catch (Exception e) {
            log.error("Failed to get provisioning status for tenant: {}", tenantId, e);
            ProvisioningStatus status = new ProvisioningStatus();
            status.setOverallReady(false);
            return status;
        }
    }
}