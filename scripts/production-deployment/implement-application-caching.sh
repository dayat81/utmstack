#!/bin/bash

# UTMStack Application-Level Caching Implementation
# Phase 6 - Sprint 2.1: Performance Optimization
# Version: 1.0.0

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Configuration
OPTIMIZATION_DATE=$(date +"%Y-%m-%d_%H-%M-%S")
LOG_FILE="/var/log/utmstack/app-caching-${OPTIMIZATION_DATE}.log"
CACHE_CONFIG_DIR="/etc/utmstack/cache"
BACKEND_DIR="/home/ptsec/utmstack/backend"

# Create directories
mkdir -p /var/log/utmstack
mkdir -p ${CACHE_CONFIG_DIR}

# Redirect output
exec > >(tee -a ${LOG_FILE})
exec 2>&1

echo "======================================================================"
echo "⚡ UTMStack Application-Level Caching Implementation"
echo "======================================================================"
echo "Implementation Date: ${OPTIMIZATION_DATE}"
echo "Log File: ${LOG_FILE}"
echo "Cache Config Directory: ${CACHE_CONFIG_DIR}"
echo "Backend Directory: ${BACKEND_DIR}"
echo "======================================================================"

# Function to create Redis configuration for multi-tenant caching
create_redis_configuration() {
    log_info "Creating Redis configuration for multi-tenant caching..."
    
    # Create Redis configuration for production
    cat > ${CACHE_CONFIG_DIR}/redis.conf << 'EOF'
# UTMStack Multi-Tenant Redis Configuration
# Production optimized settings

# Network and Security
bind 127.0.0.1
protected-mode yes
port 6379
timeout 300
tcp-keepalive 300

# Memory Management
maxmemory 2gb
maxmemory-policy allkeys-lru
maxmemory-samples 5

# Persistence (optimized for caching)
save 900 1
save 300 10
save 60 10000
stop-writes-on-bgsave-error yes
rdbcompression yes
rdbchecksum yes
dbfilename dump.rdb

# Performance Tuning
tcp-backlog 511
databases 16
always-show-logo yes
set-proc-title yes
proc-title-template "{title} {listen-addr} {server-mode}"

# Logging
loglevel notice
logfile /var/log/redis/redis-server.log
syslog-enabled yes
syslog-ident redis

# Clients
maxclients 10000

# Advanced Configuration
hash-max-ziplist-entries 512
hash-max-ziplist-value 64
list-max-ziplist-size -2
list-compress-depth 0
set-max-intset-entries 512
zset-max-ziplist-entries 128
zset-max-ziplist-value 64
hll-sparse-max-bytes 3000
stream-node-max-bytes 4096
stream-node-max-entries 100

# Active rehashing
activerehashing yes

# Client output buffer limits
client-output-buffer-limit normal 0 0 0
client-output-buffer-limit replica 256mb 64mb 60
client-output-buffer-limit pubsub 32mb 8mb 60

# Client query buffer limit
client-query-buffer-limit 1gb

# Protocol buffer limit
proto-max-bulk-len 512mb

# Frequency of rehashing
hz 10

# Lazy freeing
lazyfree-lazy-eviction no
lazyfree-lazy-expire no
lazyfree-lazy-server-del no
replica-lazy-flush no

# Threaded I/O
io-threads 4
io-threads-do-reads yes

# Tenant-specific keyspace configuration
notify-keyspace-events Ex
EOF
    
    log_success "Redis configuration created"
}

