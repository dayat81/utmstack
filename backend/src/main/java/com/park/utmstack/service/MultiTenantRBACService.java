package com.park.utmstack.service;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.park.utmstack.domain.UtmTenantRole;
import com.park.utmstack.repository.UtmTenantRoleRepository;
import com.park.utmstack.security.TenantContext;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.*;
import java.util.stream.Collectors;

/**
 * Service for multi-tenant Role-Based Access Control (RBAC).
 */
@Service
@Transactional
public class MultiTenantRBACService {

    private static final Logger log = LoggerFactory.getLogger(MultiTenantRBACService.class);

    private final UtmTenantRoleRepository tenantRoleRepository;
    private final ObjectMapper objectMapper;

    // Predefined permissions for different functional areas
    public static final class Permissions {
        // User Management
        public static final String USER_MANAGEMENT = "USER_MANAGEMENT";
        public static final String USER_CREATE = "USER_CREATE";
        public static final String USER_VIEW = "USER_VIEW";
        public static final String USER_UPDATE = "USER_UPDATE";
        public static final String USER_DELETE = "USER_DELETE";

        // Dashboard Management
        public static final String DASHBOARD_MANAGEMENT = "DASHBOARD_MANAGEMENT";
        public static final String DASHBOARD_CREATE = "DASHBOARD_CREATE";
        public static final String DASHBOARD_VIEW = "DASHBOARD_VIEW";
        public static final String DASHBOARD_UPDATE = "DASHBOARD_UPDATE";
        public static final String DASHBOARD_DELETE = "DASHBOARD_DELETE";

        // Alert Management
        public static final String ALERT_MANAGEMENT = "ALERT_MANAGEMENT";
        public static final String ALERT_VIEW = "ALERT_VIEW";
        public static final String ALERT_CREATE = "ALERT_CREATE";
        public static final String ALERT_UPDATE = "ALERT_UPDATE";
        public static final String ALERT_DELETE = "ALERT_DELETE";

        // Incident Management
        public static final String INCIDENT_MANAGEMENT = "INCIDENT_MANAGEMENT";
        public static final String INCIDENT_VIEW = "INCIDENT_VIEW";
        public static final String INCIDENT_CREATE = "INCIDENT_CREATE";
        public static final String INCIDENT_UPDATE = "INCIDENT_UPDATE";
        public static final String INCIDENT_DELETE = "INCIDENT_DELETE";

        // Configuration
        public static final String CONFIGURATION = "CONFIGURATION";
        public static final String CONFIG_VIEW = "CONFIG_VIEW";
        public static final String CONFIG_UPDATE = "CONFIG_UPDATE";

        // Reports
        public static final String REPORTS = "REPORTS";
        public static final String REPORTS_VIEW = "REPORTS_VIEW";
        public static final String REPORTS_CREATE = "REPORTS_CREATE";
        public static final String REPORTS_EXPORT = "REPORTS_EXPORT";

        // System Administration (for tenant admins)
        public static final String TENANT_ADMIN = "TENANT_ADMIN";
        public static final String SYSTEM_SETTINGS = "SYSTEM_SETTINGS";
        public static final String AUDIT_LOGS = "AUDIT_LOGS";
    }

    public MultiTenantRBACService(UtmTenantRoleRepository tenantRoleRepository) {
        this.tenantRoleRepository = tenantRoleRepository;
        this.objectMapper = new ObjectMapper();
    }

    /**
     * Check if the current user has a specific permission within their tenant
     */
    @Transactional(readOnly = true)
    public boolean hasPermission(String permission) {
        String currentTenantRole = TenantContext.getCurrentTenantRole();
        UUID currentTenantId = TenantContext.getCurrentTenantAsUUID();

        if (currentTenantRole == null || currentTenantId == null) {
            log.debug("No tenant context available for permission check: {}", permission);
            return false;
        }

        return hasPermission(currentTenantId, currentTenantRole, permission);
    }

    /**
     * Check if a user has a specific permission within a tenant
     */
    @Transactional(readOnly = true)
    public boolean hasPermission(UUID tenantId, String roleName, String permission) {
        try {
            Set<String> effectivePermissions = getEffectivePermissions(tenantId, roleName);
            boolean hasPermission = effectivePermissions.contains(permission);
            
            log.debug("Permission check: tenant={}, role={}, permission={}, result={}", 
                tenantId, roleName, permission, hasPermission);
            
            return hasPermission;
        } catch (Exception e) {
            log.error("Error checking permission: tenant={}, role={}, permission={}", 
                tenantId, roleName, permission, e);
            return false;
        }
    }

