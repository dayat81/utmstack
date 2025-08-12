package com.park.utmstack.security;

import java.util.UUID;

public class TenantContext {
    private static final ThreadLocal<UUID> currentTenant = new ThreadLocal<>();
    private static final ThreadLocal<String> currentTenantRole = new ThreadLocal<>();

    public static void setCurrentTenant(UUID tenantId) {
        currentTenant.set(tenantId);
    }

    public static UUID getCurrentTenantAsUUID() {
        return currentTenant.get();
    }

    public static String getCurrentTenantRole() {
        return currentTenantRole.get();
    }

    public static void clear() {
        currentTenant.remove();
        currentTenantRole.remove();
    }
}
