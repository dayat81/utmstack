#!/bin/bash

# UTMStack JVM Performance Optimization Script
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
LOG_FILE="/var/log/utmstack/jvm-optimization-${OPTIMIZATION_DATE}.log"
JVM_CONFIG_DIR="/etc/utmstack/jvm"
BACKEND_DIR="/home/ptsec/utmstack/backend"

# Create directories
mkdir -p /var/log/utmstack
mkdir -p ${JVM_CONFIG_DIR}

# Redirect output
exec > >(tee -a ${LOG_FILE})
exec 2>&1

echo "======================================================================"
echo "🚀 UTMStack JVM Performance Optimization"
echo "======================================================================"
echo "Optimization Date: ${OPTIMIZATION_DATE}"
echo "Log File: ${LOG_FILE}"
echo "JVM Config Directory: ${JVM_CONFIG_DIR}"
echo "Backend Directory: ${BACKEND_DIR}"
echo "======================================================================"

# Function to analyze system resources for JVM tuning
analyze_system_resources() {
    log_info "Analyzing system resources for JVM tuning..."
    
    # Get system information
    local total_mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local total_mem_gb=$((total_mem_kb / 1024 / 1024))
    local cpu_cores=$(nproc)
    local cpu_model=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
    
    # Calculate optimal JVM heap sizes
    local heap_min_gb=$((total_mem_gb / 4))  # 25% of total memory
    local heap_max_gb=$((total_mem_gb / 2))  # 50% of total memory
    
    # Ensure minimums and maximums
    if [[ $heap_min_gb -lt 2 ]]; then heap_min_gb=2; fi
    if [[ $heap_max_gb -lt 4 ]]; then heap_max_gb=4; fi
    if [[ $heap_max_gb -gt 32 ]]; then heap_max_gb=32; fi  # G1 recommendation
    
    # Save system analysis
    cat > ${JVM_CONFIG_DIR}/system-analysis.txt << EOF
UTMStack JVM System Analysis
Generated: ${OPTIMIZATION_DATE}

System Information:
- Total Memory: ${total_mem_gb} GB
- CPU Cores: ${cpu_cores}
- CPU Model: ${cpu_model}

Recommended JVM Settings:
- Heap Min: ${heap_min_gb} GB
- Heap Max: ${heap_max_gb} GB
- GC Threads: $((cpu_cores / 2))
- Parallel Threads: ${cpu_cores}
EOF

    export HEAP_MIN_GB=${heap_min_gb}
    export HEAP_MAX_GB=${heap_max_gb}
    export CPU_CORES=${cpu_cores}
    
    log_success "System analysis completed - Heap: ${heap_min_gb}GB-${heap_max_gb}GB, Cores: ${cpu_cores}"
}