    /**
     * Check if the current user has any of the specified permissions
     */
    @Transactional(readOnly = true)
    public boolean hasAnyPermission(String... permissions) {
        if (permissions == null || permissions.length == 0) {
            return false;
        }

        for (String permission : permissions) {
            if (hasPermission(permission)) {
                return true;
            }
        }
        return false;
    }

    /**
     * Check if the current user has all of the specified permissions
     */
    @Transactional(readOnly = true)
    public boolean hasAllPermissions(String... permissions) {
        if (permissions == null || permissions.length == 0) {
            return true;
        }

        for (String permission : permissions) {
            if (!hasPermission(permission)) {
                return false;
            }
        }
        return true;
    }

    /**
     * Get effective permissions for a role (including inherited permissions)
     */
    @Transactional(readOnly = true)
    public Set<String> getEffectivePermissions(UUID tenantId, String roleName) {
        Set<String> effectivePermissions = new HashSet<>();
        Set<String> visitedRoles = new HashSet<>();

        collectPermissions(tenantId, roleName, effectivePermissions, visitedRoles);

        return effectivePermissions;
    }

    /**
     * Recursively collect permissions from role hierarchy
     */
    private void collectPermissions(UUID tenantId, String roleName, Set<String> permissions, Set<String> visitedRoles) {
        // Prevent infinite recursion
        if (visitedRoles.contains(roleName)) {
            log.warn("Circular dependency detected in role hierarchy: {}", roleName);
            return;
        }
        visitedRoles.add(roleName);

        Optional<UtmTenantRole> roleOpt = tenantRoleRepository.findByTenantIdAndRoleName(tenantId, roleName);
        if (!roleOpt.isPresent()) {
            log.warn("Role not found: tenant={}, role={}", tenantId, roleName);
            return;
        }

        UtmTenantRole role = roleOpt.get();

        // Add permissions from current role
        Set<String> rolePermissions = parsePermissions(role.getPermissions());
        permissions.addAll(rolePermissions);

        // Add permissions from parent role if exists
        if (role.getParentRoleId() != null) {
            Optional<UtmTenantRole> parentRoleOpt = tenantRoleRepository.findById(role.getParentRoleId());
            if (parentRoleOpt.isPresent()) {
                collectPermissions(tenantId, parentRoleOpt.get().getRoleName(), permissions, visitedRoles);
            }
        }
    }

    /**
     * Parse JSON permissions array
     */
    private Set<String> parsePermissions(String permissionsJson) {
        try {
            if (permissionsJson == null || permissionsJson.trim().isEmpty()) {
                return new HashSet<>();
            }

            List<String> permissionsList = objectMapper.readValue(permissionsJson, new TypeReference<List<String>>() {});
            return new HashSet<>(permissionsList);
        } catch (Exception e) {
            log.error("Error parsing permissions JSON: {}", permissionsJson, e);
            return new HashSet<>();
        }
    }

    /**
     * Create a new tenant role
     */
    public UtmTenantRole createRole(UUID tenantId, String roleName, Set<String> permissions, UUID parentRoleId) {
        log.info("Creating role: tenant={}, role={}, permissions={}", tenantId, roleName, permissions);

        // Check if role already exists
        if (tenantRoleRepository.existsByTenantIdAndRoleName(tenantId, roleName)) {
            throw new IllegalArgumentException("Role already exists: " + roleName);
        }

        UtmTenantRole role = new UtmTenantRole();
        role.setTenantId(tenantId);
        role.setRoleName(roleName);
        role.setParentRoleId(parentRoleId);

        // Convert permissions to JSON
        try {
            String permissionsJson = objectMapper.writeValueAsString(new ArrayList<>(permissions));
            role.setPermissions(permissionsJson);
        } catch (Exception e) {
            log.error("Error serializing permissions", e);
            throw new RuntimeException("Failed to create role", e);
        }

        return tenantRoleRepository.save(role);
    }

    /**
     * Update role permissions
     */
    public UtmTenantRole updateRolePermissions(UUID tenantId, String roleName, Set<String> permissions) {
        log.info("Updating role permissions: tenant={}, role={}, permissions={}", tenantId, roleName, permissions);

        UtmTenantRole role = tenantRoleRepository.findByTenantIdAndRoleName(tenantId, roleName)
            .orElseThrow(() -> new IllegalArgumentException("Role not found: " + roleName));

        try {
            String permissionsJson = objectMapper.writeValueAsString(new ArrayList<>(permissions));
            role.setPermissions(permissionsJson);
        } catch (Exception e) {
            log.error("Error serializing permissions", e);
            throw new RuntimeException("Failed to update role", e);
        }

        return tenantRoleRepository.save(role);
    }

