package com.park.utmstack.repository;

import com.park.utmstack.domain.UtmTenantConfig;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

/**
 * Repository for UtmTenantConfig entity.
 */
@Repository
public interface UtmTenantConfigRepository extends JpaRepository<UtmTenantConfig, UUID> {

    /**
     * Find configuration by tenant and key
     */
    Optional<UtmTenantConfig> findByTenantIdAndConfigKey(UUID tenantId, String configKey);

    /**
     * Find all configurations for a tenant
     */
    List<UtmTenantConfig> findByTenantIdOrderByConfigKey(UUID tenantId);

    /**
     * Find configurations by key across all tenants
     */
    List<UtmTenantConfig> findByConfigKey(String configKey);

    /**
     * Find configurations by type
     */
    List<UtmTenantConfig> findByConfigType(String configType);

    /**
     * Find configurations by tenant and type
     */
    List<UtmTenantConfig> findByTenantIdAndConfigType(UUID tenantId, String configType);

    /**
     * Check if configuration exists for tenant
     */
    boolean existsByTenantIdAndConfigKey(UUID tenantId, String configKey);

    /**
     * Delete configuration by tenant and key
     */
    void deleteByTenantIdAndConfigKey(UUID tenantId, String configKey);

    /**
     * Delete all configurations for a tenant
     */
    void deleteByTenantId(UUID tenantId);

    /**
     * Find configurations with specific value
     */
    List<UtmTenantConfig> findByConfigValue(String configValue);

    /**
     * Find configurations by value pattern
     */
    @Query("SELECT tc FROM UtmTenantConfig tc WHERE tc.configValue LIKE %:pattern%")
    List<UtmTenantConfig> findByConfigValueContaining(@Param("pattern") String pattern);

    /**
     * Count configurations per tenant
     */
    long countByTenantId(UUID tenantId);

    /**
     * Find boolean configurations by tenant
     */
    @Query("SELECT tc FROM UtmTenantConfig tc WHERE tc.tenantId = :tenantId AND tc.configType = 'BOOLEAN'")
    List<UtmTenantConfig> findBooleanConfigsByTenant(@Param("tenantId") UUID tenantId);

    /**
     * Find system-wide configuration keys
     */
    @Query("SELECT DISTINCT tc.configKey FROM UtmTenantConfig tc ORDER BY tc.configKey")
    List<String> findAllDistinctConfigKeys();
}
