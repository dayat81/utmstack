#!/bin/bash

# UTMStack Elasticsearch Performance Optimization Script
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
LOG_FILE="/var/log/utmstack/es-optimization-${OPTIMIZATION_DATE}.log"
ES_CONFIG_DIR="/etc/utmstack/elasticsearch"
BACKUP_DIR="/var/backups/utmstack/es-optimization-${OPTIMIZATION_DATE}"

# Create directories
mkdir -p /var/log/utmstack
mkdir -p ${ES_CONFIG_DIR}
mkdir -p ${BACKUP_DIR}

# Redirect output
exec > >(tee -a ${LOG_FILE})
exec 2>&1

echo "======================================================================"
echo "🔍 UTMStack Elasticsearch Performance Optimization"
echo "======================================================================"
echo "Optimization Date: ${OPTIMIZATION_DATE}"
echo "Log File: ${LOG_FILE}"
echo "Config Directory: ${ES_CONFIG_DIR}"
echo "Backup Directory: ${BACKUP_DIR}"
echo "======================================================================"

# Function to analyze current Elasticsearch performance
analyze_elasticsearch_performance() {
    log_info "Analyzing current Elasticsearch performance..."
    
    # Check cluster health
    curl -s "localhost:9200/_cluster/health?pretty" > ${BACKUP_DIR}/cluster_health_before.json
    
    # Check node stats
    curl -s "localhost:9200/_nodes/stats?pretty" > ${BACKUP_DIR}/node_stats_before.json
    
    # Check index stats
    curl -s "localhost:9200/_stats?pretty" > ${BACKUP_DIR}/index_stats_before.json
    
    # Check slow queries
    curl -s "localhost:9200/_nodes/stats/indices/search?pretty" > ${BACKUP_DIR}/search_stats_before.json
    
    # Analyze index sizes and document counts
    curl -s "localhost:9200/_cat/indices?v&h=index,docs.count,store.size,pri.store.size&s=store.size:desc" > ${BACKUP_DIR}/index_sizes_before.txt
    
    log_success "Elasticsearch performance analysis completed"
}

# Function to optimize Elasticsearch cluster settings
optimize_cluster_settings() {
    log_info "Optimizing Elasticsearch cluster settings..."
    
    # Backup current settings
    curl -s "localhost:9200/_cluster/settings?pretty" > ${BACKUP_DIR}/cluster_settings_backup.json
    
    # Calculate optimal settings based on system resources
    local total_mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local total_mem_gb=$((total_mem_kb / 1024 / 1024))
    local heap_size_gb=$((total_mem_gb / 4))  # 25% of total memory for ES heap
    
    if [[ $heap_size_gb -lt 1 ]]; then
        heap_size_gb=1
    elif [[ $heap_size_gb -gt 32 ]]; then
        heap_size_gb=32  # ES recommendation: never exceed 32GB heap
    fi
    
    # Apply cluster-wide performance settings
    curl -X PUT "localhost:9200/_cluster/settings" -H 'Content-Type: application/json' -d"
    {
        \"persistent\": {
            \"cluster.routing.allocation.node_concurrent_recoveries\": 4,
            \"cluster.routing.allocation.cluster_concurrent_rebalance\": 2,
            \"cluster.routing.allocation.node_initial_primaries_recoveries\": 8,
            \"cluster.routing.allocation.same_shard.host\": false,
            \"indices.recovery.max_bytes_per_sec\": \"100mb\",
            \"indices.recovery.concurrent_streams\": 4,
            \"cluster.routing.allocation.disk.threshold_enabled\": true,
            \"cluster.routing.allocation.disk.watermark.low\": \"85%\",
            \"cluster.routing.allocation.disk.watermark.high\": \"90%\",
            \"cluster.routing.allocation.disk.watermark.flood_stage\": \"95%\",
            \"search.max_buckets\": 100000,
            \"action.search.shard_count.limit\": 10000
        }
    }"
    
    log_success "Cluster settings optimized"
}

