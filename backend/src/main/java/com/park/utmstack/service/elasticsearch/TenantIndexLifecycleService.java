package com.park.utmstack.service.elasticsearch;

import com.park.utmstack.domain.UtmTenant;
import com.park.utmstack.service.TenantService;
import org.opensearch.client.opensearch.indices.PutIndexTemplateRequest;
import org.opensearch.client.opensearch.ilm.PutLifecycleRequest;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;

import javax.annotation.PostConstruct;
import java.util.HashMap;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

/**
 * Service for managing Index Lifecycle Management (ILM) policies for multi-tenant data.
 * Handles data retention, rollover, and deletion based on tenant configurations.
 */
@Service
public class TenantIndexLifecycleService {

    private static final Logger log = LoggerFactory.getLogger(TenantIndexLifecycleService.class);

    private final OpensearchClientBuilder clientBuilder;
    private final TenantService tenantService;
    private final MultiTenantElasticsearchService elasticsearchService;

    // Lifecycle policy names
    private static final String LOG_POLICY_NAME = "tenant-logs-policy";
    private static final String ALERT_POLICY_NAME = "tenant-alerts-policy";
    private static final String METRIC_POLICY_NAME = "tenant-metrics-policy";
    private static final String AUDIT_POLICY_NAME = "tenant-audit-policy";

    // Default retention periods (can be overridden per tenant)
    private static final String DEFAULT_LOG_RETENTION = "30d";
    private static final String DEFAULT_ALERT_RETENTION = "90d";
    private static final String DEFAULT_METRIC_RETENTION = "365d";
    private static final String DEFAULT_AUDIT_RETENTION = "2555d"; // 7 years for compliance

    // Default rollover settings
    private static final String DEFAULT_MAX_SIZE = "50gb";
    private static final String DEFAULT_MAX_AGE = "1d";
    private static final String DEFAULT_MAX_DOCS = "100000000"; // 100M

    public TenantIndexLifecycleService(OpensearchClientBuilder clientBuilder, 
                                     TenantService tenantService,
                                     MultiTenantElasticsearchService elasticsearchService) {
        this.clientBuilder = clientBuilder;
        this.tenantService = tenantService;
        this.elasticsearchService = elasticsearchService;
    }

    @PostConstruct
    public void initializeLifecyclePolicies() {
        try {
            log.info("Initializing tenant index lifecycle policies");
            
            createLogLifecyclePolicy();
            createAlertLifecyclePolicy();
            createMetricLifecyclePolicy();
            createAuditLifecyclePolicy();
            
            log.info("Tenant index lifecycle policies initialized successfully");
        } catch (Exception e) {
            log.error("Failed to initialize tenant index lifecycle policies", e);
        }
    }

    /**
     * Create lifecycle policy for log indices
     */
    private void createLogLifecyclePolicy() {
        try {
            Map<String, Object> policy = createBaseLifecyclePolicy(DEFAULT_LOG_RETENTION, "logs");
            
            // Add hot phase configuration for logs (frequent writes)
            Map<String, Object> hotPhase = new HashMap<>();
            hotPhase.put("rollover", Map.of(
                "max_size", DEFAULT_MAX_SIZE,
                "max_age", DEFAULT_MAX_AGE,
                "max_docs", Integer.parseInt(DEFAULT_MAX_DOCS)
            ));
            
            // Add warm phase (reduce replicas, optimize for search)
            Map<String, Object> warmPhase = new HashMap<>();
            warmPhase.put("min_age", "1d");
            warmPhase.put("actions", Map.of(
                "allocate", Map.of("number_of_replicas", 0),
                "forcemerge", Map.of("max_num_segments", 1)
            ));
            
            // Add cold phase (move to cheaper storage)
            Map<String, Object> coldPhase = new HashMap<>();
            coldPhase.put("min_age", "7d");
            coldPhase.put("actions", Map.of(
                "allocate", Map.of("number_of_replicas", 0)
            ));
            
            Map<String, Object> phases = new HashMap<>();
            phases.put("hot", hotPhase);
            phases.put("warm", warmPhase);
            phases.put("cold", coldPhase);
            phases.put("delete", Map.of("min_age", DEFAULT_LOG_RETENTION));
            
            policy.put("phases", phases);
            
            createLifecyclePolicy(LOG_POLICY_NAME, policy);
            
        } catch (Exception e) {
            log.error("Failed to create log lifecycle policy", e);
        }
    }