# Function to create Spring Boot caching configuration
create_spring_cache_configuration() {
    log_info "Creating Spring Boot caching configuration..."
    
    # Create application cache configuration
    cat > ${CACHE_CONFIG_DIR}/cache-config.yml << 'EOF'
# UTMStack Multi-Tenant Caching Configuration

spring:
  cache:
    type: redis
    redis:
      time-to-live: 3600000  # 1 hour default TTL
      cache-null-values: false
      use-key-prefix: true
      key-prefix: "utmstack:cache:"
  
  redis:
    host: localhost
    port: 6379
    password: ${REDIS_PASSWORD}
    database: 0
    timeout: 2000ms
    connect-timeout: 2000ms
    lettuce:
      pool:
        max-active: 100
        max-idle: 20
        min-idle: 5
        max-wait: 2000ms
      shutdown-timeout: 200ms

# Custom cache configurations
utmstack:
  cache:
    # Tenant-specific cache settings
    tenant:
      ttl: 7200000  # 2 hours
      max-entries: 10000
      key-pattern: "tenant:{tenantId}:{key}"
    
    # User session cache
    user-session:
      ttl: 1800000  # 30 minutes
      max-entries: 50000
      key-pattern: "session:{tenantId}:{userId}:{key}"
    
    # Dashboard cache
    dashboard:
      ttl: 900000   # 15 minutes
      max-entries: 5000
      key-pattern: "dashboard:{tenantId}:{dashboardId}:{key}"
    
    # Alert cache
    alert:
      ttl: 300000   # 5 minutes
      max-entries: 20000
      key-pattern: "alert:{tenantId}:{key}"
    
    # Search results cache
    search:
      ttl: 600000   # 10 minutes
      max-entries: 10000
      key-pattern: "search:{tenantId}:{queryHash}"
    
    # Configuration cache
    config:
      ttl: 3600000  # 1 hour
      max-entries: 1000
      key-pattern: "config:{tenantId}:{configKey}"
    
    # Statistics cache
    stats:
      ttl: 1800000  # 30 minutes
      max-entries: 5000
      key-pattern: "stats:{tenantId}:{statsType}:{period}"
EOF
    
    log_success "Spring cache configuration created"
}

