package com.park.utmstack.service.dto.tenant;

import java.util.UUID;

public class TenantResourceUsage {
    private UUID tenantId;
    private int userCount;
    private int dashboardCount;
    private int alertCount;
    private long storageUsed;

    public TenantResourceUsage() {}

    public TenantResourceUsage(UUID tenantId, int userCount, int dashboardCount, int alertCount, long storageUsed) {
        this.tenantId = tenantId;
        this.userCount = userCount;
        this.dashboardCount = dashboardCount;
        this.alertCount = alertCount;
        this.storageUsed = storageUsed;
    }

    public UUID getTenantId() {
        return tenantId;
    }

    public void setTenantId(UUID tenantId) {
        this.tenantId = tenantId;
    }

    public int getUserCount() {
        return userCount;
    }

    public void setUserCount(int userCount) {
        this.userCount = userCount;
    }

    public int getDashboardCount() {
        return dashboardCount;
    }

    public void setDashboardCount(int dashboardCount) {
        this.dashboardCount = dashboardCount;
    }

    public int getAlertCount() {
        return alertCount;
    }

    public void setAlertCount(int alertCount) {
        this.alertCount = alertCount;
    }

    public long getStorageUsed() {
        return storageUsed;
    }

    public void setStorageUsed(long storageUsed) {
        this.storageUsed = storageUsed;
    }
}
