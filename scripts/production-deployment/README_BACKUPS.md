# UTMStack Production Backup System

## Overview

This comprehensive backup solution provides automated, production-ready backup procedures for UTMStack including PostgreSQL databases, Elasticsearch indices, configuration files, and log management with compression, rotation, and remote storage capabilities.

## Components

### Core Backup Scripts

1. **`backup-postgresql.sh`** - PostgreSQL database backups
   - Creates both custom format (.dump) and SQL format (.sql.gz) backups
   - Supports compression and integrity validation
   - Handles connection health checks and error recovery

2. **`backup-elasticsearch.sh`** - Elasticsearch index backups
   - Uses Elasticsearch snapshot API for consistent backups
   - Exports cluster settings, mappings, and metadata
   - Supports incremental snapshots and parallel operations

3. **`backup-config.sh`** - Configuration file backups
   - Backs up all UTMStack configuration files
   - Includes system information and metadata
   - Captures database schemas and Elasticsearch mappings

4. **`backup-logs.sh`** - Log archival and retention
   - Automated log rotation and compression
   - Configurable retention policies
   - Handles active log files safely

5. **`backup-master.sh`** - Orchestration script
   - Coordinates all backup operations
   - Provides health checks and notifications
   - Supports different backup types (full/incremental/config-only)

### Management Scripts

6. **`setup-backup-schedule.sh`** - Automated scheduling setup
   - Configures systemd timers or cron jobs
   - Creates monitoring and alerting
   - Sets up restoration capabilities

7. **`monitor-backups.sh`** - Backup monitoring and alerting
8. **`restore-backup.sh`** - Backup restoration utilities

## Installation and Setup

### 1. Initial Setup

```bash
# Navigate to the scripts directory
cd /home/ptsec/utmstack/scripts/production-deployment

# Run the setup script (requires root/sudo)
sudo ./setup-backup-schedule.sh
```

### 2. Configuration

Edit the environment configuration file:
```bash
nano backup.env
```

