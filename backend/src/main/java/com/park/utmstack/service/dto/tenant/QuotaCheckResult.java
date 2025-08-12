package com.park.utmstack.service.dto.tenant;

public class QuotaCheckResult {
    private boolean allowed;
    private String reason;
    private String resourceType;

    public QuotaCheckResult() {}

    public QuotaCheckResult(boolean allowed, String reason, String resourceType) {
        this.allowed = allowed;
        this.reason = reason;
        this.resourceType = resourceType;
    }

    public boolean isAllowed() {
        return allowed;
    }

    public void setAllowed(boolean allowed) {
        this.allowed = allowed;
    }

    public String getReason() {
        return reason;
    }

    public void setReason(String reason) {
        this.reason = reason;
    }

    public String getResourceType() {
        return resourceType;
    }

    public void setResourceType(String resourceType) {
        this.resourceType = resourceType;
    }
}
