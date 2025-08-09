package com.park.utmstack.web.rest.elasticsearch;

import com.park.utmstack.security.TenantContext;
import com.park.utmstack.service.elasticsearch.MultiTenantElasticsearchService;
import com.park.utmstack.service.elasticsearch.SearchIsolationValidator;
import com.park.utmstack.service.elasticsearch.TenantIndexLifecycleService;
import org.opensearch.client.opensearch.core.SearchRequest;
import org.opensearch.client.opensearch.core.SearchResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

import javax.validation.Valid;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * REST controller for multi-tenant Elasticsearch operations.
 */
@RestController
@RequestMapping("/api/multi-tenant/elasticsearch")
public class MultiTenantElasticsearchResource {

    private static final Logger log = LoggerFactory.getLogger(MultiTenantElasticsearchResource.class);

    private final MultiTenantElasticsearchService elasticsearchService;
    private final SearchIsolationValidator isolationValidator;
    private final TenantIndexLifecycleService lifecycleService;

    public MultiTenantElasticsearchResource(MultiTenantElasticsearchService elasticsearchService,
                                          SearchIsolationValidator isolationValidator,
                                          TenantIndexLifecycleService lifecycleService) {
        this.elasticsearchService = elasticsearchService;
        this.isolationValidator = isolationValidator;
        this.lifecycleService = lifecycleService;
    }

