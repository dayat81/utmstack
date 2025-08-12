package com.park.utmstack.service.dto.tenant;

import java.util.Map;

public class ResourceQuotaStatus {
    private String overallStatus;
    private Map<String, Integer> usage;
    private Map<String, Integer> limits;

    public String getOverallStatus() {
        return overallStatus;
    }

    public void setOverallStatus(String overallStatus) {
        this.overallStatus = overallStatus;
    }

    public Map<String, Integer> getUsage() {
        return usage;
    }

    public void setUsage(Map<String, Integer> usage) {
        this.usage = usage;
    }

    public Map<String, Integer> getLimits() {
        return limits;
    }

    public void setLimits(Map<String, Integer> limits) {
        this.limits = limits;
    }
}