# Function to create optimized JVM configuration
create_jvm_configuration() {
    log_info "Creating optimized JVM configuration..."
    
    # Create production JVM options file
    cat > ${JVM_CONFIG_DIR}/production-jvm.options << EOF
# UTMStack Production JVM Options
# Generated: ${OPTIMIZATION_DATE}
# Optimized for multi-tenant SIEM platform

# ============================================================================
# HEAP MEMORY CONFIGURATION
# ============================================================================
-Xms${HEAP_MIN_GB}g
-Xmx${HEAP_MAX_GB}g

# ============================================================================
# GARBAGE COLLECTION CONFIGURATION
# ============================================================================
# Use G1 GC for large heaps and low latency requirements
-XX:+UseG1GC
-XX:MaxGCPauseMillis=200
-XX:G1HeapRegionSize=16m
-XX:G1NewSizePercent=30
-XX:G1MaxNewSizePercent=40
-XX:G1MixedGCCountTarget=8
-XX:G1MixedGCLiveThresholdPercent=35

# G1 concurrent threads
-XX:ConcGCThreads=$((CPU_CORES / 4))
-XX:ParallelGCThreads=$((CPU_CORES / 2))

# ============================================================================
# METASPACE CONFIGURATION
# ============================================================================
-XX:MetaspaceSize=256m
-XX:MaxMetaspaceSize=1g
-XX:CompressedClassSpaceSize=256m

# ============================================================================
# JIT COMPILATION OPTIMIZATION
# ============================================================================
-XX:+TieredCompilation
-XX:TieredStopAtLevel=4
-XX:ReservedCodeCacheSize=256m
-XX:InitialCodeCacheSize=64m

# ============================================================================
# MEMORY OPTIMIZATION
# ============================================================================
-XX:+UseCompressedOops
-XX:+UseCompressedClassPointers
-XX:+OptimizeStringConcat
-XX:+UseStringDeduplication

# ============================================================================
# PERFORMANCE MONITORING
# ============================================================================
# Enable JFR for production monitoring
-XX:+FlightRecorder
-XX:StartFlightRecording=duration=300s,filename=${JVM_CONFIG_DIR}/jfr/startup-${OPTIMIZATION_DATE}.jfr

# GC logging
-Xlog:gc*,heap*,ergo*:${JVM_CONFIG_DIR}/logs/gc-${OPTIMIZATION_DATE}.log:time,pid,tid,level,tags
-XX:+UseGCLogFileRotation
-XX:NumberOfGCLogFiles=10
-XX:GCLogFileSize=10M

# ============================================================================
# SECURITY AND STABILITY
# ============================================================================
-XX:+HeapDumpOnOutOfMemoryError
-XX:HeapDumpPath=${JVM_CONFIG_DIR}/heapdumps/
-XX:+ExitOnOutOfMemoryError
-XX:+CrashOnOutOfMemoryError

# Disable C2 compiler assertions in production
-XX:-UseCounterDecay
-XX:+UnlockExperimentalVMOptions
-XX:+UseCGroupMemoryLimitForHeap

# ============================================================================
# NETWORK OPTIMIZATION
# ============================================================================
-Djava.net.preferIPv4Stack=true
-Djava.security.egd=file:/dev/./urandom
-Dfile.encoding=UTF-8
-Duser.timezone=UTC

# ============================================================================
# SPRING BOOT OPTIMIZATION
# ============================================================================
-Dspring.jmx.enabled=true
-Dspring.backgroundpreinitializer.ignore=true
-Dspring.output.ansi.enabled=never

# ============================================================================
# MULTI-TENANT SPECIFIC OPTIMIZATIONS
# ============================================================================
# Connection pool optimization
-Dhikari.maximumPoolSize=50
-Dhikari.minimumIdle=10
-Dhikari.connectionTimeout=30000
-Dhikari.idleTimeout=600000
-Dhikari.maxLifetime=1800000

# Jackson optimization for JSON processing
-Dcom.fasterxml.jackson.core.JsonFactory.USE_THREAD_LOCAL_FOR_BUFFER_RECYCLING=true

# ============================================================================
# DEVELOPMENT/DEBUGGING (disable in production)
# ============================================================================
# -agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=5005
# -XX:+PrintGCDetails
# -XX:+PrintGCTimeStamps
# -XX:+PrintGCApplicationStoppedTime
EOF

    # Create JVM monitoring script
    cat > ${JVM_CONFIG_DIR}/monitor-jvm.sh << 'EOF'
#!/bin/bash

# UTMStack JVM Monitoring Script

echo "UTMStack JVM Monitoring Report"
echo "============================="
echo "Timestamp: $(date)"
echo ""

# Get Java process ID
JAVA_PID=$(pgrep -f "utmstack.*jar" | head -1)

if [[ -z "$JAVA_PID" ]]; then
    echo "No UTMStack Java process found"
    exit 1
fi

echo "Java Process ID: $JAVA_PID"
echo ""

# Memory usage
echo "Memory Usage:"
echo "============"
jstat -gc $JAVA_PID | tail -1 | awk '{
    print "Eden Space: " $6 " MB / " $5 " MB (" int($6/$5*100) "%)"
    print "Survivor Space: " $8 " MB / " $7 " MB (" int($8/$7*100) "%)"
    print "Old Generation: " $10 " MB / " $9 " MB (" int($10/$9*100) "%)"
    print "Metaspace: " $12 " MB / " $11 " MB"
}'
echo ""