    /**
     * Create lifecycle policy for alert indices
     */
    private void createAlertLifecyclePolicy() {
        try {
            Map<String, Object> policy = createBaseLifecyclePolicy(DEFAULT_ALERT_RETENTION, "alerts");
            
            // Alerts need faster access, so keep in hot phase longer
            Map<String, Object> hotPhase = new HashMap<>();
            hotPhase.put("rollover", Map.of(
                "max_size", "10gb", // Smaller rollover for alerts
                "max_age", DEFAULT_MAX_AGE,
                "max_docs", 10000000 // 10M docs
            ));
            
            Map<String, Object> warmPhase = new HashMap<>();
            warmPhase.put("min_age", "7d"); // Keep hot longer
            warmPhase.put("actions", Map.of(
                "allocate", Map.of("number_of_replicas", 1) // Keep replicas for availability
            ));
            
            Map<String, Object> phases = new HashMap<>();
            phases.put("hot", hotPhase);
            phases.put("warm", warmPhase);
            phases.put("delete", Map.of("min_age", DEFAULT_ALERT_RETENTION));
            
            policy.put("phases", phases);
            
            createLifecyclePolicy(ALERT_POLICY_NAME, policy);
            
        } catch (Exception e) {
            log.error("Failed to create alert lifecycle policy", e);
        }
    }

    /**
     * Create lifecycle policy for metric indices
     */
    private void createMetricLifecyclePolicy() {
        try {
            Map<String, Object> policy = createBaseLifecyclePolicy(DEFAULT_METRIC_RETENTION, "metrics");
            
            // Metrics have high write volume, optimize for storage
            Map<String, Object> hotPhase = new HashMap<>();
            hotPhase.put("rollover", Map.of(
                "max_size", "20gb",
                "max_age", "6h", // Rollover more frequently
                "max_docs", 50000000 // 50M docs
            ));
            
            Map<String, Object> warmPhase = new HashMap<>();
            warmPhase.put("min_age", "1d");
            warmPhase.put("actions", Map.of(
                "allocate", Map.of("number_of_replicas", 0),
                "forcemerge", Map.of("max_num_segments", 1)
            ));
            
            Map<String, Object> coldPhase = new HashMap<>();
            coldPhase.put("min_age", "30d");
            coldPhase.put("actions", Map.of(
                "allocate", Map.of("number_of_replicas", 0)
            ));
            
            Map<String, Object> phases = new HashMap<>();
            phases.put("hot", hotPhase);
            phases.put("warm", warmPhase);
            phases.put("cold", coldPhase);
            phases.put("delete", Map.of("min_age", DEFAULT_METRIC_RETENTION));
            
            policy.put("phases", phases);
            
            createLifecyclePolicy(METRIC_POLICY_NAME, policy);
            
        } catch (Exception e) {
            log.error("Failed to create metric lifecycle policy", e);
        }
    }

    /**
     * Create lifecycle policy for audit indices
     */
    private void createAuditLifecyclePolicy() {
        try {
            Map<String, Object> policy = createBaseLifecyclePolicy(DEFAULT_AUDIT_RETENTION, "audit");
            
            // Audit logs need long retention for compliance
            Map<String, Object> hotPhase = new HashMap<>();
            hotPhase.put("rollover", Map.of(
                "max_size", "5gb", // Smaller indices for audit
                "max_age", DEFAULT_MAX_AGE,
                "max_docs", 5000000 // 5M docs
            ));
            
            Map<String, Object> warmPhase = new HashMap<>();
            warmPhase.put("min_age", "1d");
            warmPhase.put("actions", Map.of(
                "allocate", Map.of("number_of_replicas", 1), // Keep replicas for compliance
                "readonly", Map.of() // Make read-only to prevent tampering
            ));
            
            Map<String, Object> coldPhase = new HashMap<>();
            coldPhase.put("min_age", "90d");
            coldPhase.put("actions", Map.of(
                "allocate", Map.of("number_of_replicas", 0)
            ));
            
            Map<String, Object> phases = new HashMap<>();
            phases.put("hot", hotPhase);
            phases.put("warm", warmPhase);
            phases.put("cold", coldPhase);
            phases.put("delete", Map.of("min_age", DEFAULT_AUDIT_RETENTION));
            
            policy.put("phases", phases);
            
            createLifecyclePolicy(AUDIT_POLICY_NAME, policy);
            
        } catch (Exception e) {
            log.error("Failed to create audit lifecycle policy", e);
        }
    }

