package com.park.utmstack.security;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.UUID;

/**
 * Thread-local storage for tenant context.
 * Manages the current tenant ID throughout the request lifecycle.
 */
public final class TenantContext {

    private static final Logger log = LoggerFactory.getLogger(TenantContext.class);

    private static final ThreadLocal<String> CURRENT_TENANT = new ThreadLocal<>();
    private static final ThreadLocal<String> CURRENT_TENANT_SUBDOMAIN = new ThreadLocal<>();
    private static final ThreadLocal<String> CURRENT_TENANT_ROLE = new ThreadLocal<>();

    private TenantContext() {
        // Utility class
    }

    /**
     * Set the current tenant ID for the current thread
     */
    public static void setCurrentTenant(String tenantId) {
        if (tenantId != null && !tenantId.trim().isEmpty()) {
            CURRENT_TENANT.set(tenantId.trim());
            log.debug("Set tenant context: {}", tenantId);
        } else {
            log.warn("Attempted to set null or empty tenant ID");
        }
    }

    /**
     * Set the current tenant ID as UUID for the current thread
     */
    public static void setCurrentTenant(UUID tenantId) {
        if (tenantId != null) {
            setCurrentTenant(tenantId.toString());
        } else {
            log.warn("Attempted to set null tenant UUID");
        }
    }

    /**
     * Get the current tenant ID for the current thread
     */
    public static String getCurrentTenant() {
        return CURRENT_TENANT.get();
    }

    /**
     * Get the current tenant ID as UUID for the current thread
     */
    public static UUID getCurrentTenantAsUUID() {
        String tenantId = getCurrentTenant();
        if (tenantId != null) {
            try {
                return UUID.fromString(tenantId);
            } catch (IllegalArgumentException e) {
                log.error("Invalid tenant ID format: {}", tenantId, e);
                return null;
            }
        }
        return null;
    }

    /**
     * Set the current tenant subdomain for the current thread
     */
    public static void setCurrentTenantSubdomain(String subdomain) {
        if (subdomain != null && !subdomain.trim().isEmpty()) {
            CURRENT_TENANT_SUBDOMAIN.set(subdomain.trim());
            log.debug("Set tenant subdomain context: {}", subdomain);
        }
    }

    /**
     * Get the current tenant subdomain for the current thread
     */
    public static String getCurrentTenantSubdomain() {
        return CURRENT_TENANT_SUBDOMAIN.get();
    }

    /**
     * Set the current tenant role for the current thread
     */
    public static void setCurrentTenantRole(String role) {
        if (role != null && !role.trim().isEmpty()) {
            CURRENT_TENANT_ROLE.set(role.trim());
            log.debug("Set tenant role context: {}", role);
        }
    }

    /**
     * Get the current tenant role for the current thread
     */
    public static String getCurrentTenantRole() {
        return CURRENT_TENANT_ROLE.get();
    }

    /**
     * Check if there is a current tenant set
     */
    public static boolean hasTenant() {
        return getCurrentTenant() != null;
    }

    /**
     * Clear all tenant context for the current thread
     */
    public static void clear() {
        String previousTenant = CURRENT_TENANT.get();
        CURRENT_TENANT.remove();
        CURRENT_TENANT_SUBDOMAIN.remove();
        CURRENT_TENANT_ROLE.remove();
        
        if (previousTenant != null) {
            log.debug("Cleared tenant context: {}", previousTenant);
        }
    }

    /**
     * Execute a block of code with a specific tenant context
     */
    public static <T> T withTenant(String tenantId, java.util.function.Supplier<T> supplier) {
        String previousTenant = getCurrentTenant();
        String previousSubdomain = getCurrentTenantSubdomain();
        String previousRole = getCurrentTenantRole();
        
        try {
            setCurrentTenant(tenantId);
            return supplier.get();
        } finally {
            // Restore previous context
            if (previousTenant != null) {
                setCurrentTenant(previousTenant);
            } else {
                CURRENT_TENANT.remove();
            }
            
            if (previousSubdomain != null) {
                setCurrentTenantSubdomain(previousSubdomain);
            } else {
                CURRENT_TENANT_SUBDOMAIN.remove();
            }
            
            if (previousRole != null) {
                setCurrentTenantRole(previousRole);
            } else {
                CURRENT_TENANT_ROLE.remove();
            }
        }
    }

    /**
     * Execute a block of code with a specific tenant context (UUID version)
     */
    public static <T> T withTenant(UUID tenantId, java.util.function.Supplier<T> supplier) {
        return withTenant(tenantId != null ? tenantId.toString() : null, supplier);
    }

    /**
     * Execute a block of code without tenant context (useful for system operations)
     */
    public static <T> T withoutTenant(java.util.function.Supplier<T> supplier) {
        String previousTenant = getCurrentTenant();
        String previousSubdomain = getCurrentTenantSubdomain();
        String previousRole = getCurrentTenantRole();
        
        try {
            clear();
            return supplier.get();
        } finally {
            // Restore previous context
            if (previousTenant != null) {
                setCurrentTenant(previousTenant);
            }
            if (previousSubdomain != null) {
                setCurrentTenantSubdomain(previousSubdomain);
            }
            if (previousRole != null) {
                setCurrentTenantRole(previousRole);
            }
        }
    }

    /**
     * Get current tenant context information for logging/debugging
     */
    public static String getContextInfo() {
        return String.format("TenantContext{tenantId='%s', subdomain='%s', role='%s'}", 
            getCurrentTenant(), getCurrentTenantSubdomain(), getCurrentTenantRole());
    }

    /**
     * Validate that current tenant context is set
     */
    public static void requireTenant() {
        if (!hasTenant()) {
            throw new IllegalStateException("No tenant context is set for the current thread");
        }
    }

    /**
     * Set full tenant context from multi-tenant user principal
     */
    public static void setTenantContext(String tenantId, String subdomain, String role) {
        setCurrentTenant(tenantId);
        setCurrentTenantSubdomain(subdomain);
        setCurrentTenantRole(role);
    }
}
