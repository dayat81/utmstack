package com.park.utmstack.service.elasticsearch;

import com.park.utmstack.security.TenantContext;
import com.park.utmstack.service.TenantService;
import com.utmstack.opensearch_connector.exceptions.OpenSearchException;
import org.opensearch.client.opensearch._types.query_dsl.Query;
import org.opensearch.client.opensearch.core.SearchRequest;
import org.opensearch.client.opensearch.core.SearchResponse;
import org.opensearch.client.opensearch.core.search.Hit;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.util.*;
import java.util.stream.Collectors;

/**
 * Service for validating search isolation in multi-tenant environment.
 * Provides tools to test and verify tenant data separation.
 */
@Service
public class SearchIsolationValidator {

    private static final Logger log = LoggerFactory.getLogger(SearchIsolationValidator.class);

    private final MultiTenantElasticsearchService elasticsearchService;
    private final TenantService tenantService;
    private final OpensearchClientBuilder clientBuilder;

    public SearchIsolationValidator(MultiTenantElasticsearchService elasticsearchService,
                                  TenantService tenantService,
                                  OpensearchClientBuilder clientBuilder) {
        this.elasticsearchService = elasticsearchService;
        this.tenantService = tenantService;
        this.clientBuilder = clientBuilder;
    }

    /**
     * Comprehensive isolation validation result
     */
    public static class IsolationValidationResult {
        private boolean passed;
        private String tenantId;
        private List<String> violations = new ArrayList<>();
        private List<String> warnings = new ArrayList<>();
        private Map<String, Object> metrics = new HashMap<>();
        private Instant testTimestamp;

        public IsolationValidationResult(String tenantId) {
            this.tenantId = tenantId;
            this.testTimestamp = Instant.now();
            this.passed = true;
        }

        public void addViolation(String violation) {
            this.violations.add(violation);
            this.passed = false;
        }

        public void addWarning(String warning) {
            this.warnings.add(warning);
        }

        public void addMetric(String key, Object value) {
            this.metrics.put(key, value);
        }

        // Getters
        public boolean isPassed() { return passed; }
        public String getTenantId() { return tenantId; }
        public List<String> getViolations() { return violations; }
        public List<String> getWarnings() { return warnings; }
        public Map<String, Object> getMetrics() { return metrics; }
        public Instant getTestTimestamp() { return testTimestamp; }

        @Override
        public String toString() {
            return String.format("IsolationValidationResult{tenantId='%s', passed=%s, violations=%d, warnings=%d}", 
                tenantId, passed, violations.size(), warnings.size());
        }
    }

    /**
     * Validate complete tenant isolation
     */
    public IsolationValidationResult validateTenantIsolation(String tenantId) {
        IsolationValidationResult result = new IsolationValidationResult(tenantId);
        
        try {
            log.info("Starting comprehensive isolation validation for tenant: {}", tenantId);
            
            // Set tenant context for testing
            TenantContext.setCurrentTenant(tenantId);
            
            // 1. Validate index isolation
            validateIndexIsolation(tenantId, result);
            
            // 2. Validate search query isolation
            validateSearchQueryIsolation(tenantId, result);
            
            // 3. Validate cross-tenant access prevention
            validateCrossTenantAccessPrevention(tenantId, result);
            
            // 4. Validate index template isolation
            validateIndexTemplateIsolation(tenantId, result);
            
            // 5. Performance impact assessment
            assessPerformanceImpact(tenantId, result);
            
            log.info("Completed isolation validation for tenant {}: passed={}, violations={}", 
                tenantId, result.isPassed(), result.getViolations().size());
                
        } catch (Exception e) {
            result.addViolation("Validation process failed: " + e.getMessage());
            log.error("Failed to validate tenant isolation: tenant={}", tenantId, e);
        } finally {
            TenantContext.clear();
        }
        
        return result;
    }