# Function to create optimized index templates
create_optimized_index_templates() {
    log_info "Creating optimized index templates for multi-tenant performance..."
    
    # Multi-tenant logs template
    curl -X PUT "localhost:9200/_index_template/utmstack-multitenant-logs-optimized" -H 'Content-Type: application/json' -d'
    {
        "index_patterns": ["utmstack-*-logs-*"],
        "priority": 200,
        "template": {
            "settings": {
                "number_of_shards": 2,
                "number_of_replicas": 1,
                "index.refresh_interval": "30s",
                "index.merge.policy.max_merged_segment": "5gb",
                "index.merge.policy.segments_per_tier": 10,
                "index.codec": "best_compression",
                "index.query.default_field": ["message", "log_level", "source"],
                "index.max_result_window": 50000,
                "index.max_inner_result_window": 100,
                "index.max_rescore_window": 10000,
                "index.lifecycle.name": "tenant-log-policy-optimized",
                "index.lifecycle.rollover_alias": "utmstack-logs-active",
                "index.sort.field": ["@timestamp", "tenant_id"],
                "index.sort.order": ["desc", "asc"]
            },
            "mappings": {
                "properties": {
                    "@timestamp": {
                        "type": "date",
                        "format": "strict_date_optional_time||epoch_millis"
                    },
                    "tenant_id": {
                        "type": "keyword",
                        "index": true,
                        "doc_values": true
                    },
                    "log_level": {
                        "type": "keyword",
                        "index": true
                    },
                    "message": {
                        "type": "text",
                        "analyzer": "standard",
                        "search_analyzer": "standard",
                        "fields": {
                            "keyword": {
                                "type": "keyword",
                                "ignore_above": 256
                            }
                        }
                    },
                    "source_ip": {
                        "type": "ip"
                    },
                    "dest_ip": {
                        "type": "ip"
                    },
                    "event_type": {
                        "type": "keyword"
                    },
                    "severity": {
                        "type": "keyword"
                    },
                    "tags": {
                        "type": "keyword"
                    },
                    "host": {
                        "type": "keyword"
                    },
                    "source": {
                        "type": "keyword"
                    },
                    "raw_message": {
                        "type": "text",
                        "index": false,
                        "store": true
                    }
                }
            }
        }
    }'
    
    # Multi-tenant alerts template
    curl -X PUT "localhost:9200/_index_template/utmstack-multitenant-alerts-optimized" -H 'Content-Type: application/json' -d'
    {
        "index_patterns": ["utmstack-*-alerts-*"],
        "priority": 200,
        "template": {
            "settings": {
                "number_of_shards": 1,
                "number_of_replicas": 1,
                "index.refresh_interval": "5s",
                "index.codec": "best_compression",
                "index.lifecycle.name": "tenant-alert-policy-optimized",
                "index.sort.field": ["@timestamp", "tenant_id", "severity_order"],
                "index.sort.order": ["desc", "asc", "asc"]
            },
            "mappings": {
                "properties": {
                    "@timestamp": {
                        "type": "date"
                    },
                    "tenant_id": {
                        "type": "keyword"
                    },
                    "alert_id": {
                        "type": "keyword"
                    },
                    "severity": {
                        "type": "keyword"
                    },
                    "severity_order": {
                        "type": "integer"
                    },
                    "status": {
                        "type": "keyword"
                    },
                    "rule_name": {
                        "type": "keyword"
                    },
                    "description": {
                        "type": "text",
                        "fields": {
                            "keyword": {
                                "type": "keyword",
                                "ignore_above": 256
                            }
                        }
                    },
                    "source_data": {
                        "type": "object",
                        "enabled": false
                    },
                    "assigned_to": {
                        "type": "keyword"
                    },
                    "resolution_time": {
                        "type": "date"
                    }
                }
            }
        }
    }'
    
    log_success "Optimized index templates created"
}

