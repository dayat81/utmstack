package com.park.utmstack.service;

import com.park.utmstack.domain.UtmTenant;
import com.park.utmstack.domain.UtmTenantConfig;
import com.park.utmstack.domain.UtmTenantRole;
import com.park.utmstack.repository.UtmTenantConfigRepository;
import com.park.utmstack.repository.UtmTenantRepository;
import com.park.utmstack.repository.UtmTenantRoleRepository;
import com.park.utmstack.security.TenantContext;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

/**
 * Service for managing tenant operations.
 */
@Service
@Transactional
public class TenantService {

    private static final Logger log = LoggerFactory.getLogger(TenantService.class);

    private final UtmTenantRepository tenantRepository;
    private final UtmTenantConfigRepository tenantConfigRepository;
    private final UtmTenantRoleRepository tenantRoleRepository;

    public TenantService(UtmTenantRepository tenantRepository,
                        UtmTenantConfigRepository tenantConfigRepository,
                        UtmTenantRoleRepository tenantRoleRepository) {
        this.tenantRepository = tenantRepository;
        this.tenantConfigRepository = tenantConfigRepository;
        this.tenantRoleRepository = tenantRoleRepository;
    }

    /**
     * Create a new tenant with default configuration
     */
    public UtmTenant createTenant(String name, String subdomain, String tier) {
        log.info("Creating new tenant: name={}, subdomain={}, tier={}", name, subdomain, tier);

        // Check if subdomain already exists
        if (tenantRepository.existsBySubdomain(subdomain)) {
            throw new IllegalArgumentException("Subdomain already exists: " + subdomain);
        }

        // Check if name already exists
        if (tenantRepository.existsByName(name)) {
            throw new IllegalArgumentException("Tenant name already exists: " + name);
        }

        // Create tenant
        UtmTenant tenant = new UtmTenant();
        tenant.setName(name);
        tenant.setSubdomain(subdomain);
        tenant.setTier(tier != null ? tier : "standard");
        tenant.setStatus("active");
        tenant.setCreatedAt(Instant.now());
        tenant.setUpdatedAt(Instant.now());

        // Set default settings based on tier
        String defaultSettings = getDefaultSettingsForTier(tier);
        tenant.setSettings(defaultSettings);

        // Set default resource limits based on tier
        String defaultLimits = getDefaultResourceLimitsForTier(tier);
        tenant.setResourceLimits(defaultLimits);

        tenant = tenantRepository.save(tenant);

        // Create default configuration
        createDefaultTenantConfiguration(tenant.getId());

        // Create default roles
        createDefaultTenantRoles(tenant.getId());

        log.info("Created tenant: id={}, name={}, subdomain={}", tenant.getId(), name, subdomain);
        return tenant;
    }

    /**
     * Get tenant by ID
     */
    @Transactional(readOnly = true)
    public Optional<UtmTenant> getTenant(UUID tenantId) {
        return tenantRepository.findById(tenantId);
    }

    /**
     * Get tenant by subdomain
     */
    @Transactional(readOnly = true)
    public Optional<UtmTenant> getTenantBySubdomain(String subdomain) {
        return tenantRepository.findBySubdomain(subdomain);
    }

    /**
     * Get all active tenants
     */
    @Transactional(readOnly = true)
    public List<UtmTenant> getAllActiveTenants() {
        return tenantRepository.findAllActiveTenants();
    }

    /**
     * Check if tenant is active
     */
    @Transactional(readOnly = true)
    public boolean isActiveTenant(String tenantId) {
        try {
            UUID tenantUUID = UUID.fromString(tenantId);
            Optional<UtmTenant> tenant = tenantRepository.findById(tenantUUID);
            return tenant.isPresent() && "active".equals(tenant.get().getStatus());
        } catch (IllegalArgumentException e) {
            log.warn("Invalid tenant ID format: {}", tenantId);
            return false;
        }
    }

