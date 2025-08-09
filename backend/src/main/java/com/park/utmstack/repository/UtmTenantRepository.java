package com.park.utmstack.repository;

import com.park.utmstack.domain.UtmTenant;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

/**
 * Repository for UtmTenant entity.
 */
@Repository
public interface UtmTenantRepository extends JpaRepository<UtmTenant, UUID> {

    /**
     * Find tenant by subdomain
     */
    Optional<UtmTenant> findBySubdomain(String subdomain);

    /**
     * Find tenant by name
     */
    Optional<UtmTenant> findByName(String name);

    /**
     * Find tenants by status
     */
    List<UtmTenant> findByStatus(String status);

    /**
     * Find active tenants
     */
    @Query("SELECT t FROM UtmTenant t WHERE t.status = 'active'")
    List<UtmTenant> findAllActiveTenants();

    /**
     * Find tenants by tier
     */
    List<UtmTenant> findByTier(String tier);

    /**
     * Find tenants with pagination
     */
    Page<UtmTenant> findByStatusOrderByCreatedAtDesc(String status, Pageable pageable);

    /**
     * Check if subdomain exists
     */
    boolean existsBySubdomain(String subdomain);

    /**
     * Check if name exists
     */
    boolean existsByName(String name);

    /**
     * Find tenants created after a specific date
     */
    @Query("SELECT t FROM UtmTenant t WHERE t.createdAt >= :date ORDER BY t.createdAt DESC")
    List<UtmTenant> findTenantsCreatedAfter(@Param("date") java.time.Instant date);

    /**
     * Count tenants by status
     */
    long countByStatus(String status);

    /**
     * Find tenants by name pattern (case-insensitive)
     */
    @Query("SELECT t FROM UtmTenant t WHERE LOWER(t.name) LIKE LOWER(CONCAT('%', :name, '%'))")
    List<UtmTenant> findByNameContainingIgnoreCase(@Param("name") String name);

    /**
     * Find tenants that exceed resource thresholds
     */
    @Query("SELECT t FROM UtmTenant t WHERE " +
           "CAST(JSON_EXTRACT(t.resourceLimits, '$.max_users') AS INTEGER) < :currentUsers OR " +
           "CAST(JSON_EXTRACT(t.resourceLimits, '$.max_dashboards') AS INTEGER) < :currentDashboards")
    List<UtmTenant> findTenantsExceedingLimits(@Param("currentUsers") int currentUsers, 
                                               @Param("currentDashboards") int currentDashboards);

    /**
     * Find default tenant (for migration purposes)
     */
    @Query("SELECT t FROM UtmTenant t WHERE t.subdomain = 'default' OR " +
           "JSON_EXTRACT(t.settings, '$.legacy_migration') = 'true'")
    Optional<UtmTenant> findDefaultTenant();
}
