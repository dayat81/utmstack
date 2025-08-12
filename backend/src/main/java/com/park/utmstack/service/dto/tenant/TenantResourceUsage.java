package com.park.utmstack.service.dto.tenant;

import java.util.Map;

public class TenantResourceUsage {
    private Map<String, Integer> usage;

    public Map<String, Integer> getUsage() {
        return usage;
    }

    public void setUsage(Map<String, Integer> usage) {
        this.usage = usage;
    }
}