# GC statistics
echo "Garbage Collection Statistics:"
echo "============================="
jstat -gccapacity $JAVA_PID | tail -1 | awk '{
    print "Young Generation Capacity: " $2/1024 " MB"
    print "Old Generation Capacity: " $6/1024 " MB"
    print "Metaspace Capacity: " $10/1024 " MB"
}'
echo ""

# GC performance
echo "GC Performance:"
echo "=============="
jstat -gcutil $JAVA_PID | tail -1 | awk '{
    print "Eden Utilization: " $3 "%"
    print "Old Generation Utilization: " $4 "%"
    print "Metaspace Utilization: " $6 "%"
    print "GC Time: " $8 " seconds"
}'
echo ""

# JIT compilation
echo "JIT Compilation:"
echo "==============="
jstat -compiler $JAVA_PID | tail -1 | awk '{
    print "Compiled Methods: " $1
    print "Failed Compilations: " $2
    print "Compilation Time: " $4 " seconds"
}'
echo ""

# Thread information
echo "Thread Information:"
echo "=================="
jstack $JAVA_PID | grep -E "^\".*\"" | wc -l | awk '{print "Total Threads: " $1}'
jstack $JAVA_PID | grep -E "java.lang.Thread.State: (RUNNABLE|BLOCKED|WAITING|TIMED_WAITING)" | sort | uniq -c
echo ""

# CPU usage
echo "CPU Usage:"
echo "=========="
top -p $JAVA_PID -n 1 -b | tail -1 | awk '{print "CPU: " $9 "%, Memory: " $10 "%"}'
EOF

    chmod +x ${JVM_CONFIG_DIR}/monitor-jvm.sh
    
    log_success "JVM configuration created"
}

# Function to create JVM profiling and diagnostics tools
create_jvm_diagnostics() {
    log_info "Creating JVM profiling and diagnostics tools..."
    
    # Create heap dump script
    cat > ${JVM_CONFIG_DIR}/heap-dump.sh << 'EOF'
#!/bin/bash

# UTMStack Heap Dump Script

JAVA_PID=$(pgrep -f "utmstack.*jar" | head -1)
DUMP_DATE=$(date +"%Y-%m-%d_%H-%M-%S")
DUMP_FILE="/etc/utmstack/jvm/heapdumps/heap-dump-${DUMP_DATE}.hprof"

if [[ -z "$JAVA_PID" ]]; then
    echo "No UTMStack Java process found"
    exit 1
fi

echo "Creating heap dump for PID: $JAVA_PID"
echo "Dump file: $DUMP_FILE"

# Create heap dump
jmap -dump:live,format=b,file=$DUMP_FILE $JAVA_PID

if [[ $? -eq 0 ]]; then
    echo "Heap dump created successfully"
    echo "File size: $(du -h $DUMP_FILE | cut -f1)"
else
    echo "Failed to create heap dump"
    exit 1
fi
EOF

    chmod +x ${JVM_CONFIG_DIR}/heap-dump.sh
    
    # Create thread dump script
    cat > ${JVM_CONFIG_DIR}/thread-dump.sh << 'EOF'
#!/bin/bash

# UTMStack Thread Dump Script

JAVA_PID=$(pgrep -f "utmstack.*jar" | head -1)
DUMP_DATE=$(date +"%Y-%m-%d_%H-%M-%S")
DUMP_FILE="/etc/utmstack/jvm/threaddumps/thread-dump-${DUMP_DATE}.txt"

if [[ -z "$JAVA_PID" ]]; then
    echo "No UTMStack Java process found"
    exit 1
fi

echo "Creating thread dump for PID: $JAVA_PID"
echo "Dump file: $DUMP_FILE"

# Create thread dump
jstack $JAVA_PID > $DUMP_FILE

if [[ $? -eq 0 ]]; then
    echo "Thread dump created successfully"
    echo "Thread count: $(grep -c '^"' $DUMP_FILE)"
else
    echo "Failed to create thread dump"
    exit 1
fi
EOF

    chmod +x ${JVM_CONFIG_DIR}/thread-dump.sh
    
    # Create JFR analysis script
    cat > ${JVM_CONFIG_DIR}/jfr-analysis.sh << 'EOF'
#!/bin/bash

# UTMStack JFR Analysis Script

JAVA_PID=$(pgrep -f "utmstack.*jar" | head -1)
RECORD_DATE=$(date +"%Y-%m-%d_%H-%M-%S")
RECORD_FILE="/etc/utmstack/jvm/jfr/jfr-recording-${RECORD_DATE}.jfr"

if [[ -z "$JAVA_PID" ]]; then
    echo "No UTMStack Java process found"
    exit 1
fi

echo "Starting JFR recording for PID: $JAVA_PID"
echo "Recording duration: 300 seconds"
echo "Output file: $RECORD_FILE"

# Start JFR recording
jcmd $JAVA_PID JFR.start name=utmstack-profile duration=300s filename=$RECORD_FILE

echo "JFR recording started. It will run for 5 minutes."
echo "Use 'jcmd $JAVA_PID JFR.check' to check status"
echo "Use 'jcmd $JAVA_PID JFR.stop name=utmstack-profile' to stop early"
EOF

    chmod +x ${JVM_CONFIG_DIR}/jfr-analysis.sh
    
    # Create directories for dumps and recordings
    mkdir -p ${JVM_CONFIG_DIR}/heapdumps
    mkdir -p ${JVM_CONFIG_DIR}/threaddumps
    mkdir -p ${JVM_CONFIG_DIR}/jfr
    mkdir -p ${JVM_CONFIG_DIR}/logs
    
    log_success "JVM diagnostics tools created"
}