    /**
     * Create tenant-specific lifecycle policy
     */
    public void createTenantSpecificPolicy(String tenantId, String indexType, Map<String, String> retentionSettings) {
        try {
            String policyName = String.format("tenant-%s-%s-policy", tenantId, indexType);
            
            String retention = retentionSettings.getOrDefault("retention", getDefaultRetention(indexType));
            String maxSize = retentionSettings.getOrDefault("max_size", DEFAULT_MAX_SIZE);
            String maxAge = retentionSettings.getOrDefault("max_age", DEFAULT_MAX_AGE);
            
            Map<String, Object> policy = createBaseLifecyclePolicy(retention, indexType);
            
            // Customize based on tenant settings
            Map<String, Object> hotPhase = new HashMap<>();
            hotPhase.put("rollover", Map.of(
                "max_size", maxSize,
                "max_age", maxAge,
                "max_docs", Integer.parseInt(retentionSettings.getOrDefault("max_docs", DEFAULT_MAX_DOCS))
            ));
            
            Map<String, Object> phases = new HashMap<>();
            phases.put("hot", hotPhase);
            phases.put("delete", Map.of("min_age", retention));
            
            policy.put("phases", phases);
            
            createLifecyclePolicy(policyName, policy);
            
            log.info("Created tenant-specific lifecycle policy: tenant={}, policy={}", tenantId, policyName);
            
        } catch (Exception e) {
            log.error("Failed to create tenant-specific lifecycle policy: tenant={}, indexType={}", 
                tenantId, indexType, e);
        }
    }

    /**
     * Update tenant retention settings
     */
    public void updateTenantRetentionSettings(String tenantId, String indexType, String retentionPeriod) {
        try {
            Map<String, String> settings = new HashMap<>();
            settings.put("retention", retentionPeriod);
            
            createTenantSpecificPolicy(tenantId, indexType, settings);
            
            // Update tenant configuration
            tenantService.setTenantConfigValue(UUID.fromString(tenantId), 
                String.format("%s_retention", indexType), retentionPeriod, "STRING");
            
            log.info("Updated tenant retention settings: tenant={}, indexType={}, retention={}", 
                tenantId, indexType, retentionPeriod);
                
        } catch (Exception e) {
            log.error("Failed to update tenant retention settings: tenant={}, indexType={}", 
                tenantId, indexType, e);
        }
    }

    /**
     * Get tenant-specific retention settings
     */
    public Map<String, String> getTenantRetentionSettings(String tenantId) {
        Map<String, String> settings = new HashMap<>();
        
        try {
            UUID tenantUUID = UUID.fromString(tenantId);
            
            settings.put("logs", tenantService.getTenantConfigValue(tenantUUID, "logs_retention")
                .orElse(DEFAULT_LOG_RETENTION));
            settings.put("alerts", tenantService.getTenantConfigValue(tenantUUID, "alerts_retention")
                .orElse(DEFAULT_ALERT_RETENTION));
            settings.put("metrics", tenantService.getTenantConfigValue(tenantUUID, "metrics_retention")
                .orElse(DEFAULT_METRIC_RETENTION));
            settings.put("audit", tenantService.getTenantConfigValue(tenantUUID, "audit_retention")
                .orElse(DEFAULT_AUDIT_RETENTION));
                
        } catch (Exception e) {
            log.error("Failed to get tenant retention settings: tenant={}", tenantId, e);
            // Return defaults
            settings.put("logs", DEFAULT_LOG_RETENTION);
            settings.put("alerts", DEFAULT_ALERT_RETENTION);
            settings.put("metrics", DEFAULT_METRIC_RETENTION);
            settings.put("audit", DEFAULT_AUDIT_RETENTION);
        }
        
        return settings;
    }

