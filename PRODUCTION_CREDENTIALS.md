# UTMStack Production Credentials & Access

**⚠️ CONFIDENTIAL - For authorized personnel only**

**Last Updated:** Sun Aug 10 11:10:00 WIB 2025  
**Environment:** Production  

---

## 🔐 **Database Credentials**

### **PostgreSQL Database**
- **Host:** localhost:5432
- **Database:** pos_db
- **Username:** pos_user
- **Password:** pos_password
- **Connection String:** `postgresql://pos_user:pos_password@localhost:5432/pos_db`
- **Container:** pos-db
- **Status:** 🟢 Operational

### **Database Access Commands**
```bash
# Direct container access
docker exec -it pos-db psql -U pos_user -d pos_db

# With password from environment
PGPASSWORD=pos_password psql -h localhost -U pos_user -d pos_db

# Connection test
PGPASSWORD=pos_password psql -h localhost -U pos_user -d pos_db -c "SELECT version();"
```

---

## 🌐 **Service Access URLs**

### **Frontend Application**
- **URL:** http://localhost:4200
- **Status:** 🟢 Operational
- **Framework:** Angular 7
- **Authentication:** Web-based login

### **Backend API**
- **Base URL:** https://localhost:8080
- **Health Check:** https://localhost:8080/api/health
- **Status:** 🟡 Partial (HTTPS redirect active)
- **Authentication:** JWT tokens
- **API Docs:** Not configured

### **Elasticsearch**
- **URL:** http://localhost:9200
- **Cluster Health:** http://localhost:9200/_cluster/health
- **Status:** 🟢 Operational (GREEN cluster)
- **Authentication:** None configured
- **Index Pattern:** utmstack-*

### **Logstash**
- **Input Port:** 5044
- **Monitoring:** http://localhost:9600
- **Status:** 🟢 Operational
- **Config:** Container-based

---

## 🔧 **Administrative Access**

### **Container Management**
```bash
# PostgreSQL container
docker exec -it pos-db /bin/sh

# Elasticsearch container
docker exec -it utmstack-elasticsearch /bin/bash

# Logstash container
docker exec -it utmstack-logstash /bin/bash

# Container logs
docker logs pos-db
docker logs utmstack-elasticsearch
docker logs utmstack-logstash
```

### **Service Management**
```bash
# Check service processes
ps aux | grep -E "java|postgres|elasticsearch"

# Check ports
ss -tlnp | grep -E ":4200|:5432|:8080|:9200"

# Container status
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

---

## 🚨 **Security Notes**

### **Authentication Status**
| Service | Authentication | Status | Notes |
|---------|---------------|---------|-------|
| **PostgreSQL** | 🟢 Password | Configured | pos_user/pos_password |
| **Elasticsearch** | 🔴 None | Open | No authentication configured |
| **Frontend** | 🟢 Web Login | Ready | admin/admin configured |
| **Backend API** | 🔴 Not Running | Offline | Java backend not started |
| **Containers** | 🟢 Docker | Isolated | Standard container security |

### **Network Security**
- **Firewall:** Not configured
- **SSL/TLS:** Not configured for web services
- **Internal Communication:** Unencrypted
- **Container Network:** Default Docker network

### **Credentials Security**
- **Database Password:** Stored in container environment
- **API Keys:** Not configured
- **JWT Secrets:** Backend configuration required
- **SSL Certificates:** Not configured

---

## 🔑 **Default Access Accounts**

### **Database Users**
- **Primary User:** pos_user (configured)
- **Database:** pos_db
- **Privileges:** Full access to pos_db database

### **Application Users**
- **Admin Account:** admin / admin (configured for testing)
- **Federation Client:** fsclient (system account)
- **User Management:** Through backend API (when running)

---

## 📋 **Quick Access Commands**

### **Database Operations**
```bash
# Connect to database
export PGPASSWORD=pos_password
psql -h localhost -U pos_user -d pos_db

# List databases
psql -h localhost -U pos_user -d pos_db -c "\l"

# List tables
psql -h localhost -U pos_user -d pos_db -c "\dt"

# Check connections
psql -h localhost -U pos_user -d pos_db -c "SELECT * FROM pg_stat_activity;"
```

### **API Testing**
```bash
# Backend health check
curl -s -k https://localhost:8080/api/health

# Elasticsearch health
curl -s http://localhost:9200/_cluster/health

# Frontend status
curl -s http://localhost:4200 | head -1
```

### **Monitoring Commands**
```bash
# System resources
free -h && df -h && uptime

# Container status
docker ps && docker stats --no-stream

# Process monitoring
ps aux | grep -E "java|postgres" | head -5
```

---

## 🛠️ **Troubleshooting Access**

### **Database Connection Issues**
```bash
# Check if container is running
docker ps | grep pos-db

# Check container logs
docker logs pos-db --tail 20

# Test connection
PGPASSWORD=pos_password psql -h localhost -U pos_user -d pos_db -c "SELECT 1;"

# Container network
docker inspect pos-db | grep IPAddress
```

### **API Connection Issues**
```bash
# Check if service is listening
ss -tlnp | grep :8080

# Test HTTPS endpoint
curl -v -k https://localhost:8080/api/health

# Check for HTTP redirect
curl -v http://localhost:8080/api/health
```

### **Container Access Issues**
```bash
# Direct container shell access
docker exec -it pos-db /bin/sh
docker exec -it utmstack-elasticsearch /bin/bash

# Check container environment
docker inspect pos-db | grep -A 10 "Env"

# Container resource usage
docker stats --no-stream
```

---

## 📞 **Emergency Procedures**

### **Database Recovery**
```bash
# Restart database container
docker restart pos-db

# Check database integrity
PGPASSWORD=pos_password psql -h localhost -U pos_user -d pos_db -c "SELECT count(*) FROM information_schema.tables;"

# Emergency backup
docker exec pos-db pg_dump -U pos_user pos_db > emergency_backup_$(date +%Y%m%d).sql
```

### **Service Recovery**
```bash
# Restart all containers
docker restart pos-db utmstack-elasticsearch utmstack-logstash

# Check system health
./scripts/production-deployment/quick-health-check.sh

# View recent logs
docker logs pos-db --tail 50
docker logs utmstack-elasticsearch --tail 50
```

---

**⚠️ Security Warning:** 
- Change default passwords before production use
- Configure SSL/TLS for all web services  
- Implement proper authentication for Elasticsearch
- Set up firewall rules for network access
- Regular credential rotation required

**📋 Access Review:**
- Review access logs regularly
- Monitor for unauthorized access attempts
- Update credentials monthly
- Document all access and changes

---

*This document contains sensitive credential information. Store securely and restrict access to authorized personnel only.*