    /**
     * Update tenant status
     */
    public UtmTenant updateTenantStatus(UUID tenantId, String status) {
        log.info("Updating tenant status: tenantId={}, status={}", tenantId, status);

        UtmTenant tenant = tenantRepository.findById(tenantId)
            .orElseThrow(() -> new IllegalArgumentException("Tenant not found: " + tenantId));

        tenant.setStatus(status);
        tenant.setUpdatedAt(Instant.now());

        return tenantRepository.save(tenant);
    }

    /**
     * Get tenant configuration value
     */
    @Transactional(readOnly = true)
    public Optional<String> getTenantConfigValue(UUID tenantId, String configKey) {
        Optional<UtmTenantConfig> config = tenantConfigRepository.findByTenantIdAndConfigKey(tenantId, configKey);
        return config.map(UtmTenantConfig::getConfigValue);
    }

    /**
     * Set tenant configuration value
     */
    public void setTenantConfigValue(UUID tenantId, String configKey, String configValue, String configType) {
        log.debug("Setting tenant config: tenantId={}, key={}, value={}", tenantId, configKey, configValue);

        Optional<UtmTenantConfig> existingConfig = tenantConfigRepository.findByTenantIdAndConfigKey(tenantId, configKey);

        if (existingConfig.isPresent()) {
            UtmTenantConfig config = existingConfig.get();
            config.setConfigValue(configValue);
            config.setConfigType(configType != null ? configType : "STRING");
            config.setUpdatedAt(Instant.now());
            tenantConfigRepository.save(config);
        } else {
            UtmTenant tenant = tenantRepository.findById(tenantId)
                .orElseThrow(() -> new IllegalArgumentException("Tenant not found: " + tenantId));

            UtmTenantConfig config = new UtmTenantConfig();
            config.setTenant(tenant);
            config.setConfigKey(configKey);
            config.setConfigValue(configValue);
            config.setConfigType(configType != null ? configType : "STRING");
            config.setCreatedAt(Instant.now());
            config.setUpdatedAt(Instant.now());
            tenantConfigRepository.save(config);
        }
    }

    /**
     * Get all tenant configurations
     */
    @Transactional(readOnly = true)
    public List<UtmTenantConfig> getTenantConfigurations(UUID tenantId) {
        return tenantConfigRepository.findByTenantIdOrderByConfigKey(tenantId);
    }

    /**
     * Get tenant role
     */
    @Transactional(readOnly = true)
    public Optional<UtmTenantRole> getTenantRole(UUID tenantId, String roleName) {
        return tenantRoleRepository.findByTenantIdAndRoleName(tenantId, roleName);
    }

    /**
     * Get all tenant roles
     */
    @Transactional(readOnly = true)
    public List<UtmTenantRole> getTenantRoles(UUID tenantId) {
        return tenantRoleRepository.findByTenantIdOrderByRoleName(tenantId);
    }

    /**
     * Get current tenant from context
     */
    @Transactional(readOnly = true)
    public Optional<UtmTenant> getCurrentTenant() {
        String tenantId = TenantContext.getCurrentTenant();
        if (tenantId != null) {
            try {
                UUID tenantUUID = UUID.fromString(tenantId);
                return tenantRepository.findById(tenantUUID);
            } catch (IllegalArgumentException e) {
                log.warn("Invalid tenant ID in context: {}", tenantId);
            }
        }
        return Optional.empty();
    }