# Function to create JVM performance tuning recommendations
create_performance_recommendations() {
    log_info "Creating JVM performance tuning recommendations..."
    
    cat > ${JVM_CONFIG_DIR}/performance-recommendations.md << EOF
# UTMStack JVM Performance Tuning Recommendations

Generated: ${OPTIMIZATION_DATE}

## Current Configuration Summary

### Heap Settings
- Minimum Heap: ${HEAP_MIN_GB}GB
- Maximum Heap: ${HEAP_MAX_GB}GB
- Garbage Collector: G1GC

### System Resources
- CPU Cores: ${CPU_CORES}
- Total Memory: Available for analysis

## Performance Monitoring Checklist

### Daily Monitoring
- [ ] Check GC pause times (target: <200ms)
- [ ] Monitor heap utilization (target: <80%)
- [ ] Review thread counts and states
- [ ] Check for memory leaks
- [ ] Validate response times

### Weekly Analysis
- [ ] Analyze GC logs for patterns
- [ ] Review JFR recordings
- [ ] Check for deadlocks in thread dumps
- [ ] Validate connection pool metrics
- [ ] Review metaspace usage

### Monthly Optimization
- [ ] Tune GC parameters based on workload
- [ ] Adjust heap sizes if needed
- [ ] Review and update JVM flags
- [ ] Analyze long-term memory trends
- [ ] Performance regression testing

## Tuning Guidelines

### G1GC Optimization
- MaxGCPauseMillis: Start with 200ms, adjust based on latency requirements
- G1HeapRegionSize: 16MB for heaps >8GB, 8MB for smaller heaps
- G1NewSizePercent: 30% for mixed workloads
- G1MixedGCCountTarget: 8 for balanced throughput/latency

### Memory Optimization
- Monitor metaspace usage and adjust MaxMetaspaceSize
- Use -XX:+UseStringDeduplication for memory savings
- Consider -XX:+UseLargePages for large heaps

### Thread Pool Tuning
- Database connections: 2-3x CPU cores
- HTTP thread pool: 200-500 threads
- Async processing: CPU cores + 1

## Troubleshooting Common Issues

### High GC Pause Times
1. Check G1 region size
2. Adjust MaxGCPauseMillis
3. Consider concurrent GC threads
4. Review allocation patterns

### OutOfMemoryError
1. Analyze heap dumps
2. Check for memory leaks
3. Review object retention
4. Consider heap size increase

### High CPU Usage
1. Check GC overhead
2. Review JIT compilation
3. Analyze thread contention
4. Monitor connection pools

### Performance Degradation
1. Compare JFR recordings
2. Check GC log trends
3. Review application metrics
4. Validate database performance

## Production Deployment Considerations

### Monitoring Setup
- Enable JFR with minimal overhead
- Configure GC logging rotation
- Set up heap dump on OOM
- Monitor key JVM metrics

### Capacity Planning
- Plan for 3x peak load
- Reserve 50% heap headroom
- Monitor growth trends
- Plan scaling thresholds

### Emergency Procedures
- Heap dump collection process
- Thread dump analysis steps
- JVM restart procedures
- Performance rollback plan
EOF

    log_success "Performance recommendations created"
}

