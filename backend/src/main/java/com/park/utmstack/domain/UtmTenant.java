package com.park.utmstack.domain;

import com.fasterxml.jackson.annotation.JsonFormat;
import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import org.hibernate.annotations.GenericGenerator;
import org.hibernate.annotations.Type;

import javax.persistence.*;
import javax.validation.constraints.NotNull;
import javax.validation.constraints.Size;
import java.io.Serializable;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.HashSet;
import java.util.Objects;
import java.util.Set;
import java.util.UUID;

/**
 * A UtmTenant entity for multi-tenant support.
 */
@Entity
@Table(name = "utm_tenant")
public class UtmTenant implements Serializable {

    private static final long serialVersionUID = 1L;

    @Id
    @GeneratedValue(generator = "UUID")
    @GenericGenerator(name = "UUID", strategy = "org.hibernate.id.UUIDGenerator")
    @Column(name = "id", updatable = false, nullable = false)
    @Type(type = "uuid-char")
    private UUID id;

    @NotNull
    @Size(max = 255)
    @Column(name = "name", length = 255, nullable = false)
    private String name;

    @NotNull
    @Size(max = 100)
    @Column(name = "subdomain", length = 100, nullable = false, unique = true)
    private String subdomain;

    @NotNull
    @Size(max = 50)
    @Column(name = "status", length = 50, nullable = false)
    private String status = "active";

    @Column(name = "created_at", nullable = false)
    @JsonFormat(pattern = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'")
    private Instant createdAt = Instant.now();

    @Column(name = "updated_at", nullable = false)
    @JsonFormat(pattern = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'")
    private Instant updatedAt = Instant.now();

    @Type(type = "jsonb")
    @Column(name = "settings", columnDefinition = "jsonb")
    private String settings = "{}";

    @Type(type = "jsonb")
    @Column(name = "resource_limits", columnDefinition = "jsonb")
    private String resourceLimits = "{}";

    @NotNull
    @Size(max = 50)
    @Column(name = "tier", length = 50, nullable = false)
    private String tier = "standard";

    @Column(name = "cpu_threshold", precision = 5, scale = 2, nullable = false)
    private BigDecimal cpuThreshold = BigDecimal.valueOf(80.0);

    @Column(name = "memory_threshold", precision = 5, scale = 2, nullable = false)
    private BigDecimal memoryThreshold = BigDecimal.valueOf(80.0);

    @Column(name = "error_rate_threshold", precision = 5, scale = 2, nullable = false)
    private BigDecimal errorRateThreshold = BigDecimal.valueOf(5.0);

    @OneToMany(mappedBy = "tenant", cascade = CascadeType.ALL, fetch = FetchType.LAZY)
    @JsonIgnoreProperties(value = "tenant", allowSetters = true)
    private Set<UtmTenantConfig> configurations = new HashSet<>();

    @OneToMany(mappedBy = "tenant", cascade = CascadeType.ALL, fetch = FetchType.LAZY)
    @JsonIgnoreProperties(value = "tenant", allowSetters = true)
    private Set<UtmTenantRole> roles = new HashSet<>();

    // Constructors
    public UtmTenant() {}

    public UtmTenant(String name, String subdomain) {
        this.name = name;
        this.subdomain = subdomain;
    }

    // Getters and Setters
    public UUID getId() {
        return id;
    }

    public void setId(UUID id) {
        this.id = id;
    }

    public String getName() {
        return name;
    }

    public UtmTenant name(String name) {
        this.name = name;
        return this;
    }

    public void setName(String name) {
        this.name = name;
    }

    public String getSubdomain() {
        return subdomain;
    }

    public UtmTenant subdomain(String subdomain) {
        this.subdomain = subdomain;
        return this;
    }

    public void setSubdomain(String subdomain) {
        this.subdomain = subdomain;
    }

    public String getStatus() {
        return status;
    }

    public UtmTenant status(String status) {
        this.status = status;
        return this;
    }

    public void setStatus(String status) {
        this.status = status;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public UtmTenant createdAt(Instant createdAt) {
        this.createdAt = createdAt;
        return this;
    }

    public void setCreatedAt(Instant createdAt) {
        this.createdAt = createdAt;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }

    public UtmTenant updatedAt(Instant updatedAt) {
        this.updatedAt = updatedAt;
        return this;
    }

    public void setUpdatedAt(Instant updatedAt) {
        this.updatedAt = updatedAt;
    }

    public String getSettings() {
        return settings;
    }

    public UtmTenant settings(String settings) {
        this.settings = settings;
        return this;
    }

    public void setSettings(String settings) {
        this.settings = settings;
    }

    public String getResourceLimits() {
        return resourceLimits;
    }

    public UtmTenant resourceLimits(String resourceLimits) {
        this.resourceLimits = resourceLimits;
        return this;
    }

    public void setResourceLimits(String resourceLimits) {
        this.resourceLimits = resourceLimits;
    }

    public String getTier() {
        return tier;
    }

    public UtmTenant tier(String tier) {
        this.tier = tier;
        return this;
    }

    public void setTier(String tier) {
        this.tier = tier;
    }

    public BigDecimal getCpuThreshold() {
        return cpuThreshold;
    }

    public UtmTenant cpuThreshold(BigDecimal cpuThreshold) {
        this.cpuThreshold = cpuThreshold;
        return this;
    }

    public void setCpuThreshold(BigDecimal cpuThreshold) {
        this.cpuThreshold = cpuThreshold;
    }

    public BigDecimal getMemoryThreshold() {
        return memoryThreshold;
    }

    public UtmTenant memoryThreshold(BigDecimal memoryThreshold) {
        this.memoryThreshold = memoryThreshold;
        return this;
    }

    public void setMemoryThreshold(BigDecimal memoryThreshold) {
        this.memoryThreshold = memoryThreshold;
    }

    public BigDecimal getErrorRateThreshold() {
        return errorRateThreshold;
    }

    public UtmTenant errorRateThreshold(BigDecimal errorRateThreshold) {
        this.errorRateThreshold = errorRateThreshold;
        return this;
    }

    public void setErrorRateThreshold(BigDecimal errorRateThreshold) {
        this.errorRateThreshold = errorRateThreshold;
    }

    public Set<UtmTenantConfig> getConfigurations() {
        return configurations;
    }

    public UtmTenant configurations(Set<UtmTenantConfig> configurations) {
        this.configurations = configurations;
        return this;
    }

    public void setConfigurations(Set<UtmTenantConfig> configurations) {
        this.configurations = configurations;
    }

    public Set<UtmTenantRole> getRoles() {
        return roles;
    }

    public UtmTenant roles(Set<UtmTenantRole> roles) {
        this.roles = roles;
        return this;
    }

    public void setRoles(Set<UtmTenantRole> roles) {
        this.roles = roles;
    }

    @PreUpdate
    public void preUpdate() {
        this.updatedAt = Instant.now();
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) {
            return true;
        }
        if (!(o instanceof UtmTenant)) {
            return false;
        }
        return id != null && id.equals(((UtmTenant) o).id);
    }

    @Override
    public int hashCode() {
        return Objects.hash(id);
    }

    @Override
    public String toString() {
        return "UtmTenant{" +
            "id=" + getId() +
            ", name='" + getName() + "'" +
            ", subdomain='" + getSubdomain() + "'" +
            ", status='" + getStatus() + "'" +
            ", tier='" + getTier() + "'" +
            ", createdAt='" + getCreatedAt() + "'" +
            ", updatedAt='" + getUpdatedAt() + "'" +
            "}";
    }
}
