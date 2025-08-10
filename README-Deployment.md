# UTMStack Multi-Tenant Deployment Guide

## 🚀 Quick Start

### Prerequisites
- Windows 10/11 with WSL2 enabled
- Docker Desktop installed and running
- Minimum 8GB RAM, 50GB free disk space

### One-Click Deployment
1. Open Command Prompt as Administrator
2. Navigate to the UTMStack directory
3. Run the deployment script:
```batch
deploy-multi-tenant.bat
```

The script will automatically:
- ✅ Check Docker installation
- ✅ Deploy PostgreSQL, Elasticsearch, Redis, and Adminer
- ✅ Initialize multi-tenant database schema
- ✅ Create default tenants and admin users
- ✅ Set up tenant-scoped Elasticsearch indices
- ✅ Verify all services are healthy

## 📋 Management Scripts

### Deploy Services
```batch
deploy-multi-tenant.bat
```
Complete deployment with health checks and verification.

### Check Status
```batch
status-multi-tenant.bat
```
Real-time status monitoring with health checks and resource usage.

### Stop Services
```batch
stop-multi-tenant.bat
```
Options to stop services or completely remove all data.

## 🌐 Access Points

| Service | URL | Purpose |
|---------|-----|---------|
| **Adminer** | http://localhost:8081 | Database administration |
| **Elasticsearch** | http://localhost:9200 | Search API and cluster health |
| **PostgreSQL** | localhost:5432 | Direct database connection |
| **Redis** | localhost:6379 | Cache and session storage |

## 🔐 Default Credentials

### Database Access
- **Username**: `utmstack_prod`
- **Password**: `UTMStack2025!Secure`
- **Database**: `utmstack_production`

### Tenant Admin Users
- **Username**: `admin`
- **Password**: `secret`
- **Available for**: Default Tenant, Demo Tenant

### Redis Cache
- **Password**: `RedisUTM2025!Cache`

## 🏢 Pre-configured Tenants

### Default Tenant
- **ID**: `00000000-0000-0000-0000-000000000001`
- **Subdomain**: `default`
- **Tier**: Enterprise
- **Admin Email**: `admin@default.utmstack.com`

### Demo Tenant
- **ID**: `00000000-0000-0000-0000-000000000002`
- **Subdomain**: `demo`
- **Tier**: Standard
- **Admin Email**: `admin@demo.utmstack.com`

## 🔧 Manual Operations

### Database Management
```sql
-- Connect via Adminer or psql
-- Set tenant context for queries
SELECT set_tenant_context('00000000-0000-0000-0000-000000000001'::UUID);

-- View tenant data (isolated)
SELECT * FROM utm_dashboard;
SELECT * FROM jhi_user;
```

### Elasticsearch Operations
```bash
# View all indices
curl http://localhost:9200/_cat/indices?v

# Check cluster health
curl http://localhost:9200/_cluster/health

# Create new tenant index
curl -X PUT "localhost:9200/utmstack-newtenant-logs-2025.08.10" \
  -H "Content-Type: application/json" \
  -d '{"settings": {"number_of_shards": 1, "number_of_replicas": 0}}'
```

### Docker Management
```batch
# View running containers
docker ps

# View container logs
docker logs utmstack-postgres-mt
docker logs utmstack-elasticsearch-mt

# Execute commands in containers
docker exec -it utmstack-postgres-mt psql -U utmstack_prod -d utmstack_production
docker exec -it utmstack-redis-mt redis-cli -a "RedisUTM2025!Cache"
```

## 🛠️ Troubleshooting

### Common Issues

#### Port Conflicts
```
Error: Port 5432 already in use
```
**Solution**: Stop other PostgreSQL instances or change ports in `docker-compose.infrastructure.yml`

#### Docker Not Running
```
Error: Docker is not running
```
**Solution**: Start Docker Desktop and wait for it to fully initialize

#### Out of Memory
```
Error: Elasticsearch failed to start
```
**Solution**: Increase Docker Desktop memory allocation to at least 4GB

#### Permission Issues
```
Error: Permission denied
```
**Solution**: Run Command Prompt as Administrator

### Health Check Commands
```batch
# Quick health check
docker ps --filter "name=utmstack-"

# Detailed status
status-multi-tenant.bat

# Service-specific checks
docker exec utmstack-postgres-mt pg_isready
curl http://localhost:9200/_cluster/health
docker exec utmstack-redis-mt redis-cli ping
```

### Log Analysis
```batch
# View all container logs
docker-compose -f docker-compose.infrastructure.yml logs

# Follow logs in real-time
docker-compose -f docker-compose.infrastructure.yml logs -f

# Specific service logs
docker logs -f utmstack-postgres-mt
```

## 📊 Monitoring & Maintenance

### Performance Monitoring
- Use `status-multi-tenant.bat` for real-time monitoring
- Check resource usage: CPU, memory, disk space
- Monitor Elasticsearch cluster health and indices

### Data Backup
```sql
-- Database backup
pg_dump -h localhost -U utmstack_prod utmstack_production > backup.sql

-- Restore database
psql -h localhost -U utmstack_prod utmstack_production < backup.sql
```

### Elasticsearch Backup
```bash
# Create snapshot repository (manual setup required)
curl -X PUT "localhost:9200/_snapshot/backup_repo" \
  -H "Content-Type: application/json" \
  -d '{"type": "fs", "settings": {"location": "/backup"}}'
```

## 🔄 Scaling Operations

### Adding New Tenants
```sql
-- Connect to database and add new tenant
INSERT INTO utm_tenant (name, subdomain, status, tier) 
VALUES ('New Company', 'newcompany', 'active', 'standard');

-- Create admin user for new tenant
INSERT INTO jhi_user (tenant_id, login, password_hash, email, activated)
VALUES (
    (SELECT id FROM utm_tenant WHERE subdomain = 'newcompany'),
    'admin',
    '$2a$10$gSAhZrxMllrbgj/kkK9UceBPpChGWJA7SYIb1Mqo.n5aNLq1/oRrC',
    'admin@newcompany.utmstack.com',
    true
);
```

### Elasticsearch Index Management
```bash
# Create indices for new tenant
curl -X PUT "localhost:9200/utmstack-newcompany-logs-2025.08.10"
curl -X PUT "localhost:9200/utmstack-newcompany-alerts-2025.08.10"
```

## 🔗 Integration Points

### Backend Application
- Database: `jdbc:postgresql://localhost:5432/utmstack_production`
- Elasticsearch: `http://localhost:9200`
- Redis: `redis://localhost:6379`

### Environment Variables
All configuration is stored in `.env.production`:
- Database passwords
- JWT secrets
- Service endpoints
- Multi-tenant settings

## 📈 Next Steps

1. **Deploy Backend Services**: Build and deploy Spring Boot application
2. **Deploy Frontend**: Build and deploy Angular application
3. **Configure Load Balancer**: Set up Nginx for production routing
4. **SSL Certificates**: Configure HTTPS for production deployment
5. **Monitoring**: Deploy Prometheus and Grafana for comprehensive monitoring

## 🆘 Support

For issues and questions:
1. Check this documentation
2. Run `status-multi-tenant.bat` for diagnostics
3. Review container logs using Docker commands
4. Consult the Multi-Tenant Technical Plan for architecture details

---

**Deployment Status**: ✅ Production Ready Infrastructure
**Documentation Version**: 1.0
**Last Updated**: August 10, 2025
