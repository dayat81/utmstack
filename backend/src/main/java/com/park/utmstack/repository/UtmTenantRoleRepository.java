package com.park.utmstack.repository;

import com.park.utmstack.domain.UtmTenantRole;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

/**
 * Repository for UtmTenantRole entity.
 */
@Repository
public interface UtmTenantRoleRepository extends JpaRepository<UtmTenantRole, UUID> {

    /**
     * Find role by tenant and role name
     */
    Optional<UtmTenantRole> findByTenantIdAndRoleName(UUID tenantId, String roleName);

    /**
     * Find all roles for a tenant
     */
    List<UtmTenantRole> findByTenantIdOrderByRoleName(UUID tenantId);

    /**
     * Find roles by name across all tenants
     */
    List<UtmTenantRole> findByRoleName(String roleName);

    /**
     * Find child roles for a parent role
     */
    List<UtmTenantRole> findByParentRoleId(UUID parentRoleId);

    /**
     * Find root roles (no parent) for a tenant
     */
    @Query("SELECT tr FROM UtmTenantRole tr WHERE tr.tenantId = :tenantId AND tr.parentRoleId IS NULL")
    List<UtmTenantRole> findRootRolesByTenant(@Param("tenantId") UUID tenantId);

    /**
     * Check if role exists for tenant
     */
    boolean existsByTenantIdAndRoleName(UUID tenantId, String roleName);

    /**
     * Delete role by tenant and name
     */
    void deleteByTenantIdAndRoleName(UUID tenantId, String roleName);

    /**
     * Delete all roles for a tenant
     */
    void deleteByTenantId(UUID tenantId);

    /**
     * Count roles per tenant
     */
    long countByTenantId(UUID tenantId);

    /**
     * Find roles with specific permission
     */
    @Query("SELECT tr FROM UtmTenantRole tr WHERE JSON_CONTAINS(tr.permissions, :permission)")
    List<UtmTenantRole> findRolesWithPermission(@Param("permission") String permission);

    /**
     * Find tenant admin roles
     */
    @Query("SELECT tr FROM UtmTenantRole tr WHERE tr.roleName LIKE '%ADMIN%' OR " +
           "JSON_CONTAINS(tr.permissions, '\"USER_MANAGEMENT\"')")
    List<UtmTenantRole> findAdminRoles();

    /**
     * Find effective roles (including inherited from parent)
     */
    @Query("WITH RECURSIVE role_hierarchy AS (" +
           "SELECT id, tenant_id, role_name, permissions, parent_role_id, 0 as level " +
           "FROM utm_tenant_role WHERE tenant_id = :tenantId AND role_name = :roleName " +
           "UNION ALL " +
           "SELECT r.id, r.tenant_id, r.role_name, r.permissions, r.parent_role_id, rh.level + 1 " +
           "FROM utm_tenant_role r " +
           "INNER JOIN role_hierarchy rh ON r.id = rh.parent_role_id " +
           "WHERE rh.level < 10) " +
           "SELECT DISTINCT r.* FROM UtmTenantRole r " +
           "INNER JOIN role_hierarchy rh ON r.id = rh.id")
    List<UtmTenantRole> findEffectiveRoles(@Param("tenantId") UUID tenantId, @Param("roleName") String roleName);

    /**
     * Find all distinct role names across tenants
     */
    @Query("SELECT DISTINCT tr.roleName FROM UtmTenantRole tr ORDER BY tr.roleName")
    List<String> findAllDistinctRoleNames();

    /**
     * Find roles by permission pattern
     */
    @Query("SELECT tr FROM UtmTenantRole tr WHERE tr.permissions LIKE %:permissionPattern%")
    List<UtmTenantRole> findRolesByPermissionPattern(@Param("permissionPattern") String permissionPattern);
}