    /**
     * Index document to tenant-scoped index
     */
    @PostMapping("/index/{indexType}")
    @PreAuthorize("hasPermission('DATA_CREATE')")
    public ResponseEntity<Map<String, Object>> indexDocument(
            @PathVariable String indexType,
            @RequestParam(required = false) String documentId,
            @Valid @RequestBody Map<String, Object> document) {
        
        try {
            String tenantId = TenantContext.getCurrentTenant();
            if (tenantId == null) {
                return ResponseEntity.badRequest()
                    .body(Map.of("error", "No tenant context available"));
            }

            String docId = documentId != null ? documentId : 
                "doc-" + System.currentTimeMillis() + "-" + Math.random();
            
            var indexResponse = elasticsearchService.indexDocument(indexType, docId, document);
            
            Map<String, Object> response = new HashMap<>();
            response.put("tenant_id", tenantId);
            response.put("index_type", indexType);
            response.put("document_id", indexResponse.id());
            response.put("result", indexResponse.result().jsonValue());
            response.put("index_name", elasticsearchService.getTenantIndexName(indexType, tenantId));
            
            return ResponseEntity.ok(response);
            
        } catch (Exception e) {
            log.error("Failed to index document", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(Map.of("error", "Failed to index document: " + e.getMessage()));
        }
    }

    /**
     * Search in tenant-scoped indices
     */
    @PostMapping("/search/{indexType}")
    @PreAuthorize("hasPermission('DATA_READ')")
    public ResponseEntity<Map<String, Object>> search(
            @PathVariable String indexType,
            @Valid @RequestBody Map<String, Object> searchQuery) {
        
        try {
            String tenantId = TenantContext.getCurrentTenant();
            if (tenantId == null) {
                return ResponseEntity.badRequest()
                    .body(Map.of("error", "No tenant context available"));
            }

            // Convert search query to SearchRequest
            // This is a simplified conversion - in practice, you'd need a more robust query builder
            SearchRequest searchRequest = SearchRequest.of(builder -> builder
                .size(searchQuery.containsKey("size") ? 
                    Integer.parseInt(searchQuery.get("size").toString()) : 20)
                .from(searchQuery.containsKey("from") ? 
                    Integer.parseInt(searchQuery.get("from").toString()) : 0)
            );
            
            @SuppressWarnings("rawtypes")
            SearchResponse searchResponse = elasticsearchService.search(searchRequest, Map.class, indexType);
            
            Map<String, Object> response = new HashMap<>();
            response.put("tenant_id", tenantId);
            response.put("index_type", indexType);
            response.put("index_pattern", elasticsearchService.getCurrentTenantIndexPattern(indexType));
            response.put("total_hits", searchResponse.hits().total().value());
            response.put("hits", searchResponse.hits().hits());
            response.put("took", searchResponse.took());
            
            return ResponseEntity.ok(response);
            
        } catch (Exception e) {
            log.error("Failed to execute search", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(Map.of("error", "Failed to execute search: " + e.getMessage()));
        }
    }

    /**
     * Get field values for tenant
     */
    @GetMapping("/field-values")
    @PreAuthorize("hasPermission('DATA_READ')")
    public ResponseEntity<Map<String, Object>> getFieldValues(
            @RequestParam String field,
            @RequestParam(defaultValue = "logs") String indexType,
            @RequestParam(defaultValue = "1000") Integer size) {
        
        try {
            String tenantId = TenantContext.getCurrentTenant();
            if (tenantId == null) {
                return ResponseEntity.badRequest()
                    .body(Map.of("error", "No tenant context available"));
            }

            Map<String, Long> fieldValues = elasticsearchService.getFieldValues(
                field, indexType, null, size,
                com.utmstack.opensearch_connector.enums.TermOrder.Count,
                org.opensearch.client.opensearch._types.SortOrder.Desc
            );
            
            Map<String, Object> response = new HashMap<>();
            response.put("tenant_id", tenantId);
            response.put("field", field);
            response.put("index_type", indexType);
            response.put("values", fieldValues);
            response.put("count", fieldValues.size());
            
            return ResponseEntity.ok(response);
            
        } catch (Exception e) {
            log.error("Failed to get field values", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(Map.of("error", "Failed to get field values: " + e.getMessage()));
        }
    }

    /**
     * Get tenant indices information
     */
    @GetMapping("/indices")
    @PreAuthorize("hasPermission('CONFIG_VIEW')")
    public ResponseEntity<Map<String, Object>> getTenantIndices() {
        try {
            String tenantId = TenantContext.getCurrentTenant();
            if (tenantId == null) {
                return ResponseEntity.badRequest()
                    .body(Map.of("error", "No tenant context available"));
            }

            var tenantIndices = elasticsearchService.getTenantIndices(tenantId);
            
            Map<String, Object> response = new HashMap<>();
            response.put("tenant_id", tenantId);
            response.put("indices", tenantIndices);
            response.put("count", tenantIndices.size());
            
            return ResponseEntity.ok(response);
            
        } catch (Exception e) {
            log.error("Failed to get tenant indices", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(Map.of("error", "Failed to get tenant indices: " + e.getMessage()));
        }
    }

    /**
     * Validate tenant search isolation
     */
    @PostMapping("/validate-isolation")
    @PreAuthorize("hasPermission('TENANT_ADMIN')")
    public ResponseEntity<Map<String, Object>> validateIsolation() {
        try {
            String tenantId = TenantContext.getCurrentTenant();
            if (tenantId == null) {
                return ResponseEntity.badRequest()
                    .body(Map.of("error", "No tenant context available"));
            }

            var validationResult = isolationValidator.validateTenantIsolation(tenantId);
            String report = isolationValidator.generateValidationReport(validationResult);
            
            Map<String, Object> response = new HashMap<>();
            response.put("tenant_id", tenantId);
            response.put("passed", validationResult.isPassed());
            response.put("violations", validationResult.getViolations());
            response.put("warnings", validationResult.getWarnings());
            response.put("metrics", validationResult.getMetrics());
            response.put("report", report);
            response.put("test_timestamp", validationResult.getTestTimestamp());
            
            return ResponseEntity.ok(response);
            
        } catch (Exception e) {
            log.error("Failed to validate isolation", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(Map.of("error", "Failed to validate isolation: " + e.getMessage()));
        }
    }

    /**
     * Batch validate multiple tenants (admin only)
     */
    @PostMapping("/validate-isolation/batch")
    @PreAuthorize("hasAuthority('ADMIN')")
    public ResponseEntity<Map<String, Object>> validateMultipleTenants(
            @RequestBody List<String> tenantIds) {
        try {
            var results = isolationValidator.validateMultipleTenants(tenantIds);
            
            Map<String, Object> response = new HashMap<>();
            response.put("tenant_count", tenantIds.size());
            response.put("results", results);
            response.put("summary", Map.of(
                "total", results.size(),
                "passed", results.values().stream().mapToLong(r -> r.isPassed() ? 1 : 0).sum(),
                "failed", results.values().stream().mapToLong(r -> r.isPassed() ? 0 : 1).sum()
            ));
            
            return ResponseEntity.ok(response);
            
        } catch (Exception e) {
            log.error("Failed to validate multiple tenants", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(Map.of("error", "Failed to validate multiple tenants: " + e.getMessage()));
        }
    }

    /**
     * Create index template for tenant
     */
    @PostMapping("/templates/{indexType}")
    @PreAuthorize("hasPermission('TENANT_ADMIN')")
    public ResponseEntity<Map<String, Object>> createIndexTemplate(
            @PathVariable String indexType) {
        try {
            String tenantId = TenantContext.getCurrentTenant();
            if (tenantId == null) {
                return ResponseEntity.badRequest()
                    .body(Map.of("error", "No tenant context available"));
            }

            elasticsearchService.createTenantIndexTemplate(tenantId, indexType);
            
            Map<String, Object> response = new HashMap<>();
            response.put("tenant_id", tenantId);
            response.put("index_type", indexType);
            response.put("template_name", String.format("utmstack-%s-%s-template", tenantId, indexType));
            response.put("status", "created");
            
            return ResponseEntity.ok(response);
            
        } catch (Exception e) {
            log.error("Failed to create index template", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(Map.of("error", "Failed to create index template: " + e.getMessage()));
        }
    }

    /**
     * Get tenant retention settings
     */
    @GetMapping("/lifecycle/retention")
    @PreAuthorize("hasPermission('CONFIG_VIEW')")
    public ResponseEntity<Map<String, Object>> getRetentionSettings() {
        try {
            String tenantId = TenantContext.getCurrentTenant();
            if (tenantId == null) {
                return ResponseEntity.badRequest()
                    .body(Map.of("error", "No tenant context available"));
            }

            Map<String, String> retentionSettings = lifecycleService.getTenantRetentionSettings(tenantId);
            
            Map<String, Object> response = new HashMap<>();
            response.put("tenant_id", tenantId);
            response.put("retention_settings", retentionSettings);
            
            return ResponseEntity.ok(response);
            
        } catch (Exception e) {
            log.error("Failed to get retention settings", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(Map.of("error", "Failed to get retention settings: " + e.getMessage()));
        }
    }

    /**
     * Update tenant retention settings
     */
    @PutMapping("/lifecycle/retention/{indexType}")
    @PreAuthorize("hasPermission('CONFIGURATION')")
    public ResponseEntity<Map<String, Object>> updateRetentionSettings(
            @PathVariable String indexType,
            @RequestParam String retentionPeriod) {
        try {
            String tenantId = TenantContext.getCurrentTenant();
            if (tenantId == null) {
                return ResponseEntity.badRequest()
                    .body(Map.of("error", "No tenant context available"));
            }

            lifecycleService.updateTenantRetentionSettings(tenantId, indexType, retentionPeriod);
            
            Map<String, Object> response = new HashMap<>();
            response.put("tenant_id", tenantId);
            response.put("index_type", indexType);
            response.put("retention_period", retentionPeriod);
            response.put("status", "updated");
            
            return ResponseEntity.ok(response);
            
        } catch (Exception e) {
            log.error("Failed to update retention settings", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(Map.of("error", "Failed to update retention settings: " + e.getMessage()));
        }
    }

    /**
     * Initialize lifecycle policies for tenant
     */
    @PostMapping("/lifecycle/initialize")
    @PreAuthorize("hasPermission('TENANT_ADMIN')")
    public ResponseEntity<Map<String, Object>> initializeLifecyclePolicies() {
        try {
            String tenantId = TenantContext.getCurrentTenant();
            if (tenantId == null) {
                return ResponseEntity.badRequest()
                    .body(Map.of("error", "No tenant context available"));
            }

            lifecycleService.initializeTenantPolicies(tenantId);
            
            Map<String, Object> response = new HashMap<>();
            response.put("tenant_id", tenantId);
            response.put("status", "initialized");
            response.put("message", "Lifecycle policies initialized for all index types");
            
            return ResponseEntity.ok(response);
            
        } catch (Exception e) {
            log.error("Failed to initialize lifecycle policies", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(Map.of("error", "Failed to initialize lifecycle policies: " + e.getMessage()));
        }
    }

    /**
     * Clean up test data
     */
    @DeleteMapping("/test-data")
    @PreAuthorize("hasPermission('TENANT_ADMIN')")
    public ResponseEntity<Map<String, Object>> cleanupTestData() {
        try {
            String tenantId = TenantContext.getCurrentTenant();
            if (tenantId == null) {
                return ResponseEntity.badRequest()
                    .body(Map.of("error", "No tenant context available"));
            }

            isolationValidator.cleanupTestData(tenantId);
            
            Map<String, Object> response = new HashMap<>();
            response.put("tenant_id", tenantId);
            response.put("status", "cleaned");
            response.put("message", "Test data removed");
            
            return ResponseEntity.ok(response);
            
        } catch (Exception e) {
            log.error("Failed to cleanup test data", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(Map.of("error", "Failed to cleanup test data: " + e.getMessage()));
        }
    }

    /**
     * Health check for multi-tenant Elasticsearch
     */
    @GetMapping("/health")
    public ResponseEntity<Map<String, Object>> healthCheck() {
        try {
            String tenantId = TenantContext.getCurrentTenant();
            
            Map<String, Object> health = new HashMap<>();
            health.put("status", "healthy");
            health.put("tenant_context", tenantId != null);
            health.put("timestamp", System.currentTimeMillis());
            
            if (tenantId != null) {
                // Check tenant-specific indices
                var tenantIndices = elasticsearchService.getTenantIndices(tenantId);
                health.put("tenant_id", tenantId);
                health.put("tenant_indices_count", tenantIndices.size());
            }
            
            return ResponseEntity.ok(health);
            
        } catch (Exception e) {
            log.error("Health check failed", e);
            return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                .body(Map.of("status", "unhealthy", "error", e.getMessage()));
        }
    }
}