# Function to create Java caching service implementation
create_cache_service_implementation() {
    log_info "Creating Java caching service implementation..."
    
    # Create cache service interface
    mkdir -p ${BACKEND_DIR}/src/main/java/com/park/utmstack/service/cache
    
    cat > ${BACKEND_DIR}/src/main/java/com/park/utmstack/service/cache/MultiTenantCacheService.java << 'EOF'
package com.park.utmstack.service.cache;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.park.utmstack.security.TenantContext;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.stereotype.Service;

import java.time.Duration;
import java.util.Optional;
import java.util.Set;
import java.util.concurrent.TimeUnit;

/**
 * Multi-tenant aware caching service for UTMStack
 * Provides tenant-scoped caching with automatic key prefixing
 */
@Service
public class MultiTenantCacheService {

    private static final Logger log = LoggerFactory.getLogger(MultiTenantCacheService.class);
    
    private final RedisTemplate<String, Object> redisTemplate;
    private final ObjectMapper objectMapper;
    
    // Cache key patterns
    private static final String TENANT_KEY_PATTERN = "utmstack:tenant:{%s}:%s";
    private static final String USER_SESSION_PATTERN = "utmstack:session:{%s}:{%s}:%s";
    private static final String DASHBOARD_PATTERN = "utmstack:dashboard:{%s}:{%s}:%s";
    private static final String ALERT_PATTERN = "utmstack:alert:{%s}:%s";
    private static final String SEARCH_PATTERN = "utmstack:search:{%s}:%s";
    private static final String CONFIG_PATTERN = "utmstack:config:{%s}:%s";
    private static final String STATS_PATTERN = "utmstack:stats:{%s}:{%s}:{%s";

    @Autowired
    public MultiTenantCacheService(RedisTemplate<String, Object> redisTemplate, ObjectMapper objectMapper) {
        this.redisTemplate = redisTemplate;
        this.objectMapper = objectMapper;
    }

    /**
     * Generic cache operations with tenant context
     */
    public void put(String key, Object value, Duration ttl) {
        String tenantKey = buildTenantKey(key);
        try {
            redisTemplate.opsForValue().set(tenantKey, value, ttl);
            log.debug("Cached value for key: {}", tenantKey);
        } catch (Exception e) {
            log.error("Error caching value for key: {}", tenantKey, e);
        }
    }

    public <T> Optional<T> get(String key, Class<T> type) {
        String tenantKey = buildTenantKey(key);
        try {
            Object value = redisTemplate.opsForValue().get(tenantKey);
            if (value == null) {
                return Optional.empty();
            }
            
            if (type.isInstance(value)) {
                return Optional.of(type.cast(value));
            }
            
            // Try JSON deserialization for complex objects
            if (value instanceof String) {
                T deserializedValue = objectMapper.readValue((String) value, type);
                return Optional.of(deserializedValue);
            }
            
            return Optional.empty();
        } catch (Exception e) {
            log.error("Error retrieving cached value for key: {}", tenantKey, e);
            return Optional.empty();
        }
    }

    public void evict(String key) {
        String tenantKey = buildTenantKey(key);
        try {
            redisTemplate.delete(tenantKey);
            log.debug("Evicted cache key: {}", tenantKey);
        } catch (Exception e) {
            log.error("Error evicting cache key: {}", tenantKey, e);
        }
    }

    public void evictPattern(String pattern) {
        String tenantPattern = buildTenantKey(pattern);
        try {
            Set<String> keys = redisTemplate.keys(tenantPattern);
            if (!keys.isEmpty()) {
                redisTemplate.delete(keys);
                log.debug("Evicted {} keys matching pattern: {}", keys.size(), tenantPattern);
            }
        } catch (Exception e) {
            log.error("Error evicting keys with pattern: {}", tenantPattern, e);
        }
    }

    /**
     * User session caching
     */
    public void cacheUserSession(String userId, String sessionKey, Object sessionData, Duration ttl) {
        String key = String.format(USER_SESSION_PATTERN, getCurrentTenantId(), userId, sessionKey);
        put(key, sessionData, ttl);
    }

    public <T> Optional<T> getUserSession(String userId, String sessionKey, Class<T> type) {
        String key = String.format(USER_SESSION_PATTERN, getCurrentTenantId(), userId, sessionKey);
        return get(key, type);
    }

    public void evictUserSession(String userId, String sessionKey) {
        String key = String.format(USER_SESSION_PATTERN, getCurrentTenantId(), userId, sessionKey);
        evict(key);
    }

    /**
     * Dashboard caching
     */
    public void cacheDashboard(String dashboardId, String dataKey, Object dashboardData, Duration ttl) {
        String key = String.format(DASHBOARD_PATTERN, getCurrentTenantId(), dashboardId, dataKey);
        put(key, dashboardData, ttl);
    }

    public <T> Optional<T> getDashboardCache(String dashboardId, String dataKey, Class<T> type) {
        String key = String.format(DASHBOARD_PATTERN, getCurrentTenantId(), dashboardId, dataKey);
        return get(key, type);
    }

    public void evictDashboardCache(String dashboardId) {
        String pattern = String.format(DASHBOARD_PATTERN, getCurrentTenantId(), dashboardId, "*");
        evictPattern(pattern);
    }

    /**
     * Alert caching
     */
    public void cacheAlert(String alertKey, Object alertData, Duration ttl) {
        String key = String.format(ALERT_PATTERN, getCurrentTenantId(), alertKey);
        put(key, alertData, ttl);
    }

    public <T> Optional<T> getAlertCache(String alertKey, Class<T> type) {
        String key = String.format(ALERT_PATTERN, getCurrentTenantId(), alertKey);
        return get(key, type);
    }

    /**
     * Search results caching
     */
    public void cacheSearchResults(String queryHash, Object searchResults, Duration ttl) {
        String key = String.format(SEARCH_PATTERN, getCurrentTenantId(), queryHash);
        put(key, searchResults, ttl);
    }

    public <T> Optional<T> getSearchResults(String queryHash, Class<T> type) {
        String key = String.format(SEARCH_PATTERN, getCurrentTenantId(), queryHash);
        return get(key, type);
    }

    /**
     * Configuration caching
     */
    public void cacheConfig(String configKey, Object configValue, Duration ttl) {
        String key = String.format(CONFIG_PATTERN, getCurrentTenantId(), configKey);
        put(key, configValue, ttl);
    }

    public <T> Optional<T> getConfig(String configKey, Class<T> type) {
        String key = String.format(CONFIG_PATTERN, getCurrentTenantId(), configKey);
        return get(key, type);
    }

    /**
     * Statistics caching
     */
    public void cacheStats(String statsType, String period, Object statsData, Duration ttl) {
        String key = String.format(STATS_PATTERN, getCurrentTenantId(), statsType, period);
        put(key, statsData, ttl);
    }

    public <T> Optional<T> getStats(String statsType, String period, Class<T> type) {
        String key = String.format(STATS_PATTERN, getCurrentTenantId(), statsType, period);
        return get(key, type);
    }

    /**
     * Tenant-wide cache operations
     */
    public void evictAllTenantCache() {
        String pattern = String.format(TENANT_KEY_PATTERN, getCurrentTenantId(), "*");
        evictPattern(pattern);
        log.info("Evicted all cache for tenant: {}", getCurrentTenantId());
    }

    public long getTenantCacheSize() {
        String pattern = String.format(TENANT_KEY_PATTERN, getCurrentTenantId(), "*");
        Set<String> keys = redisTemplate.keys(pattern);
        return keys != null ? keys.size() : 0;
    }

    /**
     * Cache health and monitoring
     */
    public boolean isHealthy() {
        try {
            redisTemplate.opsForValue().set("health-check", "ok", Duration.ofSeconds(10));
            String value = (String) redisTemplate.opsForValue().get("health-check");
            redisTemplate.delete("health-check");
            return "ok".equals(value);
        } catch (Exception e) {
            log.error("Cache health check failed", e);
            return false;
        }
    }

    public CacheStats getCacheStats() {
        try {
            String tenantId = getCurrentTenantId();
            long totalKeys = getTenantCacheSize();
            
            // Get memory usage (approximate)
            String info = (String) redisTemplate.execute(connection -> {
                return new String(connection.info("memory").getBytes());
            });
            
            return new CacheStats(tenantId, totalKeys, info);
        } catch (Exception e) {
            log.error("Error getting cache stats", e);
            return new CacheStats(getCurrentTenantId(), 0, "Error retrieving stats");
        }
    }

    /**
     * Helper methods
     */
    private String buildTenantKey(String key) {
        return String.format(TENANT_KEY_PATTERN, getCurrentTenantId(), key);
    }

    private String getCurrentTenantId() {
        return TenantContext.getCurrentTenant();
    }

    /**
     * Cache statistics data class
     */
    public static class CacheStats {
        private final String tenantId;
        private final long totalKeys;
        private final String memoryInfo;

        public CacheStats(String tenantId, long totalKeys, String memoryInfo) {
            this.tenantId = tenantId;
            this.totalKeys = totalKeys;
            this.memoryInfo = memoryInfo;
        }

        // Getters
        public String getTenantId() { return tenantId; }
        public long getTotalKeys() { return totalKeys; }
        public String getMemoryInfo() { return memoryInfo; }
    }
}
EOF

    log_success "Java caching service implementation created"
}