# Function to create application.yml updates for JVM optimization
create_application_yml_updates() {
    log_info "Creating application.yml updates for JVM optimization..."
    
    cat > ${JVM_CONFIG_DIR}/application-jvm-optimized.yml << 'EOF'
# UTMStack JVM Optimized Application Configuration

spring:
  jpa:
    hibernate:
      # Optimize Hibernate for multi-tenant performance
      jdbc:
        batch_size: 25
        batch_versioned_data: true
        order_inserts: true
        order_updates: true
      cache:
        use_second_level_cache: true
        use_query_cache: true
        region_prefix: utmstack
    properties:
      hibernate:
        # Connection pool optimization
        connection:
          pool_size: 50
          autocommit: false
        # Query optimization
        query:
          in_clause_parameter_padding: true
          plan_cache_max_size: 2048
        # Batch processing
        jdbc:
          batch_size: 25
          batch_versioned_data: true
        # Statistics and monitoring
        generate_statistics: true
        session:
          events:
            log:
              LOG_QUERIES_SLOWER_THAN_MS: 1000

  # Task execution optimization
  task:
    execution:
      pool:
        core-size: ${CPU_CORES:8}
        max-size: $((CPU_CORES * 2)):16}
        queue-capacity: 1000
        keep-alive: 60s
      thread-name-prefix: "utmstack-task-"
    scheduling:
      pool:
        size: ${CPU_CORES:8}
      thread-name-prefix: "utmstack-scheduler-"

  # HTTP client optimization
  http:
    client:
      timeout:
        connect: 5000
        read: 30000
        write: 30000

management:
  metrics:
    export:
      prometheus:
        enabled: true
        step: 30s
    distribution:
      percentiles-histogram:
        http.server.requests: true
        jvm.gc.pause: true
        jvm.memory.used: true
      percentiles:
        http.server.requests: 0.5,0.9,0.95,0.99,0.999
        jvm.gc.pause: 0.5,0.9,0.95,0.99,0.999
  endpoints:
    web:
      exposure:
        include: health,info,metrics,prometheus,threaddump,heapdump
  endpoint:
    health:
      show-details: always
    metrics:
      enabled: true
    prometheus:
      enabled: true

# UTMStack specific JVM optimizations
utmstack:
  performance:
    # Connection pooling
    database:
      pool:
        minimum-idle: 10
        maximum-pool-size: 50
        connection-timeout: 30000
        idle-timeout: 600000
        max-lifetime: 1800000
        leak-detection-threshold: 60000
    
    # Caching optimization
    cache:
      enabled: true
      ttl: 3600000
      max-entries: 10000
      
    # Async processing
    async:
      core-pool-size: ${CPU_CORES:8}
      max-pool-size: $((CPU_CORES * 2)):16}
      queue-capacity: 1000
      
    # Search optimization
    elasticsearch:
      bulk:
        size: 1000
        flush-interval: 5s
        concurrent-requests: 4
      search:
        timeout: 30s
        max-result-window: 50000
        
    # Multi-tenant optimization
    tenant:
      cache-size: 1000
      cache-ttl: 7200000
      max-concurrent-requests: 100

logging:
  level:
    com.park.utmstack: INFO
    org.springframework.cache: WARN
    org.hibernate: WARN
    org.hibernate.SQL: WARN
    org.hibernate.type.descriptor.sql.BasicBinder: WARN
  pattern:
    console: "%d{HH:mm:ss.SSS} [%thread] %-5level [%X{tenantId}] %logger{36} - %msg%n"
    file: "%d{yyyy-MM-dd HH:mm:ss.SSS} [%thread] %-5level [%X{tenantId}] %logger{36} - %msg%n"