Key settings:
- `BACKUP_BASE_PATH`: Where backups are stored (default: `/var/backups/utmstack`)
- `BACKUP_RETENTION_DAYS`: How long to keep backups (default: 30 days)
- `REMOTE_BACKUP_ENABLED`: Enable remote storage (default: false)
- `REMOTE_BACKUP_PATH`: Remote storage location (s3://, rsync://, scp://)

### 3. Database Credentials

Update database credentials in the environment file or export them:
```bash
export POSTGRES_HOST="localhost"
export POSTGRES_PORT="5432"
export POSTGRES_DB="utmstack"
export POSTGRES_USER="postgres"
export POSTGRES_PASSWORD="admin"
```

## Backup Schedule

The automated schedule includes:

- **Full Backup**: Daily at 2:00 AM
- **Incremental Backup**: Every 6 hours (00:30, 06:30, 12:30, 18:30)
- **Configuration Backup**: Every 4 hours (00:15, 04:15, 08:15, 12:15, 16:15, 20:15)
- **Log Cleanup**: Weekly on Sunday at 3:00 AM
- **Monitoring**: Hourly health checks

## Manual Operations

### Manual Backup

```bash
# Full backup
./backup-master.sh full

# Incremental backup
./backup-master.sh incremental

# Configuration only
./backup-master.sh config-only

# Individual components
./backup-postgresql.sh
./backup-elasticsearch.sh
./backup-config.sh
./backup-logs.sh
```

### Monitoring

```bash
# Check backup status
./monitor-backups.sh

# View backup reports
ls -la /var/backups/utmstack/*/backup_report_*.txt

# Check systemd timer status
systemctl status utmstack-backup-*.timer
```

### Restoration

```bash
# Restore PostgreSQL from latest backup
./restore-backup.sh postgresql

# Restore configuration from specific backup
./restore-backup.sh config /var/backups/utmstack/config/utmstack_config_20250810_020000.tar.gz

# Restore all components from latest backups
./restore-backup.sh all
```

## Remote Storage Support

### AWS S3

```bash
export REMOTE_BACKUP_ENABLED="true"
export REMOTE_BACKUP_PATH="s3://your-backup-bucket/utmstack"
```

Requires AWS CLI configured with appropriate credentials.

### Rsync

```bash
export REMOTE_BACKUP_ENABLED="true"
export REMOTE_BACKUP_PATH="rsync://backup-server/utmstack"
```

### SCP

```bash
export REMOTE_BACKUP_ENABLED="true"
export REMOTE_BACKUP_PATH="scp://user@backup-server:/backups/utmstack"
```

## Notifications and Alerting

### Email Notifications

```bash
export NOTIFICATION_ENABLED="true"
export NOTIFICATION_EMAIL="admin@yourcompany.com"
```

### Webhook Notifications

```bash
export NOTIFICATION_ENABLED="true"
export NOTIFICATION_WEBHOOK="https://your-webhook-url/endpoint"
```

## File Locations

### Backup Storage
- **Base Path**: `/var/backups/utmstack/`
- **PostgreSQL**: `/var/backups/utmstack/postgresql/`
- **Elasticsearch**: `/var/backups/utmstack/elasticsearch/`
- **Configuration**: `/var/backups/utmstack/config/`
- **Logs**: `/var/backups/utmstack/logs/`

### Log Files
- **Backup Logs**: `/var/log/utmstack/backup-*.log`
- **Monitoring Logs**: `/var/log/utmstack/backup-monitor.log`

### Configuration
- **Environment**: `./backup.env`
- **Systemd Services**: `/etc/systemd/system/utmstack-backup-*.service`
- **Systemd Timers**: `/etc/systemd/system/utmstack-backup-*.timer`
- **Cron Jobs**: `/etc/cron.d/utmstack-backup`

## Backup Types and Retention

### Full Backup
- Complete PostgreSQL database dump (custom + SQL format)
- Full Elasticsearch snapshot
- All configuration files and metadata
- System information and schemas

### Incremental Backup
- Configuration files and logs
- Database/Elasticsearch only if older than 24 hours

### Configuration-Only Backup
- UTMStack configuration files
- Database schemas and ES mappings
- System metadata

## Security Considerations

1. **Credentials**: Store database passwords securely
2. **File Permissions**: Backup files are readable only by backup user
3. **Network Security**: Use encrypted transport for remote backups
4. **Access Control**: Limit access to backup directories
5. **Encryption**: Consider encrypting backups at rest

## Troubleshooting

### Check Backup Status
```bash
# View recent logs
tail -f /var/log/utmstack/backup-master.log

# Check disk space
df -h /var/backups

# Verify services
systemctl status utmstack-backup-*.timer
```

### Common Issues

1. **Insufficient Disk Space**: Increase storage or adjust retention
2. **Database Connection Failures**: Check credentials and connectivity
3. **Permission Errors**: Ensure backup user has proper permissions
4. **Remote Upload Failures**: Verify network connectivity and credentials

### Recovery Testing

Regularly test backup restoration:
```bash
# Test database restore to temporary instance
./restore-backup.sh postgresql /path/to/backup.sql.gz

# Validate Elasticsearch snapshots
curl -X GET "localhost:9200/_snapshot/utmstack_backup_repo/_all"
```

## Performance Optimization

1. **Compression**: Adjust `COMPRESSION_LEVEL` (1-9, default: 6)
2. **Parallel Operations**: Elasticsearch supports parallel snapshots
3. **Network Bandwidth**: Configure remote backup throttling
4. **Storage**: Use appropriate storage classes for remote backups
5. **Scheduling**: Stagger backup operations to avoid resource conflicts

## Monitoring and Metrics

The backup system provides:
- Success/failure notifications
- Backup size and duration metrics
- Health checks for all components
- Disk space monitoring
- Service availability checks

Access monitoring reports at:
- `/var/backups/utmstack/*/backup_report_*.txt`
- `/var/log/utmstack/backup-*.log`

## Maintenance

### Regular Tasks
1. Monitor disk usage and adjust retention policies
2. Test restoration procedures monthly
3. Verify remote backup integrity
4. Review and update notification settings
5. Check for failed backups and investigate

### Updating Configuration
After modifying `backup.env`, restart the services:
```bash
sudo systemctl daemon-reload
sudo systemctl restart utmstack-backup-*.timer
```

## Support

For issues or questions:
1. Check log files in `/var/log/utmstack/`
2. Review backup reports in `/var/backups/utmstack/`
3. Verify system requirements and dependencies
4. Contact UTMStack support with relevant log excerpts
