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
 * A UtmTenantRole entity for tenant-specific role management.
 */
@Entity
@Table(name = "utm_tenant_role", 
       uniqueConstraints = @UniqueConstraint(columnNames = {"tenant_id", "role_name"}))
public class UtmTenantRole implements Serializable {

    private static final long serialVersionUID = 1L;

    @Id
    @GeneratedValue(generator = "UUID")
    @GenericGenerator(name = "UUID", strategy = "org.hibernate.id.UUIDGenerator")
    @Column(name = "id", updatable = false, nullable = false)
    @Type(type = "uuid-char")
    private UUID id;

    @NotNull
    @Size(max = 100)
    @Column(name = "role_name", length = 100, nullable = false)
    private String roleName;

    @Type(type = "jsonb")
    @Column(name = "permissions", columnDefinition = "jsonb")
    private String permissions = "[]";

    @Column(name = "parent_role_id")
    @Type(type = "uuid-char")
    private UUID parentRoleId;

    @Column(name = "created_at", nullable = false)
    @JsonFormat(pattern = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'")
    private Instant createdAt = Instant.now();

    @Column(name = "updated_at", nullable = false)
    @JsonFormat(pattern = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'")
    private Instant updatedAt = Instant.now();

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "tenant_id", nullable = false)
    @JsonIgnoreProperties(value = "roles", allowSetters = true)
    private UtmTenant tenant;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "parent_role_id", insertable = false, updatable = false)
    @JsonIgnoreProperties(value = "childRoles", allowSetters = true)
    private UtmTenantRole parentRole;

    // Constructors
    public UtmTenantRole() {}

    public UtmTenantRole(String roleName, String permissions) {
        this.roleName = roleName;
        this.permissions = permissions;
    }

    // Getters and Setters
    public UUID getId() {
        return id;
    }

    public void setId(UUID id) {
        this.id = id;
    }

    public String getRoleName() {
        return roleName;
    }

    public UtmTenantRole roleName(String roleName) {
        this.roleName = roleName;
        return this;
    }

    public void setRoleName(String roleName) {
        this.roleName = roleName;
    }

    public String getPermissions() {
        return permissions;
    }

    public UtmTenantRole permissions(String permissions) {
        this.permissions = permissions;
        return this;
    }

    public void setPermissions(String permissions) {
        this.permissions = permissions;
    }

    public UUID getParentRoleId() {
        return parentRoleId;
    }

    public UtmTenantRole parentRoleId(UUID parentRoleId) {
        this.parentRoleId = parentRoleId;
        return this;
    }

    public void setParentRoleId(UUID parentRoleId) {
        this.parentRoleId = parentRoleId;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public UtmTenantRole createdAt(Instant createdAt) {
        this.createdAt = createdAt;
        return this;
    }

    public void setCreatedAt(Instant createdAt) {
        this.createdAt = createdAt;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }

    public UtmTenantRole updatedAt(Instant updatedAt) {
        this.updatedAt = updatedAt;
        return this;
    }

    public void setUpdatedAt(Instant updatedAt) {
        this.updatedAt = updatedAt;
    }

    public UtmTenant getTenant() {
        return tenant;
    }

    public UtmTenantRole tenant(UtmTenant tenant) {
        this.tenant = tenant;
        return this;
    }

    public void setTenant(UtmTenant tenant) {
        this.tenant = tenant;
    }

    public UtmTenantRole getParentRole() {
        return parentRole;
    }

    public UtmTenantRole parentRole(UtmTenantRole parentRole) {
        this.parentRole = parentRole;
        return this;
    }

    public void setParentRole(UtmTenantRole parentRole) {
        this.parentRole = parentRole;
    }

    public void setTenantId(UUID tenantId) {
        if (this.tenant == null) {
            this.tenant = new UtmTenant();
        }
        this.tenant.setId(tenantId);
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
        if (!(o instanceof UtmTenantRole)) {
            return false;
        }
        return id != null && id.equals(((UtmTenantRole) o).id);
    }

    @Override
    public int hashCode() {
        return Objects.hash(id);
    }

    @Override
    public String toString() {
        return "UtmTenantRole{" +
            "id=" + getId() +
            ", roleName='" + getRoleName() + "'" +
            ", permissions='" + getPermissions() + "'" +
            ", parentRoleId=" + getParentRoleId() +
            ", createdAt='" + getCreatedAt() + "'" +
            ", updatedAt='" + getUpdatedAt() + "'" +
            "}";
    }
}