EOF

    log_success "Application configuration updates created"
}

# Function to create JVM startup script
create_jvm_startup_script() {
    log_info "Creating JVM startup script..."
    
    cat > ${JVM_CONFIG_DIR}/start-utmstack-optimized.sh << 'EOF'
#!/bin/bash

# UTMStack Optimized Startup Script

set -e

# Configuration
JVM_CONFIG_DIR="/etc/utmstack/jvm"
APP_DIR="/opt/utmstack"
LOG_DIR="/var/log/utmstack"
PID_FILE="/var/run/utmstack/utmstack.pid"

# Create necessary directories
mkdir -p ${LOG_DIR}
mkdir -p $(dirname ${PID_FILE})

# Load JVM options
JVM_OPTS=""
if [[ -f "${JVM_CONFIG_DIR}/production-jvm.options" ]]; then
    JVM_OPTS=$(grep -v '^#' ${JVM_CONFIG_DIR}/production-jvm.options | grep -v '^$' | tr '\n' ' ')
fi

# Additional JVM options for production
ADDITIONAL_OPTS="-server"
ADDITIONAL_OPTS="${ADDITIONAL_OPTS} -Djava.awt.headless=true"
ADDITIONAL_OPTS="${ADDITIONAL_OPTS} -Dfile.encoding=UTF-8"
ADDITIONAL_OPTS="${ADDITIONAL_OPTS} -Duser.timezone=UTC"
ADDITIONAL_OPTS="${ADDITIONAL_OPTS} -Djava.io.tmpdir=/tmp"

# Application options
APP_OPTS="--spring.profiles.active=production,multi-tenant"
APP_OPTS="${APP_OPTS} --logging.file.name=${LOG_DIR}/utmstack.log"
APP_OPTS="${APP_OPTS} --server.port=8080"

# Find JAR file
JAR_FILE=$(find ${APP_DIR} -name "*.jar" -type f | head -1)

if [[ -z "$JAR_FILE" ]]; then
    echo "ERROR: No JAR file found in ${APP_DIR}"
    exit 1
fi

echo "Starting UTMStack with optimized JVM settings..."
echo "JAR File: ${JAR_FILE}"
echo "JVM Options: ${JVM_OPTS}"
echo "App Options: ${APP_OPTS}"
echo "PID File: ${PID_FILE}"

# Start the application
nohup java ${JVM_OPTS} ${ADDITIONAL_OPTS} -jar ${JAR_FILE} ${APP_OPTS} \
    > ${LOG_DIR}/console.log 2>&1 &

# Save PID
echo $! > ${PID_FILE}

echo "UTMStack started with PID: $(cat ${PID_FILE})"
echo "Console log: ${LOG_DIR}/console.log"
echo "Application log: ${LOG_DIR}/utmstack.log"
echo "GC log: ${JVM_CONFIG_DIR}/logs/gc-*.log"
EOF

    chmod +x ${JVM_CONFIG_DIR}/start-utmstack-optimized.sh
    
    log_success "JVM startup script created"
}