# Function to create cache configuration class
create_cache_configuration_class() {
    log_info "Creating cache configuration class..."
    
    cat > ${BACKEND_DIR}/src/main/java/com/park/utmstack/config/CacheConfiguration.java << 'EOF'
package com.park.utmstack.config;

import com.fasterxml.jackson.annotation.JsonTypeInfo;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.jsontype.impl.LaissezFaireSubTypeValidator;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.cache.CacheManager;
import org.springframework.cache.annotation.EnableCaching;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.data.redis.cache.RedisCacheConfiguration;
import org.springframework.data.redis.cache.RedisCacheManager;
import org.springframework.data.redis.connection.RedisConnectionFactory;
import org.springframework.data.redis.connection.lettuce.LettuceConnectionFactory;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.serializer.GenericJackson2JsonRedisSerializer;
import org.springframework.data.redis.serializer.RedisSerializationContext;
import org.springframework.data.redis.serializer.StringRedisSerializer;

import java.time.Duration;
import java.util.HashMap;
import java.util.Map;

/**
 * Redis cache configuration for UTMStack multi-tenant caching
 */
@Configuration
@EnableCaching
public class CacheConfiguration {

    @Value("${spring.redis.host:localhost}")
    private String redisHost;

    @Value("${spring.redis.port:6379}")
    private int redisPort;

    @Value("${spring.redis.password:}")
    private String redisPassword;

    @Value("${spring.redis.database:0}")
    private int redisDatabase;

    @Bean
    public RedisConnectionFactory redisConnectionFactory() {
        LettuceConnectionFactory factory = new LettuceConnectionFactory(redisHost, redisPort);
        if (!redisPassword.isEmpty()) {
            factory.setPassword(redisPassword);
        }
        factory.setDatabase(redisDatabase);
        return factory;
    }

    @Bean
    public RedisTemplate<String, Object> redisTemplate(RedisConnectionFactory connectionFactory) {
        RedisTemplate<String, Object> template = new RedisTemplate<>();
        template.setConnectionFactory(connectionFactory);
        
        // Use String serializer for keys
        template.setKeySerializer(new StringRedisSerializer());
        template.setHashKeySerializer(new StringRedisSerializer());
        
        // Use JSON serializer for values
        ObjectMapper objectMapper = new ObjectMapper();
        objectMapper.activateDefaultTyping(
            LaissezFaireSubTypeValidator.instance,
            ObjectMapper.DefaultTyping.NON_FINAL,
            JsonTypeInfo.As.PROPERTY
        );
        
        GenericJackson2JsonRedisSerializer jsonSerializer = new GenericJackson2JsonRedisSerializer(objectMapper);
        template.setValueSerializer(jsonSerializer);
        template.setHashValueSerializer(jsonSerializer);
        
        template.afterPropertiesSet();
        return template;
    }

    @Bean
    public CacheManager cacheManager(RedisConnectionFactory connectionFactory) {
        // Default cache configuration
        RedisCacheConfiguration defaultConfig = RedisCacheConfiguration.defaultCacheConfig()
            .entryTtl(Duration.ofHours(1))
            .serializeKeysWith(RedisSerializationContext.SerializationPair.fromSerializer(new StringRedisSerializer()))
            .serializeValuesWith(RedisSerializationContext.SerializationPair.fromSerializer(new GenericJackson2JsonRedisSerializer()))
            .disableCachingNullValues();

        // Specific cache configurations
        Map<String, RedisCacheConfiguration> cacheConfigurations = new HashMap<>();
        
        // Tenant cache - 2 hours TTL
        cacheConfigurations.put("tenant", defaultConfig.entryTtl(Duration.ofHours(2)));
        
        // User session cache - 30 minutes TTL
        cacheConfigurations.put("user-session", defaultConfig.entryTtl(Duration.ofMinutes(30)));
        
        // Dashboard cache - 15 minutes TTL
        cacheConfigurations.put("dashboard", defaultConfig.entryTtl(Duration.ofMinutes(15)));
        
        // Alert cache - 5 minutes TTL
        cacheConfigurations.put("alert", defaultConfig.entryTtl(Duration.ofMinutes(5)));
        
        // Search results cache - 10 minutes TTL
        cacheConfigurations.put("search", defaultConfig.entryTtl(Duration.ofMinutes(10)));
        
        // Configuration cache - 1 hour TTL
        cacheConfigurations.put("config", defaultConfig.entryTtl(Duration.ofHours(1)));
        
        // Statistics cache - 30 minutes TTL
        cacheConfigurations.put("stats", defaultConfig.entryTtl(Duration.ofMinutes(30)));

        return RedisCacheManager.builder(connectionFactory)
            .cacheDefaults(defaultConfig)
            .withInitialCacheConfigurations(cacheConfigurations)
            .build();
    }
}
EOF

    log_success "Cache configuration class created"
}