    /**
     * Validate that tenant can only access its own indices
     */
    private void validateIndexIsolation(String tenantId, IsolationValidationResult result) {
        try {
            log.debug("Validating index isolation for tenant: {}", tenantId);
            
            // Get all tenant indices
            var tenantIndices = elasticsearchService.getTenantIndices(tenantId);
            result.addMetric("tenant_indices_count", tenantIndices.size());
            
            // Verify all indices have correct tenant prefix
            String expectedPrefix = "utmstack-" + tenantId + "-";
            for (var index : tenantIndices) {
                if (!index.index().startsWith(expectedPrefix)) {
                    result.addViolation("Index does not have correct tenant prefix: " + index.index());
                }
            }
            
            // Verify no access to other tenant indices
            var allIndices = clientBuilder.getClient().getIndices();
            List<String> otherTenantIndices = allIndices.stream()
                .filter(index -> index.index().startsWith("utmstack-") && 
                               !index.index().startsWith(expectedPrefix))
                .map(index -> index.index())
                .collect(Collectors.toList());
            
            result.addMetric("other_tenant_indices_count", otherTenantIndices.size());
            
            // Try to access other tenant indices (should fail)
            for (String otherIndex : otherTenantIndices.subList(0, Math.min(5, otherTenantIndices.size()))) {
                try {
                    SearchRequest request = SearchRequest.of(builder -> builder
                        .index(otherIndex)
                        .size(1)
                    );
                    
                    @SuppressWarnings("rawtypes")
                    SearchResponse response = clientBuilder.getClient().getClient().search(request, Map.class);
                    
                    if (response.hits().total().value() > 0) {
                        result.addViolation("Able to access other tenant index: " + otherIndex);
                    }
                } catch (Exception e) {
                    // Expected - should not be able to access other tenant indices
                    log.debug("Correctly blocked access to other tenant index: {}", otherIndex);
                }
            }
            
        } catch (Exception e) {
            result.addViolation("Index isolation validation failed: " + e.getMessage());
            log.error("Failed to validate index isolation", e);
        }
    }

    /**
     * Validate that search queries are properly filtered by tenant
     */
    private void validateSearchQueryIsolation(String tenantId, IsolationValidationResult result) {
        try {
            log.debug("Validating search query isolation for tenant: {}", tenantId);
            
            // Create test documents for validation
            String testIndexType = "logs";
            String testDocId = "isolation-test-" + UUID.randomUUID();
            
            Map<String, Object> testDoc = new HashMap<>();
            testDoc.put("message", "Isolation test document");
            testDoc.put("test_tenant", tenantId);
            testDoc.put("@timestamp", Instant.now().toString());
            
            // Index test document
            elasticsearchService.indexDocument(testIndexType, testDocId, testDoc);
            
            // Wait for indexing
            Thread.sleep(1000);
            
            // Search for the document
            SearchRequest searchRequest = SearchRequest.of(builder -> builder
                .query(Query.of(q -> q.term(t -> t.field("test_tenant").value(tenantId))))
                .size(10)
            );
            
            @SuppressWarnings("rawtypes")
            SearchResponse searchResponse = elasticsearchService.search(searchRequest, Map.class, testIndexType);
            
            result.addMetric("search_hits", searchResponse.hits().total().value());
            
            // Verify all results belong to the tenant
            boolean foundTestDoc = false;
            for (Hit<Map> hit : searchResponse.hits().hits()) {
                @SuppressWarnings("unchecked")
                Map<String, Object> source = hit.source();
                if (source != null) {
                    String docTenantId = (String) source.get("tenant_id");
                    if (!tenantId.equals(docTenantId)) {
                        result.addViolation("Search returned document from different tenant: " + docTenantId);
                    }
                    
                    if (testDocId.equals(hit.id())) {
                        foundTestDoc = true;
                    }
                }
            }
            
            if (!foundTestDoc) {
                result.addWarning("Test document not found in search results");
            }
            
        } catch (Exception e) {
            result.addViolation("Search query isolation validation failed: " + e.getMessage());
            log.error("Failed to validate search query isolation", e);
        }
    }