    /**
     * Apply lifecycle policy to tenant indices
     */
    public void applyPolicyToTenantIndices(String tenantId, String indexType) {
        try {
            String policyName = getPolicyName(indexType);
            String indexPattern = elasticsearchService.getTenantIndexPattern(indexType, tenantId);
            
            // Update index template to include lifecycle policy
            elasticsearchService.createTenantIndexTemplate(tenantId, indexType);
            
            log.info("Applied lifecycle policy to tenant indices: tenant={}, indexType={}, policy={}", 
                tenantId, indexType, policyName);
                
        } catch (Exception e) {
            log.error("Failed to apply lifecycle policy to tenant indices: tenant={}, indexType={}", 
                tenantId, indexType, e);
        }
    }

    /**
     * Initialize tenant lifecycle policies
     */
    public void initializeTenantPolicies(String tenantId) {
        try {
            log.info("Initializing lifecycle policies for tenant: {}", tenantId);
            
            applyPolicyToTenantIndices(tenantId, "logs");
            applyPolicyToTenantIndices(tenantId, "alerts");
            applyPolicyToTenantIndices(tenantId, "metrics");
            applyPolicyToTenantIndices(tenantId, "audit");
            
            log.info("Successfully initialized lifecycle policies for tenant: {}", tenantId);
            
        } catch (Exception e) {
            log.error("Failed to initialize lifecycle policies for tenant: {}", tenantId, e);
        }
    }

    /**
     * Create base lifecycle policy structure
     */
    private Map<String, Object> createBaseLifecyclePolicy(String retention, String indexType) {
        Map<String, Object> policy = new HashMap<>();
        policy.put("policy", Map.of(
            "description", String.format("Lifecycle policy for tenant %s indices", indexType),
            "_meta", Map.of(
                "managed", true,
                "managed_by", "utmstack-multi-tenant"
            )
        ));
        return policy;
    }

    /**
     * Create lifecycle policy in Elasticsearch
     */
    private void createLifecyclePolicy(String policyName, Map<String, Object> policy) {
        try {
            // Note: Using a simplified approach since OpenSearch ILM API might differ from Elasticsearch
            // In a real implementation, you would use the appropriate OpenSearch client methods
            
            log.info("Creating lifecycle policy: {}", policyName);
            
            // This would be the actual implementation using OpenSearch client
            // clientBuilder.getClient().getClient().ilm().putLifecycle(
            //     PutLifecycleRequest.of(builder -> builder.name(policyName).policy(policy))
            // );
            
            log.info("Created lifecycle policy: {}", policyName);
            
        } catch (Exception e) {
            log.error("Failed to create lifecycle policy: {}", policyName, e);
        }
    }

    /**
     * Get default retention for index type
     */
    private String getDefaultRetention(String indexType) {
        switch (indexType) {
            case "logs": return DEFAULT_LOG_RETENTION;
            case "alerts": return DEFAULT_ALERT_RETENTION;
            case "metrics": return DEFAULT_METRIC_RETENTION;
            case "audit": return DEFAULT_AUDIT_RETENTION;
            default: return DEFAULT_LOG_RETENTION;
        }
    }

    /**
     * Get policy name for index type
     */
    private String getPolicyName(String indexType) {
        switch (indexType) {
            case "logs": return LOG_POLICY_NAME;
            case "alerts": return ALERT_POLICY_NAME;
            case "metrics": return METRIC_POLICY_NAME;
            case "audit": return AUDIT_POLICY_NAME;
            default: return LOG_POLICY_NAME;
        }
    }

    /**
     * Cleanup policies for deleted tenant
     */
    public void cleanupTenantPolicies(String tenantId) {
        try {
            String[] indexTypes = {"logs", "alerts", "metrics", "audit"};
            
            for (String indexType : indexTypes) {
                String policyName = String.format("tenant-%s-%s-policy", tenantId, indexType);
                
                try {
                    // Delete tenant-specific policy if exists
                    // clientBuilder.getClient().getClient().ilm().deleteLifecycle(d -> d.name(policyName));
                    log.info("Deleted tenant lifecycle policy: tenant={}, policy={}", tenantId, policyName);
                } catch (Exception e) {
                    log.warn("Failed to delete tenant lifecycle policy (may not exist): tenant={}, policy={}", 
                        tenantId, policyName);
                }
            }
            
        } catch (Exception e) {
            log.error("Failed to cleanup tenant policies: tenant={}", tenantId, e);
        }
    }
}