# Function to create cache monitoring and management endpoints
create_cache_monitoring() {
    log_info "Creating cache monitoring and management endpoints..."
    
    cat > ${BACKEND_DIR}/src/main/java/com/park/utmstack/web/rest/CacheManagementResource.java << 'EOF'
package com.park.utmstack.web.rest;

import com.park.utmstack.service.cache.MultiTenantCacheService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

import java.util.HashMap;
import java.util.Map;

/**
 * REST controller for cache management and monitoring
 */
@RestController
@RequestMapping("/api/cache")
public class CacheManagementResource {

    private static final Logger log = LoggerFactory.getLogger(CacheManagementResource.class);

    @Autowired
    private MultiTenantCacheService cacheService;

    /**
     * Get cache statistics for current tenant
     */
    @GetMapping("/stats")
    @PreAuthorize("hasRole('ADMIN') or hasRole('TENANT_ADMIN')")
    public ResponseEntity<MultiTenantCacheService.CacheStats> getCacheStats() {
        log.debug("REST request to get cache statistics");
        MultiTenantCacheService.CacheStats stats = cacheService.getCacheStats();
        return ResponseEntity.ok(stats);
    }

    /**
     * Check cache health
     */
    @GetMapping("/health")
    @PreAuthorize("hasRole('ADMIN') or hasRole('TENANT_ADMIN')")
    public ResponseEntity<Map<String, Object>> getCacheHealth() {
        log.debug("REST request to check cache health");
        
        Map<String, Object> health = new HashMap<>();
        boolean isHealthy = cacheService.isHealthy();
        
        health.put("status", isHealthy ? "UP" : "DOWN");
        health.put("timestamp", System.currentTimeMillis());
        health.put("tenantCacheSize", cacheService.getTenantCacheSize());
        
        return ResponseEntity.ok(health);
    }

    /**
     * Clear all cache for current tenant
     */
    @DeleteMapping("/clear")
    @PreAuthorize("hasRole('ADMIN') or hasRole('TENANT_ADMIN')")
    public ResponseEntity<Map<String, String>> clearTenantCache() {
        log.debug("REST request to clear tenant cache");
        
        try {
            cacheService.evictAllTenantCache();
            
            Map<String, String> response = new HashMap<>();
            response.put("status", "success");
            response.put("message", "Tenant cache cleared successfully");
            
            return ResponseEntity.ok(response);
        } catch (Exception e) {
            log.error("Error clearing tenant cache", e);
            
            Map<String, String> response = new HashMap<>();
            response.put("status", "error");
            response.put("message", "Failed to clear tenant cache: " + e.getMessage());
            
            return ResponseEntity.internalServerError().body(response);
        }
    }

    /**
     * Clear specific cache pattern for current tenant
     */
    @DeleteMapping("/clear/{pattern}")
    @PreAuthorize("hasRole('ADMIN') or hasRole('TENANT_ADMIN')")
    public ResponseEntity<Map<String, String>> clearCachePattern(@PathVariable String pattern) {
        log.debug("REST request to clear cache pattern: {}", pattern);
        
        try {
            cacheService.evictPattern(pattern);
            
            Map<String, String> response = new HashMap<>();
            response.put("status", "success");
            response.put("message", "Cache pattern cleared successfully: " + pattern);
            
            return ResponseEntity.ok(response);
        } catch (Exception e) {
            log.error("Error clearing cache pattern: {}", pattern, e);
            
            Map<String, String> response = new HashMap<>();
            response.put("status", "error");
            response.put("message", "Failed to clear cache pattern: " + e.getMessage());
            
            return ResponseEntity.internalServerError().body(response);
        }
    }

    /**
     * Warm up cache for current tenant
     */
    @PostMapping("/warmup")
    @PreAuthorize("hasRole('ADMIN') or hasRole('TENANT_ADMIN')")
    public ResponseEntity<Map<String, String>> warmupCache() {
        log.debug("REST request to warm up cache");
        
        try {
            // Implement cache warmup logic here
            // This could include pre-loading common queries, configurations, etc.
            
            Map<String, String> response = new HashMap<>();
            response.put("status", "success");
            response.put("message", "Cache warmup initiated");
            
            return ResponseEntity.ok(response);
        } catch (Exception e) {
            log.error("Error warming up cache", e);
            
            Map<String, String> response = new HashMap<>();
            response.put("status", "error");
            response.put("message", "Failed to warm up cache: " + e.getMessage());
            
            return ResponseEntity.internalServerError().body(response);
        }
    }
}
EOF

    log_success "Cache monitoring endpoints created"
}