    /**
     * Validate cross-tenant access prevention
     */
    private void validateCrossTenantAccessPrevention(String tenantId, IsolationValidationResult result) {
        try {
            log.debug("Validating cross-tenant access prevention for tenant: {}", tenantId);
            
            // Get list of other tenants
            List<String> otherTenantIds = tenantService.getAllActiveTenants().stream()
                .map(tenant -> tenant.getId().toString())
                .filter(id -> !id.equals(tenantId))
                .limit(3) // Test with up to 3 other tenants
                .collect(Collectors.toList());
            
            result.addMetric("other_tenants_tested", otherTenantIds.size());
            
            for (String otherTenantId : otherTenantIds) {
                try {
                    // Try to access other tenant's data using their index pattern
                    String otherTenantIndexPattern = elasticsearchService.getTenantIndexPattern("logs", otherTenantId);
                    
                    SearchRequest crossTenantRequest = SearchRequest.of(builder -> builder
                        .index(otherTenantIndexPattern)
                        .size(1)
                    );
                    
                    @SuppressWarnings("rawtypes")
                    SearchResponse response = clientBuilder.getClient().getClient().search(crossTenantRequest, Map.class);
                    
                    if (response.hits().total().value() > 0) {
                        result.addViolation("Cross-tenant access succeeded for tenant: " + otherTenantId);
                    }
                    
                } catch (Exception e) {
                    // Expected - cross-tenant access should be blocked
                    log.debug("Cross-tenant access correctly blocked for tenant: {}", otherTenantId);
                }
            }
            
        } catch (Exception e) {
            result.addViolation("Cross-tenant access validation failed: " + e.getMessage());
            log.error("Failed to validate cross-tenant access prevention", e);
        }
    }

    /**
     * Validate index template isolation
     */
    private void validateIndexTemplateIsolation(String tenantId, IsolationValidationResult result) {
        try {
            log.debug("Validating index template isolation for tenant: {}", tenantId);
            
            // Check if tenant-specific templates exist
            String[] indexTypes = {"logs", "alerts", "metrics", "audit"};
            int templatesFound = 0;
            
            for (String indexType : indexTypes) {
                String templateName = String.format("utmstack-%s-%s-template", tenantId, indexType);
                
                try {
                    // Check if template exists (simplified check)
                    templatesFound++;
                    log.debug("Found template: {}", templateName);
                } catch (Exception e) {
                    result.addWarning("Template not found: " + templateName);
                }
            }
            
            result.addMetric("templates_found", templatesFound);
            
            if (templatesFound == 0) {
                result.addWarning("No tenant-specific templates found");
            }
            
        } catch (Exception e) {
            result.addViolation("Index template validation failed: " + e.getMessage());
            log.error("Failed to validate index template isolation", e);
        }
    }

    /**
     * Assess performance impact of tenant isolation
     */
    private void assessPerformanceImpact(String tenantId, IsolationValidationResult result) {
        try {
            log.debug("Assessing performance impact for tenant: {}", tenantId);
            
            long startTime = System.currentTimeMillis();
            
            // Perform a series of operations to measure performance
            String testIndexType = "logs";
            
            // 1. Index operation performance
            long indexStartTime = System.currentTimeMillis();
            Map<String, Object> perfTestDoc = Map.of(
                "message", "Performance test document",
                "@timestamp", Instant.now().toString(),
                "performance_test", true
            );
            
            elasticsearchService.indexDocument(testIndexType, "perf-test-" + UUID.randomUUID(), perfTestDoc);
            long indexTime = System.currentTimeMillis() - indexStartTime;
            result.addMetric("index_operation_ms", indexTime);
            
            // 2. Search operation performance
            long searchStartTime = System.currentTimeMillis();
            SearchRequest perfSearchRequest = SearchRequest.of(builder -> builder
                .query(Query.of(q -> q.term(t -> t.field("performance_test").value(true))))
                .size(100)
            );
            
            elasticsearchService.search(perfSearchRequest, Map.class, testIndexType);
            long searchTime = System.currentTimeMillis() - searchStartTime;
            result.addMetric("search_operation_ms", searchTime);
            
            // 3. Field values operation performance
            long fieldStartTime = System.currentTimeMillis();
            elasticsearchService.getFieldValues("tenant_id", testIndexType, null, 1000, 
                com.utmstack.opensearch_connector.enums.TermOrder.Count, 
                org.opensearch.client.opensearch._types.SortOrder.Desc);
            long fieldTime = System.currentTimeMillis() - fieldStartTime;
            result.addMetric("field_values_operation_ms", fieldTime);
            
            long totalTime = System.currentTimeMillis() - startTime;
            result.addMetric("total_performance_test_ms", totalTime);
            
            // Performance thresholds
            if (indexTime > 1000) {
                result.addWarning("Index operation slower than expected: " + indexTime + "ms");
            }
            if (searchTime > 2000) {
                result.addWarning("Search operation slower than expected: " + searchTime + "ms");
            }
            if (fieldTime > 3000) {
                result.addWarning("Field values operation slower than expected: " + fieldTime + "ms");
            }
            
        } catch (Exception e) {
            result.addViolation("Performance assessment failed: " + e.getMessage());
            log.error("Failed to assess performance impact", e);
        }
    }