# Function to create optimized ILM policies
create_optimized_ilm_policies() {
    log_info "Creating optimized Index Lifecycle Management policies..."
    
    # Optimized log retention policy
    curl -X PUT "localhost:9200/_ilm/policy/tenant-log-policy-optimized" -H 'Content-Type: application/json' -d'
    {
        "policy": {
            "phases": {
                "hot": {
                    "min_age": "0ms",
                    "actions": {
                        "rollover": {
                            "max_size": "10gb",
                            "max_age": "1d",
                            "max_docs": 10000000
                        },
                        "set_priority": {
                            "priority": 100
                        }
                    }
                },
                "warm": {
                    "min_age": "3d",
                    "actions": {
                        "set_priority": {
                            "priority": 50
                        },
                        "allocate": {
                            "number_of_replicas": 0
                        },
                        "forcemerge": {
                            "max_num_segments": 1
                        }
                    }
                },
                "cold": {
                    "min_age": "30d",
                    "actions": {
                        "set_priority": {
                            "priority": 0
                        },
                        "allocate": {
                            "number_of_replicas": 0
                        }
                    }
                },
                "delete": {
                    "min_age": "365d"
                }
            }
        }
    }'
    
    # Optimized alert retention policy
    curl -X PUT "localhost:9200/_ilm/policy/tenant-alert-policy-optimized" -H 'Content-Type: application/json' -d'
    {
        "policy": {
            "phases": {
                "hot": {
                    "min_age": "0ms",
                    "actions": {
                        "rollover": {
                            "max_size": "5gb",
                            "max_age": "7d",
                            "max_docs": 1000000
                        },
                        "set_priority": {
                            "priority": 100
                        }
                    }
                },
                "warm": {
                    "min_age": "7d",
                    "actions": {
                        "set_priority": {
                            "priority": 50
                        },
                        "forcemerge": {
                            "max_num_segments": 1
                        }
                    }
                },
                "cold": {
                    "min_age": "90d",
                    "actions": {
                        "set_priority": {
                            "priority": 0
                        },
                        "allocate": {
                            "number_of_replicas": 0
                        }
                    }
                },
                "delete": {
                    "min_age": "2555d"
                }
            }
        }
    }'
    
    log_success "Optimized ILM policies created"
}