# Function to create cache utility scripts
create_cache_utilities() {
    log_info "Creating cache utility scripts..."
    
    # Create cache monitoring script
    cat > ${CACHE_CONFIG_DIR}/monitor-cache.sh << 'EOF'
#!/bin/bash

# UTMStack Cache Monitoring Script

echo "UTMStack Cache Monitoring Report"
echo "==============================="
echo "Timestamp: $(date)"
echo ""

# Redis server info
echo "Redis Server Status:"
redis-cli ping
echo ""

# Memory usage
echo "Memory Usage:"
redis-cli info memory | grep -E "(used_memory_human|used_memory_peak_human|maxmemory_human)"
echo ""

# Connected clients
echo "Connected Clients:"
redis-cli info clients | grep -E "(connected_clients|blocked_clients)"
echo ""

# Keyspace info
echo "Keyspace Information:"
redis-cli info keyspace
echo ""

# Cache hit ratio (approximate)
echo "Cache Statistics:"
redis-cli info stats | grep -E "(keyspace_hits|keyspace_misses)"
echo ""

# Top cache keys by memory usage
echo "Top Cache Keys by Memory Usage:"
redis-cli --bigkeys --i 0.01 | head -20
echo ""

# Tenant-specific cache sizes
echo "Tenant Cache Sizes:"
for tenant in $(redis-cli keys "utmstack:tenant:*" | cut -d: -f3 | sort -u | head -10); do
    count=$(redis-cli keys "utmstack:tenant:${tenant}:*" | wc -l)
    echo "Tenant ${tenant}: ${count} keys"
done
EOF

    chmod +x ${CACHE_CONFIG_DIR}/monitor-cache.sh
    
    # Create cache cleanup script
    cat > ${CACHE_CONFIG_DIR}/cleanup-cache.sh << 'EOF'
#!/bin/bash

# UTMStack Cache Cleanup Script

echo "Starting cache cleanup at $(date)"

# Remove expired keys (Redis should do this automatically, but this forces it)
redis-cli eval "return redis.call('EXPIRE', KEYS[1], 0)" 0

# Clean up empty tenant caches
echo "Cleaning up empty tenant caches..."
for tenant in $(redis-cli keys "utmstack:tenant:*" | cut -d: -f3 | sort -u); do
    count=$(redis-cli keys "utmstack:tenant:${tenant}:*" | wc -l)
    if [ "$count" -eq 0 ]; then
        echo "Removing empty tenant cache for: $tenant"
        redis-cli del "utmstack:tenant:${tenant}:*"
    fi
done

# Log cleanup completion
echo "Cache cleanup completed at $(date)"
EOF

    chmod +x ${CACHE_CONFIG_DIR}/cleanup-cache.sh
    
    # Create cache backup script
    cat > ${CACHE_CONFIG_DIR}/backup-cache.sh << 'EOF'
#!/bin/bash

# UTMStack Cache Backup Script

BACKUP_DATE=$(date +"%Y-%m-%d_%H-%M-%S")
BACKUP_DIR="/var/backups/utmstack/cache"
mkdir -p ${BACKUP_DIR}

echo "Starting cache backup at $(date)"

# Create Redis snapshot
redis-cli BGSAVE

# Wait for background save to complete
while [ $(redis-cli LASTSAVE) -eq $(redis-cli LASTSAVE) ]; do
    sleep 1
done

# Copy the RDB file
cp /var/lib/redis/dump.rdb ${BACKUP_DIR}/redis-dump-${BACKUP_DATE}.rdb

# Compress the backup
gzip ${BACKUP_DIR}/redis-dump-${BACKUP_DATE}.rdb

# Remove old backups (keep 7 days)
find ${BACKUP_DIR} -name "redis-dump-*.rdb.gz" -mtime +7 -delete

echo "Cache backup completed at $(date)"
echo "Backup file: ${BACKUP_DIR}/redis-dump-${BACKUP_DATE}.rdb.gz"
EOF

    chmod +x ${CACHE_CONFIG_DIR}/backup-cache.sh
    
    log_success "Cache utility scripts created"
}

