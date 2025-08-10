# Current Tenant Information - UTMStack

## Current System Status
- **Multi-tenant Feature**: Disabled (config: `features.multi_tenant: false`)
- **Environment**: Development
- **Version**: 10.1.0
- **Backend API**: http://localhost:8080 (HTTPS endpoint active)

## Tenant Configuration Overview

### System Configuration
- **Database**: PostgreSQL on localhost:5432 (database: utmstack)
- **Elasticsearch**: http://localhost:9200
- **Current Environment**: Development mode with debug enabled

### Multi-Tenant Architecture (Available but Disabled)

The system has full multi-tenant capabilities implemented but currently disabled. When enabled, it supports:

#### Tenant Identification Methods
1. **JWT Token** - Primary method with `tenant_id` claim
2. **Subdomain** - tenant.utmstack.com routing  
3. **HTTP Header** - `X-Tenant-ID` header
4. **Request Parameter** - For API requests

#### Core Tenant Tables
1. **`utm_tenant`** - Main tenant entity with UUID, name, subdomain, status, tier
2. **`utm_tenant_config`** - Key-value configuration storage
3. **`utm_tenant_role`** - Hierarchical role and permission management

#### Available Tenant Tiers
- Standard
- Premium  
- Enterprise

### Current Single-Tenant Operation
Since multi-tenant is disabled, the system operates as a single-tenant installation with:

- **Default Database**: utmstack
- **Single Instance**: All services share the same database and configuration
- **No Tenant Isolation**: All data stored without tenant partitioning
- **API Access**: Direct access without tenant context

### API Endpoints (When Multi-tenant Enabled)
- `GET /api/tenants` - List all tenants
- `GET /api/tenant/current` - Current tenant info
- `GET /api/tenants/{id}` - Specific tenant details
- `POST /api/admin/tenants/provision` - Create new tenant
- `DELETE /api/admin/tenants/{id}` - Deprovision tenant

### To Enable Multi-Tenant Mode
1. Set `features.multi_tenant: true` in [config/utmstack.yml](file:///home/ptsec/utmstack/config/utmstack.yml#L314)
2. Run tenant table creation script: [create-tenant-tables.sql](file:///home/ptsec/utmstack/create-tenant-tables.sql)
3. Restart UTMStack services

---
*Generated on: $(date)*
*System: UTMStack v10.1.0 - Development Environment*