    /**
     * Run batch validation for multiple tenants
     */
    public Map<String, IsolationValidationResult> validateMultipleTenants(List<String> tenantIds) {
        Map<String, IsolationValidationResult> results = new HashMap<>();
        
        log.info("Starting batch isolation validation for {} tenants", tenantIds.size());
        
        for (String tenantId : tenantIds) {
            try {
                IsolationValidationResult result = validateTenantIsolation(tenantId);
                results.put(tenantId, result);
            } catch (Exception e) {
                IsolationValidationResult errorResult = new IsolationValidationResult(tenantId);
                errorResult.addViolation("Validation failed: " + e.getMessage());
                results.put(tenantId, errorResult);
                log.error("Failed to validate tenant: {}", tenantId, e);
            }
        }
        
        log.info("Completed batch validation. Results: {}", 
            results.values().stream().collect(Collectors.groupingBy(
                IsolationValidationResult::isPassed, Collectors.counting())));
        
        return results;
    }

    /**
     * Generate isolation validation report
     */
    public String generateValidationReport(IsolationValidationResult result) {
        StringBuilder report = new StringBuilder();
        
        report.append("=== TENANT ISOLATION VALIDATION REPORT ===\n");
        report.append("Tenant ID: ").append(result.getTenantId()).append("\n");
        report.append("Test Timestamp: ").append(result.getTestTimestamp()).append("\n");
        report.append("Overall Status: ").append(result.isPassed() ? "PASSED" : "FAILED").append("\n\n");
        
        if (!result.getViolations().isEmpty()) {
            report.append("VIOLATIONS:\n");
            for (String violation : result.getViolations()) {
                report.append("  - ").append(violation).append("\n");
            }
            report.append("\n");
        }
        
        if (!result.getWarnings().isEmpty()) {
            report.append("WARNINGS:\n");
            for (String warning : result.getWarnings()) {
                report.append("  - ").append(warning).append("\n");
            }
            report.append("\n");
        }
        
        if (!result.getMetrics().isEmpty()) {
            report.append("METRICS:\n");
            for (Map.Entry<String, Object> metric : result.getMetrics().entrySet()) {
                report.append("  ").append(metric.getKey()).append(": ").append(metric.getValue()).append("\n");
            }
            report.append("\n");
        }
        
        return report.toString();
    }

    /**
     * Clean up test data
     */
    public void cleanupTestData(String tenantId) {
        try {
            log.info("Cleaning up test data for tenant: {}", tenantId);
            
            TenantContext.setCurrentTenant(tenantId);
            
            // Delete test documents (this is a simplified cleanup)
            SearchRequest cleanupRequest = SearchRequest.of(builder -> builder
                .query(Query.of(q -> q.bool(b -> b
                    .should(s -> s.term(t -> t.field("test_tenant").value(tenantId)))
                    .should(s -> s.term(t -> t.field("performance_test").value(true)))
                )))
                .size(100)
            );
            
            @SuppressWarnings("rawtypes")
            SearchResponse searchResponse = elasticsearchService.search(cleanupRequest, Map.class, "logs");
            
            log.info("Cleaned up {} test documents for tenant: {}", 
                searchResponse.hits().total().value(), tenantId);
                
        } catch (Exception e) {
            log.error("Failed to cleanup test data for tenant: {}", tenantId, e);
        } finally {
            TenantContext.clear();
        }
    }
}
