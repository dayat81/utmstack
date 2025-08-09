package com.park.utmstack.domain;

import com.fasterxml.jackson.annotation.JsonFormat;
import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import org.hibernate.annotations.GenericGenerator;
import org.hibernate.annotations.Type;

import javax.persistence.*;
import javax.validation.constraints.NotNull;
import javax.validation.constraints.Size;
import java.io.Serializable;
import java.time.Instant;
import java.util.Objects;
import java.util.UUID;

/**
 * A UtmTenantConfig entity for tenant-specific configuration.
 */
@Entity
@Table(name = "utm_tenant_config", 
       uniqueConstraints = @UniqueConstraint(columnNames = {"tenant_id", "config_key"}))
public class UtmTenantConfig implements Serializable {

    private static final long serialVersionUID = 1L;

    @Id
    @GeneratedValue(generator = "UUID")
    @GenericGenerator(name = "UUID", strategy = "org.hibernate.id.UUIDGenerator")
    @Column(name = "id", updatable = false, nullable = false)
    @Type(type = "uuid-char")
    private UUID id;

    @NotNull
    @Size(max = 255)
    @Column(name = "config_key", length = 255, nullable = false)
    private String configKey;

    @Lob
    @Column(name = "config_value")
    private String configValue;

    @NotNull
    @Size(max = 50)
    @Column(name = "config_type", length = 50, nullable = false)
    private String configType = "STRING";

    @Column(name = "created_at", nullable = false)
    @JsonFormat(pattern = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'")
    private Instant createdAt = Instant.now();

    @Column(name = "updated_at", nullable = false)
    @JsonFormat(pattern = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'")
    private Instant updatedAt = Instant.now();

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "tenant_id", nullable = false)
    @JsonIgnoreProperties(value = "configurations", allowSetters = true)
    private UtmTenant tenant;

    // Constructors
    public UtmTenantConfig() {}

    public UtmTenantConfig(String configKey, String configValue, String configType) {
        this.configKey = configKey;
        this.configValue = configValue;
        this.configType = configType;
    }

    // Getters and Setters
    public UUID getId() {
        return id;
    }

    public void setId(UUID id) {
        this.id = id;
    }

    public String getConfigKey() {
        return configKey;
    }

    public UtmTenantConfig configKey(String configKey) {
        this.configKey = configKey;
        return this;
    }

    public void setConfigKey(String configKey) {
        this.configKey = configKey;
    }

    public String getConfigValue() {
        return configValue;
    }

    public UtmTenantConfig configValue(String configValue) {
        this.configValue = configValue;
        return this;
    }

    public void setConfigValue(String configValue) {
        this.configValue = configValue;
    }

    public String getConfigType() {
        return configType;
    }

    public UtmTenantConfig configType(String configType) {
        this.configType = configType;
        return this;
    }

    public void setConfigType(String configType) {
        this.configType = configType;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public UtmTenantConfig createdAt(Instant createdAt) {
        this.createdAt = createdAt;
        return this;
    }

    public void setCreatedAt(Instant createdAt) {
        this.createdAt = createdAt;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }

    public UtmTenantConfig updatedAt(Instant updatedAt) {
        this.updatedAt = updatedAt;
        return this;
    }

    public void setUpdatedAt(Instant updatedAt) {
        this.updatedAt = updatedAt;
    }

    public UtmTenant getTenant() {
        return tenant;
    }

    public UtmTenantConfig tenant(UtmTenant tenant) {
        this.tenant = tenant;
        return this;
    }

    public void setTenant(UtmTenant tenant) {
        this.tenant = tenant;
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
        if (!(o instanceof UtmTenantConfig)) {
            return false;
        }
        return id != null && id.equals(((UtmTenantConfig) o).id);
    }

    @Override
    public int hashCode() {
        return Objects.hash(id);
    }

    @Override
    public String toString() {
        return "UtmTenantConfig{" +
            "id=" + getId() +
            ", configKey='" + getConfigKey() + "'" +
            ", configValue='" + getConfigValue() + "'" +
            ", configType='" + getConfigType() + "'" +
            ", createdAt='" + getCreatedAt() + "'" +
            ", updatedAt='" + getUpdatedAt() + "'" +
            "}";
    }
}