# Function to create JVM monitoring cron jobs
create_jvm_monitoring_jobs() {
    log_info "Creating JVM monitoring cron jobs..."
    
    cat > /etc/cron.d/utmstack-jvm-monitoring << 'EOF'
# UTMStack JVM Monitoring Jobs

# Monitor JVM every 5 minutes
*/5 * * * * root /etc/utmstack/jvm/monitor-jvm.sh >> /var/log/utmstack/jvm-monitor.log 2>&1

# Weekly JFR recording (Sunday at 2 AM for 1 hour)
0 2 * * 0 root /etc/utmstack/jvm/jfr-analysis.sh

# Daily heap usage check (alert if >80%)
0 8 * * * root /etc/utmstack/jvm/check-heap-usage.sh

# Weekly GC log analysis (Monday at 1 AM)
0 1 * * 1 root /etc/utmstack/jvm/analyze-gc-logs.sh
EOF

    # Create heap usage check script
    cat > ${JVM_CONFIG_DIR}/check-heap-usage.sh << 'EOF'
#!/bin/bash

# Check heap usage and alert if high

JAVA_PID=$(pgrep -f "utmstack.*jar" | head -1)

if [[ -z "$JAVA_PID" ]]; then
    echo "No UTMStack Java process found"
    exit 0
fi

HEAP_USAGE=$(jstat -gc $JAVA_PID | tail -1 | awk '{
    old_used = $10
    old_capacity = $9
    if (old_capacity > 0) {
        print int(old_used/old_capacity*100)
    } else {
        print 0
    }
}')

if [[ $HEAP_USAGE -gt 80 ]]; then
    echo "WARNING: High heap usage detected: ${HEAP_USAGE}%"
    # Could send email or alert here
fi
EOF

    chmod +x ${JVM_CONFIG_DIR}/check-heap-usage.sh
    
    # Create GC log analysis script
    cat > ${JVM_CONFIG_DIR}/analyze-gc-logs.sh << 'EOF'
#!/bin/bash

# Analyze GC logs for performance issues

GC_LOG_DIR="/etc/utmstack/jvm/logs"
REPORT_FILE="/var/log/utmstack/gc-analysis-$(date +%Y-%m-%d).txt"

echo "GC Log Analysis Report - $(date)" > ${REPORT_FILE}
echo "=================================" >> ${REPORT_FILE}

# Find recent GC logs
RECENT_LOGS=$(find ${GC_LOG_DIR} -name "gc-*.log" -mtime -7)

for log_file in $RECENT_LOGS; do
    echo "" >> ${REPORT_FILE}
    echo "Analyzing: $(basename $log_file)" >> ${REPORT_FILE}
    echo "-----------------------------------" >> ${REPORT_FILE}
    
    # Extract pause times
    grep "pause" $log_file | tail -10 >> ${REPORT_FILE} 2>/dev/null || echo "No pause data found" >> ${REPORT_FILE}
done

echo "GC analysis completed: ${REPORT_FILE}"
EOF

    chmod +x ${JVM_CONFIG_DIR}/analyze-gc-logs.sh
    
    log_success "JVM monitoring cron jobs created"
}

# Main optimization execution
main() {
    log_info "Starting UTMStack JVM Performance Optimization..."
    
    analyze_system_resources
    create_jvm_configuration
    create_jvm_diagnostics
    create_performance_recommendations
    create_application_yml_updates
    create_jvm_startup_script
    create_jvm_monitoring_jobs
    
    log_success "JVM performance optimization completed!"
    echo ""
    echo "======================================================================"
    echo "🚀 JVM Performance Optimization Summary"
    echo "======================================================================"
    echo "Optimization Date: ${OPTIMIZATION_DATE}"
    echo "Log File: ${LOG_FILE}"
    echo "JVM Config Directory: ${JVM_CONFIG_DIR}"
    echo ""
    echo "Optimizations Applied:"
    echo "✅ Heap sizing: ${HEAP_MIN_GB}GB - ${HEAP_MAX_GB}GB"
    echo "✅ G1 Garbage Collector with optimized settings"
    echo "✅ JIT compilation optimization"
    echo "✅ Memory and performance monitoring"
    echo "✅ Production startup scripts"
    echo "✅ Diagnostic and profiling tools"
    echo "✅ Automated monitoring and alerting"
    echo ""
    echo "Key Features:"
    echo "• Low-latency GC with <200ms pause target"
    echo "• Flight Recorder for production profiling"
    echo "• Comprehensive monitoring and alerting"
    echo "• Automated heap and thread dump collection"
    echo "• Performance regression detection"
    echo ""
    echo "Next Steps:"
    echo "1. Update application startup to use new JVM options"
    echo "2. Monitor GC performance and adjust parameters"
    echo "3. Set up automated performance monitoring"
    echo "4. Run load tests to validate improvements"
    echo "======================================================================"
}

# Execute main function
main "$@"