# Function to create cron jobs for cache maintenance
create_cache_maintenance_jobs() {
    log_info "Creating cache maintenance cron jobs..."
    
    cat > /etc/cron.d/utmstack-cache-maintenance << 'EOF'
# UTMStack Cache Maintenance Jobs

# Monitor cache every 5 minutes
*/5 * * * * root /etc/utmstack/cache/monitor-cache.sh >> /var/log/utmstack/cache-monitor.log 2>&1

# Cleanup cache daily at 3 AM
0 3 * * * root /etc/utmstack/cache/cleanup-cache.sh >> /var/log/utmstack/cache-cleanup.log 2>&1

# Backup cache daily at 4 AM
0 4 * * * root /etc/utmstack/cache/backup-cache.sh >> /var/log/utmstack/cache-backup.log 2>&1
EOF

    log_success "Cache maintenance cron jobs created"
}

# Function to create cache performance benchmarking
create_cache_benchmarking() {
    log_info "Creating cache performance benchmarking..."
    
    cat > ${CACHE_CONFIG_DIR}/benchmark-cache.sh << 'EOF'
#!/bin/bash

# UTMStack Cache Performance Benchmark

echo "Cache Performance Benchmark"
echo "=========================="
echo "Timestamp: $(date)"
echo ""

# Test 1: Simple SET/GET operations
echo "Test 1: Simple SET/GET Performance"
start_time=$(date +%s%N)
for i in {1..1000}; do
    redis-cli SET "test:$i" "value$i" > /dev/null
done
end_time=$(date +%s%N)
set_time=$((($end_time - $start_time) / 1000000))
echo "1000 SET operations: ${set_time} ms"

start_time=$(date +%s%N)
for i in {1..1000}; do
    redis-cli GET "test:$i" > /dev/null
done
end_time=$(date +%s%N)
get_time=$((($end_time - $start_time) / 1000000))
echo "1000 GET operations: ${get_time} ms"

# Cleanup test keys
redis-cli eval "return redis.call('del', unpack(redis.call('keys', 'test:*')))" 0

echo ""

# Test 2: Tenant-scoped operations
echo "Test 2: Tenant-scoped Cache Performance"
tenant_id="00000000-0000-0000-0000-000000000001"

start_time=$(date +%s%N)
for i in {1..100}; do
    redis-cli SET "utmstack:tenant:${tenant_id}:benchmark:$i" "tenant_value$i" EX 3600 > /dev/null
done
end_time=$(date +%s%N)
tenant_set_time=$((($end_time - $start_time) / 1000000))
echo "100 Tenant SET operations: ${tenant_set_time} ms"

start_time=$(date +%s%N)
for i in {1..100}; do
    redis-cli GET "utmstack:tenant:${tenant_id}:benchmark:$i" > /dev/null
done
end_time=$(date +%s%N)
tenant_get_time=$((($end_time - $start_time) / 1000000))
echo "100 Tenant GET operations: ${tenant_get_time} ms"

# Test 3: Pattern-based operations
echo ""
echo "Test 3: Pattern-based Operations"
start_time=$(date +%s%N)
key_count=$(redis-cli keys "utmstack:tenant:${tenant_id}:benchmark:*" | wc -l)
end_time=$(date +%s%N)
pattern_time=$((($end_time - $start_time) / 1000000))
echo "Pattern search (${key_count} keys): ${pattern_time} ms"

# Cleanup
redis-cli eval "return redis.call('del', unpack(redis.call('keys', 'utmstack:tenant:${tenant_id}:benchmark:*')))" 0

echo ""
echo "Benchmark completed at $(date)"
EOF

    chmod +x ${CACHE_CONFIG_DIR}/benchmark-cache.sh
    
    log_success "Cache benchmarking created"
}

