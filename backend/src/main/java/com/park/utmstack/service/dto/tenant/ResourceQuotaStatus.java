package com.park.utmstack.service.dto.tenant;

import java.util.UUID;

public class ResourceQuotaStatus {
    private UUID tenantId;
    private boolean withinLimits;
    private String message;

    public ResourceQuotaStatus() {}

    public ResourceQuotaStatus(UUID tenantId, boolean withinLimits, String message) {
        this.tenantId = tenantId;
        this.withinLimits = withinLimits;
        this.message = message;
    }

    public UUID getTenantId() {
        return tenantId;
    }

    public void setTenantId(UUID tenantId) {
        this.tenantId = tenantId;
    }

    public boolean isWithinLimits() {
        return withinLimits;
    }

    public void setWithinLimits(boolean withinLimits) {
        this.withinLimits = withinLimits;
    }

    public String getMessage() {
        return message;
    }

    public void setMessage(String message) {
        this.message = message;
    }
}