    /**
     * Create default tenant configuration
     */
    private void createDefaultTenantConfiguration(UUID tenantId) {
        log.debug("Creating default configuration for tenant: {}", tenantId);

        UtmTenant tenant = tenantRepository.findById(tenantId)
            .orElseThrow(() -> new IllegalArgumentException("Tenant not found: " + tenantId));

        // Default configurations
        String[][] defaultConfigs = {
            {"timezone", "UTC", "STRING"},
            {"date_format", "YYYY-MM-DD", "STRING"},
            {"max_retention_days", "365", "INTEGER"},
            {"enable_sso", "false", "BOOLEAN"},
            {"session_timeout", "8", "INTEGER"},
            {"max_failed_login_attempts", "5", "INTEGER"},
            {"password_min_length", "8", "INTEGER"},
            {"require_password_change", "true", "BOOLEAN"}
        };

        for (String[] config : defaultConfigs) {
            UtmTenantConfig tenantConfig = new UtmTenantConfig();
            tenantConfig.setTenant(tenant);
            tenantConfig.setConfigKey(config[0]);
            tenantConfig.setConfigValue(config[1]);
            tenantConfig.setConfigType(config[2]);
            tenantConfig.setCreatedAt(Instant.now());
            tenantConfig.setUpdatedAt(Instant.now());
            tenantConfigRepository.save(tenantConfig);
        }
    }

    /**
     * Create default tenant roles
     */
    private void createDefaultTenantRoles(UUID tenantId) {
        log.debug("Creating default roles for tenant: {}", tenantId);

        UtmTenant tenant = tenantRepository.findById(tenantId)
            .orElseThrow(() -> new IllegalArgumentException("Tenant not found: " + tenantId));

        // Default roles
        String[][] defaultRoles = {
            {"TENANT_ADMIN", "[\"USER_MANAGEMENT\", \"DASHBOARD_MANAGEMENT\", \"ALERT_MANAGEMENT\", \"CONFIGURATION\", \"REPORTS\", \"INCIDENT_MANAGEMENT\"]"},
            {"ANALYST", "[\"DASHBOARD_VIEW\", \"DASHBOARD_CREATE\", \"ALERT_MANAGEMENT\", \"INCIDENT_MANAGEMENT\", \"REPORTS_VIEW\"]"},
            {"TENANT_USER", "[\"DASHBOARD_VIEW\", \"ALERT_VIEW\", \"REPORTS_VIEW\"]"},
            {"VIEWER", "[\"DASHBOARD_VIEW\", \"REPORTS_VIEW\"]"}
        };

        for (String[] role : defaultRoles) {
            UtmTenantRole tenantRole = new UtmTenantRole();
            tenantRole.setTenant(tenant);
            tenantRole.setRoleName(role[0]);
            tenantRole.setPermissions(role[1]);
            tenantRole.setCreatedAt(Instant.now());
            tenantRole.setUpdatedAt(Instant.now());
            tenantRoleRepository.save(tenantRole);
        }
    }

    /**
     * Get default settings for tier
     */
    private String getDefaultSettingsForTier(String tier) {
        switch (tier != null ? tier.toLowerCase() : "standard") {
            case "enterprise":
                return "{\"support_level\": \"premium\", \"sla_level\": \"99.95\", \"backup_retention\": \"7_years\", \"audit_level\": \"full\"}";
            case "professional":
                return "{\"support_level\": \"business\", \"sla_level\": \"99.9\", \"backup_retention\": \"3_years\", \"audit_level\": \"standard\"}";
            case "standard":
            default:
                return "{\"support_level\": \"standard\", \"sla_level\": \"99.5\", \"backup_retention\": \"1_year\", \"audit_level\": \"basic\"}";
        }
    }

    /**
     * Get default resource limits for tier
     */
    private String getDefaultResourceLimitsForTier(String tier) {
        switch (tier != null ? tier.toLowerCase() : "standard") {
            case "enterprise":
                return "{\"max_users\": 1000, \"max_dashboards\": 100, \"max_alerts_per_day\": 1000000, \"storage_gb\": 1000}";
            case "professional":
                return "{\"max_users\": 100, \"max_dashboards\": 50, \"max_alerts_per_day\": 100000, \"storage_gb\": 100}";
            case "standard":
            default:
                return "{\"max_users\": 25, \"max_dashboards\": 10, \"max_alerts_per_day\": 10000, \"storage_gb\": 10}";
        }
    }
}