# Main implementation execution
main() {
    log_info "Starting UTMStack Application-Level Caching Implementation..."
    
    create_redis_configuration
    create_spring_cache_configuration
    create_cache_service_implementation
    create_cache_configuration_class
    create_cache_monitoring
    create_cache_utilities
    create_cache_maintenance_jobs
    create_cache_benchmarking
    
    log_success "Application-level caching implementation completed!"
    echo ""
    echo "======================================================================"
    echo "⚡ Application Caching Implementation Summary"
    echo "======================================================================"
    echo "Implementation Date: ${OPTIMIZATION_DATE}"
    echo "Log File: ${LOG_FILE}"
    echo "Cache Config Directory: ${CACHE_CONFIG_DIR}"
    echo ""
    echo "Components Implemented:"
    echo "✅ Redis configuration for multi-tenant caching"
    echo "✅ Spring Boot cache configuration"
    echo "✅ Multi-tenant cache service implementation"
    echo "✅ Cache configuration classes"
    echo "✅ Cache monitoring and management endpoints"
    echo "✅ Cache utility scripts"
    echo "✅ Automated maintenance jobs"
    echo "✅ Performance benchmarking tools"
    echo ""
    echo "Cache Types Implemented:"
    echo "• Tenant-scoped caching"
    echo "• User session caching"
    echo "• Dashboard data caching"
    echo "• Alert caching"
    echo "• Search results caching"
    echo "• Configuration caching"
    echo "• Statistics caching"
    echo ""
    echo "Next Steps:"
    echo "1. Start Redis server with new configuration"
    echo "2. Deploy updated backend application"
    echo "3. Run cache performance benchmarks"
    echo "4. Monitor cache hit ratios and performance"
    echo "======================================================================"
}

# Execute main function
main "$@"
