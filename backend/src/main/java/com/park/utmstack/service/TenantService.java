package com.park.utmstack.service;

import com.park.utmstack.domain.UtmTenant;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public class TenantService {

    public List<UtmTenant> getAllActiveTenants() {
        return null;
    }

    public Optional<UtmTenant> getTenant(UUID tenantId) {
        return Optional.empty();
    }

    public UtmTenant updateTenantStatus(UUID tenantId, String status) {
        return null;
    }

    public void deleteTenant(UUID tenantId) {
    }
}