# Function to optimize search and aggregation performance
optimize_search_performance() {
    log_info "Optimizing search and aggregation performance..."
    
    # Create search templates for common tenant queries
    curl -X PUT "localhost:9200/_scripts/tenant-logs-search" -H 'Content-Type: application/json' -d'
    {
        "script": {
            "lang": "mustache",
            "source": {
                "query": {
                    "bool": {
                        "must": [
                            {
                                "term": {
                                    "tenant_id": "{{tenant_id}}"
                                }
                            },
                            {
                                "range": {
                                    "@timestamp": {
                                        "gte": "{{start_time}}",
                                        "lte": "{{end_time}}"
                                    }
                                }
                            }
                        ],
                        "filter": [
                            {{#log_level}}
                            {
                                "term": {
                                    "log_level": "{{log_level}}"
                                }
                            }
                            {{/log_level}}
                        ]
                    }
                },
                "sort": [
                    {
                        "@timestamp": {
                            "order": "desc"
                        }
                    }
                ],
                "size": "{{size|20}}",
                "from": "{{from|0}}"
            }
        }
    }'
    
    # Create aggregation template for tenant statistics
    curl -X PUT "localhost:9200/_scripts/tenant-stats-agg" -H 'Content-Type: application/json' -d'
    {
        "script": {
            "lang": "mustache",
            "source": {
                "query": {
                    "bool": {
                        "must": [
                            {
                                "term": {
                                    "tenant_id": "{{tenant_id}}"
                                }
                            },
                            {
                                "range": {
                                    "@timestamp": {
                                        "gte": "{{start_time}}",
                                        "lte": "{{end_time}}"
                                    }
                                }
                            }
                        ]
                    }
                },
                "size": 0,
                "aggs": {
                    "log_levels": {
                        "terms": {
                            "field": "log_level",
                            "size": 10
                        }
                    },
                    "events_over_time": {
                        "date_histogram": {
                            "field": "@timestamp",
                            "calendar_interval": "{{interval|1h}}",
                            "time_zone": "UTC"
                        }
                    },
                    "top_sources": {
                        "terms": {
                            "field": "source",
                            "size": 20
                        }
                    }
                }
            }
        }
    }'
    
    # Optimize field data circuit breakers
    curl -X PUT "localhost:9200/_cluster/settings" -H 'Content-Type: application/json' -d'
    {
        "persistent": {
            "indices.breaker.fielddata.limit": "40%",
            "indices.breaker.request.limit": "60%",
            "indices.breaker.total.limit": "95%",
            "network.breaker.inflight_requests.limit": "100%"
        }
    }'
    
    log_success "Search performance optimizations applied"
}

# Function to create tenant-aware index aliases
create_tenant_aliases() {
    log_info "Creating tenant-aware index aliases..."
    
    # Create a script to generate tenant aliases
    cat > /tmp/create_tenant_aliases.sh << 'EOF'
#!/bin/bash

# Get list of tenants from the database
TENANTS=$(psql -h localhost -U utmstack_prod -d utmstack_production -t -c "SELECT subdomain FROM utm_tenant WHERE status = 'active';" | tr -d ' ' | grep -v '^$')

for tenant in $TENANTS; do
    echo "Creating aliases for tenant: $tenant"
    
    # Create logs alias
    curl -X PUT "localhost:9200/utmstack-${tenant}-logs-*/_alias/utmstack-${tenant}-logs-read" -H 'Content-Type: application/json' -d'
    {
        "filter": {
            "term": {
                "tenant_id": "'${tenant}'"
            }
        }
    }'
    
    # Create alerts alias
    curl -X PUT "localhost:9200/utmstack-${tenant}-alerts-*/_alias/utmstack-${tenant}-alerts-read" -H 'Content-Type: application/json' -d'
    {
        "filter": {
            "term": {
                "tenant_id": "'${tenant}'"
            }
        }
    }'
    
    echo "Aliases created for tenant: $tenant"
done
EOF
    
    chmod +x /tmp/create_tenant_aliases.sh
    /tmp/create_tenant_aliases.sh
    
    log_success "Tenant aliases created"
}

# Function to optimize index settings for existing indices
optimize_existing_indices() {
    log_info "Optimizing settings for existing indices..."
    
    # Get list of indices
    indices=$(curl -s "localhost:9200/_cat/indices?h=index" | grep -E "^(utmstack-|logstash-)")
    
    for index in $indices; do
        [[ -z "$index" ]] && continue
        
        log_info "Optimizing index: $index"
        
        # Update index settings
        curl -X PUT "localhost:9200/${index}/_settings" -H 'Content-Type: application/json' -d'
        {
            "index": {
                "refresh_interval": "30s",
                "merge.policy.max_merged_segment": "5gb",
                "codec": "best_compression",
                "max_result_window": 50000
            }
        }'
        
        # Force merge if index is small enough (< 5GB)
        index_size=$(curl -s "localhost:9200/_cat/indices/${index}?h=store.size" | sed 's/[a-zA-Z]//g')
        if [[ -n "$index_size" ]] && [[ $(echo "$index_size < 5" | bc -l 2>/dev/null) -eq 1 ]]; then
            curl -X POST "localhost:9200/${index}/_forcemerge?max_num_segments=1&wait_for_completion=false"
        fi
    done
    
    log_success "Existing indices optimized"
}

# Function to create monitoring and alerting for Elasticsearch
create_elasticsearch_monitoring() {
    log_info "Creating Elasticsearch monitoring and alerting..."
    
    # Create watcher for cluster health
    curl -X PUT "localhost:9200/_watcher/watch/cluster_health_watch" -H 'Content-Type: application/json' -d'
    {
        "trigger": {
            "schedule": {
                "interval": "1m"
            }
        },
        "input": {
            "http": {
                "request": {
                    "scheme": "http",
                    "host": "localhost",
                    "port": 9200,
                    "path": "/_cluster/health"
                }
            }
        },
        "condition": {
            "compare": {
                "ctx.payload.status": {
                    "not_eq": "green"
                }
            }
        },
        "actions": {
            "log_error": {
                "logging": {
                    "level": "error",
                    "text": "Elasticsearch cluster health is {{ctx.payload.status}}"
                }
            }
        }
    }'
    
    # Create performance monitoring index
    curl -X PUT "localhost:9200/elasticsearch-performance" -H 'Content-Type: application/json' -d'
    {
        "settings": {
            "number_of_shards": 1,
            "number_of_replicas": 0
        },
        "mappings": {
            "properties": {
                "@timestamp": {"type": "date"},
                "cluster_name": {"type": "keyword"},
                "node_name": {"type": "keyword"},
                "heap_used_percent": {"type": "float"},
                "jvm_gc_time": {"type": "long"},
                "search_query_time": {"type": "long"},
                "search_query_count": {"type": "long"},
                "indexing_time": {"type": "long"},
                "indexing_count": {"type": "long"}
            }
        }
    }'
    
    log_success "Elasticsearch monitoring created"
}

# Function to create maintenance procedures
create_maintenance_procedures() {
    log_info "Creating Elasticsearch maintenance procedures..."
    
    # Create maintenance script
    cat > ${ES_CONFIG_DIR}/es-maintenance.sh << 'EOF'
#!/bin/bash

# Elasticsearch Maintenance Script
MAINTENANCE_DATE=$(date +"%Y-%m-%d_%H-%M-%S")
LOG_FILE="/var/log/utmstack/es-maintenance-${MAINTENANCE_DATE}.log"

echo "Starting Elasticsearch maintenance at $(date)" >> ${LOG_FILE}

# 1. Force merge old indices (older than 7 days)
old_indices=$(curl -s "localhost:9200/_cat/indices?h=index,creation.date" | awk -v cutoff=$(($(date +%s) - 7*24*3600)) '$2 < cutoff {print $1}')

for index in $old_indices; do
    [[ -z "$index" ]] && continue
    echo "Force merging index: $index" >> ${LOG_FILE}
    curl -X POST "localhost:9200/${index}/_forcemerge?max_num_segments=1&wait_for_completion=false"
done

# 2. Clean up old snapshots (older than 30 days)
old_snapshots=$(curl -s "localhost:9200/_snapshot/backup_repository/_all" | jq -r '.snapshots[] | select(.end_time_in_millis < ('$(date +%s)'000 - 30*24*3600*1000)) | .snapshot')

for snapshot in $old_snapshots; do
    [[ -z "$snapshot" ]] && continue
    echo "Deleting old snapshot: $snapshot" >> ${LOG_FILE}
    curl -X DELETE "localhost:9200/_snapshot/backup_repository/${snapshot}"
done

# 3. Refresh tenant aliases
psql -h localhost -U utmstack_prod -d utmstack_production -t -c "SELECT subdomain FROM utm_tenant WHERE status = 'active';" | tr -d ' ' | grep -v '^$' | while read tenant; do
    echo "Refreshing aliases for tenant: $tenant" >> ${LOG_FILE}
    curl -s -X POST "localhost:9200/utmstack-${tenant}-*/_refresh" > /dev/null
done

echo "Elasticsearch maintenance completed at $(date)" >> ${LOG_FILE}
EOF

    chmod +x ${ES_CONFIG_DIR}/es-maintenance.sh
    
    # Create cron job
    cat > /etc/cron.d/elasticsearch-maintenance << 'EOF'
# Elasticsearch Maintenance
0 4 * * * root /etc/utmstack/elasticsearch/es-maintenance.sh
EOF

    log_success "Maintenance procedures created"
}

# Function to benchmark Elasticsearch performance
benchmark_elasticsearch_performance() {
    log_info "Benchmarking Elasticsearch performance..."
    
    # Run performance tests
    cat > /tmp/es_benchmark.sh << 'EOF'
#!/bin/bash

echo "Elasticsearch Performance Benchmark"
echo "=================================="

# Test 1: Simple search
start_time=$(date +%s%N)
curl -s "localhost:9200/utmstack-*/_search?size=10" > /dev/null
end_time=$(date +%s%N)
echo "Simple search: $((($end_time - $start_time) / 1000000)) ms"

# Test 2: Tenant-filtered search
start_time=$(date +%s%N)
curl -s -X POST "localhost:9200/utmstack-*/_search" -H 'Content-Type: application/json' -d'
{
    "query": {
        "bool": {
            "must": [
                {"term": {"tenant_id": "00000000-0000-0000-0000-000000000001"}},
                {"range": {"@timestamp": {"gte": "now-1h"}}}
            ]
        }
    },
    "size": 10
}' > /dev/null
end_time=$(date +%s%N)
echo "Tenant-filtered search: $((($end_time - $start_time) / 1000000)) ms"

# Test 3: Aggregation query
start_time=$(date +%s%N)
curl -s -X POST "localhost:9200/utmstack-*/_search" -H 'Content-Type: application/json' -d'
{
    "query": {
        "term": {"tenant_id": "00000000-0000-0000-0000-000000000001"}
    },
    "size": 0,
    "aggs": {
        "events_over_time": {
            "date_histogram": {
                "field": "@timestamp",
                "calendar_interval": "1h"
            }
        }
    }
}' > /dev/null
end_time=$(date +%s%N)
echo "Aggregation query: $((($end_time - $start_time) / 1000000)) ms"

echo "=================================="
EOF

    chmod +x /tmp/es_benchmark.sh
    /tmp/es_benchmark.sh > ${BACKUP_DIR}/es_benchmark_after.txt
    
    log_success "Elasticsearch performance benchmark completed"
}

# Main optimization execution
main() {
    log_info "Starting UTMStack Elasticsearch Performance Optimization..."
    
    analyze_elasticsearch_performance
    optimize_cluster_settings
    create_optimized_index_templates
    create_optimized_ilm_policies
    optimize_search_performance
    create_tenant_aliases
    optimize_existing_indices
    create_elasticsearch_monitoring
    create_maintenance_procedures
    benchmark_elasticsearch_performance
    
    log_success "Elasticsearch performance optimization completed!"
    echo ""
    echo "======================================================================"
    echo "🔍 Elasticsearch Performance Optimization Summary"
    echo "======================================================================"
    echo "Optimization Date: ${OPTIMIZATION_DATE}"
    echo "Log File: ${LOG_FILE}"
    echo "Config Directory: ${ES_CONFIG_DIR}"
    echo "Backup Directory: ${BACKUP_DIR}"
    echo ""
    echo "Optimizations Applied:"
    echo "✅ Cluster settings optimization"
    echo "✅ Multi-tenant index templates"
    echo "✅ Optimized ILM policies"
    echo "✅ Search and aggregation performance"
    echo "✅ Tenant-aware aliases"
    echo "✅ Existing indices optimization"
    echo "✅ Performance monitoring"
    echo "✅ Automated maintenance"
    echo ""
    echo "Next Steps:"
    echo "1. Monitor cluster health and performance"
    echo "2. Validate search response times"
    echo "3. Test with realistic tenant loads"
    echo "4. Schedule regular maintenance"
    echo "======================================================================"
}

# Execute main function
main "$@"