    /**
     * Get all available permissions (for role management UI)
     */
    public Set<String> getAllAvailablePermissions() {
        Set<String> allPermissions = new HashSet<>();

        // Use reflection to get all permission constants
        java.lang.reflect.Field[] fields = Permissions.class.getDeclaredFields();
        for (java.lang.reflect.Field field : fields) {
            if (java.lang.reflect.Modifier.isStatic(field.getModifiers()) && 
                java.lang.reflect.Modifier.isFinal(field.getModifiers()) &&
                field.getType() == String.class) {
                try {
                    allPermissions.add((String) field.get(null));
                } catch (IllegalAccessException e) {
                    log.warn("Cannot access permission field: {}", field.getName());
                }
            }
        }

        return allPermissions;
    }

    /**
     * Get permissions grouped by functional area
     */
    public Map<String, Set<String>> getPermissionsByArea() {
        Map<String, Set<String>> permissionsByArea = new HashMap<>();

        permissionsByArea.put("User Management", Set.of(
            Permissions.USER_MANAGEMENT, Permissions.USER_CREATE, Permissions.USER_VIEW,
            Permissions.USER_UPDATE, Permissions.USER_DELETE
        ));

        permissionsByArea.put("Dashboard Management", Set.of(
            Permissions.DASHBOARD_MANAGEMENT, Permissions.DASHBOARD_CREATE, Permissions.DASHBOARD_VIEW,
            Permissions.DASHBOARD_UPDATE, Permissions.DASHBOARD_DELETE
        ));

        permissionsByArea.put("Alert Management", Set.of(
            Permissions.ALERT_MANAGEMENT, Permissions.ALERT_VIEW, Permissions.ALERT_CREATE,
            Permissions.ALERT_UPDATE, Permissions.ALERT_DELETE
        ));

        permissionsByArea.put("Incident Management", Set.of(
            Permissions.INCIDENT_MANAGEMENT, Permissions.INCIDENT_VIEW, Permissions.INCIDENT_CREATE,
            Permissions.INCIDENT_UPDATE, Permissions.INCIDENT_DELETE
        ));

        permissionsByArea.put("Configuration", Set.of(
            Permissions.CONFIGURATION, Permissions.CONFIG_VIEW, Permissions.CONFIG_UPDATE
        ));

        permissionsByArea.put("Reports", Set.of(
            Permissions.REPORTS, Permissions.REPORTS_VIEW, Permissions.REPORTS_CREATE,
            Permissions.REPORTS_EXPORT
        ));

        permissionsByArea.put("Administration", Set.of(
            Permissions.TENANT_ADMIN, Permissions.SYSTEM_SETTINGS, Permissions.AUDIT_LOGS
        ));

        return permissionsByArea;
    }

    /**
     * Check if user is tenant admin
     */
    @Transactional(readOnly = true)
    public boolean isTenantAdmin() {
        return hasPermission(Permissions.TENANT_ADMIN) || hasPermission(Permissions.USER_MANAGEMENT);
    }

    /**
     * Get user's roles within current tenant
     */
    @Transactional(readOnly = true)
    public List<String> getCurrentUserRoles() {
        String currentRole = TenantContext.getCurrentTenantRole();
        UUID currentTenantId = TenantContext.getCurrentTenantAsUUID();

        if (currentRole == null || currentTenantId == null) {
            return Collections.emptyList();
        }

        // For now, return the current role
        // This could be extended to support multiple roles per user
        return Collections.singletonList(currentRole);
    }

    /**
     * Validate permission exists
     */
    public boolean isValidPermission(String permission) {
        return getAllAvailablePermissions().contains(permission);
    }

    /**
     * Get role hierarchy for a tenant
     */
    @Transactional(readOnly = true)
    public Map<String, List<String>> getRoleHierarchy(UUID tenantId) {
        List<UtmTenantRole> roles = tenantRoleRepository.findByTenantIdOrderByRoleName(tenantId);
        Map<String, List<String>> hierarchy = new HashMap<>();

        for (UtmTenantRole role : roles) {
            String roleName = role.getRoleName();
            List<String> children = new ArrayList<>();

            // Find child roles
            for (UtmTenantRole potentialChild : roles) {
                if (role.getId().equals(potentialChild.getParentRoleId())) {
                    children.add(potentialChild.getRoleName());
                }
            }

            hierarchy.put(roleName, children);
        }

        return hierarchy;
    }
}
