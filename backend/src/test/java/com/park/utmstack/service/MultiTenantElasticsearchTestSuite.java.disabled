package com.park.utmstack.service;

import com.park.utmstack.domain.UtmTenant;
import com.park.utmstack.repository.UtmTenantRepository;
import com.park.utmstack.security.TenantContext;
import com.park.utmstack.service.elasticsearch.MultiTenantElasticsearchService;
import com.park.utmstack.service.elasticsearch.TenantIndexLifecycleService;
import com.park.utmstack.service.elasticsearch.SearchIsolationValidator;
import com.park.utmstack.service.TenantProvisioningService.TenantProvisioningRequest;
import org.elasticsearch.action.admin.indices.delete.DeleteIndexRequest;
import org.elasticsearch.action.delete.DeleteRequest;
import org.elasticsearch.action.index.IndexRequest;
import org.elasticsearch.action.search.SearchRequest;
import org.elasticsearch.action.search.SearchResponse;
import org.elasticsearch.client.RequestOptions;
import org.elasticsearch.client.RestHighLevelClient;
import org.elasticsearch.client.indices.CreateIndexRequest;
import org.elasticsearch.client.indices.GetIndexRequest;
import org.elasticsearch.common.xcontent.XContentType;
import org.elasticsearch.index.query.QueryBuilders;
import org.elasticsearch.search.SearchHit;
import org.elasticsearch.search.builder.SearchSourceBuilder;
import org.junit.jupiter.api.*;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.security.test.context.support.WithMockUser;
import org.springframework.test.context.ActiveProfiles;

import java.io.IOException;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.*;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.stream.IntStream;

import static org.assertj.core.api.Assertions.*;

/**
 * Comprehensive test suite for multi-tenant Elasticsearch operations.
 * Tests tenant-scoped indexes, data isolation, and search operations.
 */
@SpringBootTest
@ActiveProfiles("test")
@TestMethodOrder(MethodOrderer.OrderAnnotation.class)
public class MultiTenantElasticsearchTestSuite {

    private static final Logger log = LoggerFactory.getLogger(MultiTenantElasticsearchTestSuite.class);

    @Autowired private MultiTenantElasticsearchService elasticsearchService;
    @Autowired private TenantIndexLifecycleService indexLifecycleService;
    @Autowired private SearchIsolationValidator isolationValidator;
    @Autowired private TenantProvisioningService tenantProvisioningService;
    @Autowired private UtmTenantRepository tenantRepository;
    @Autowired private RestHighLevelClient elasticsearchClient;

    private final List<UUID> testTenantIds = new ArrayList<>();
    private final List<String> testIndexNames = new ArrayList<>();
    private final DateTimeFormatter dateFormatter = DateTimeFormatter.ofPattern("yyyy.MM.dd");

    @BeforeEach
    void setUp() {
        TenantContext.clear();
    }

    @AfterEach
    void tearDown() {
        cleanup();
        TenantContext.clear();
    }

    /**
     * Test 1: Tenant-scoped index creation
     */
    @Test
    @Order(1)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test tenant-scoped index creation")
    void testTenantScopedIndexCreation() throws Exception {
        log.info("Testing tenant-scoped index creation");

        UUID tenantId = createTestTenant("ES Test Tenant", "es-test");
        TenantContext.setCurrentTenant(tenantId);

        String today = LocalDate.now().format(dateFormatter);
        
        // Test creating different types of tenant indexes
        String alertsIndex = elasticsearchService.createTenantIndex("alerts", today);
        String logsIndex = elasticsearchService.createTenantIndex("logs", today);
        String incidentsIndex = elasticsearchService.createTenantIndex("incidents", today);

        testIndexNames.addAll(List.of(alertsIndex, logsIndex, incidentsIndex));

        // Verify index naming convention
        assertThat(alertsIndex).startsWith("utmstack-" + tenantId + "-alerts-");
        assertThat(logsIndex).startsWith("utmstack-" + tenantId + "-logs-");
        assertThat(incidentsIndex).startsWith("utmstack-" + tenantId + "-incidents-");

        // Verify indexes exist in Elasticsearch
        GetIndexRequest getRequest = new GetIndexRequest(alertsIndex);
        boolean alertsExists = elasticsearchClient.indices().exists(getRequest, RequestOptions.DEFAULT);
        assertThat(alertsExists).isTrue();

        getRequest = new GetIndexRequest(logsIndex);
        boolean logsExists = elasticsearchClient.indices().exists(getRequest, RequestOptions.DEFAULT);
        assertThat(logsExists).isTrue();

        // Verify tenant-specific mappings and settings
        Map<String, Object> indexSettings = elasticsearchService.getTenantIndexSettings(tenantId, "alerts");
        assertThat(indexSettings).isNotNull();
        assertThat(indexSettings.get("tenant_id")).isEqualTo(tenantId.toString());
    }

    /**
     * Test 2: Data isolation between tenants
     */
    @Test
    @Order(2)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test data isolation between tenants")
    void testDataIsolationBetweenTenants() throws Exception {
        log.info("Testing data isolation between tenants");

        UUID tenantA = createTestTenant("ES Tenant A", "es-tenant-a");
        UUID tenantB = createTestTenant("ES Tenant B", "es-tenant-b");

        String today = LocalDate.now().format(dateFormatter);

        // Create indexes for both tenants
        TenantContext.setCurrentTenant(tenantA);
        String indexA = elasticsearchService.createTenantIndex("test-data", today);
        testIndexNames.add(indexA);

        TenantContext.setCurrentTenant(tenantB);
        String indexB = elasticsearchService.createTenantIndex("test-data", today);
        testIndexNames.add(indexB);

        // Index data in tenant A
        TenantContext.setCurrentTenant(tenantA);
        Map<String, Object> docA1 = new HashMap<>();
        docA1.put("tenant", "A");
        docA1.put("message", "Data from tenant A - Doc 1");
        docA1.put("timestamp", System.currentTimeMillis());
        docA1.put("severity", "INFO");

        Map<String, Object> docA2 = new HashMap<>();
        docA2.put("tenant", "A");
        docA2.put("message", "Data from tenant A - Doc 2");
        docA2.put("timestamp", System.currentTimeMillis());
        docA2.put("severity", "WARN");

        elasticsearchService.indexDocument("test-data", "doc1", docA1);
        elasticsearchService.indexDocument("test-data", "doc2", docA2);

        // Index data in tenant B
        TenantContext.setCurrentTenant(tenantB);
        Map<String, Object> docB1 = new HashMap<>();
        docB1.put("tenant", "B");
        docB1.put("message", "Data from tenant B - Doc 1");
        docB1.put("timestamp", System.currentTimeMillis());
        docB1.put("severity", "ERROR");

        elasticsearchService.indexDocument("test-data", "doc1", docB1);

        // Refresh indexes
        elasticsearchService.refreshTenantIndexes(tenantA);
        elasticsearchService.refreshTenantIndexes(tenantB);

        // Verify tenant A can only see its data
        TenantContext.setCurrentTenant(tenantA);
        SearchResponse responseA = elasticsearchService.search("test-data", QueryBuilders.matchAllQuery());
        assertThat(responseA.getHits().getTotalHits().value).isEqualTo(2);
        
        for (SearchHit hit : responseA.getHits().getHits()) {
            Map<String, Object> source = hit.getSourceAsMap();
            assertThat(source.get("tenant")).isEqualTo("A");
        }

        // Verify tenant B can only see its data
        TenantContext.setCurrentTenant(tenantB);
        SearchResponse responseB = elasticsearchService.search("test-data", QueryBuilders.matchAllQuery());
        assertThat(responseB.getHits().getTotalHits().value).isEqualTo(1);
        
        SearchHit hitB = responseB.getHits().getHits()[0];
        assertThat(hitB.getSourceAsMap().get("tenant")).isEqualTo("B");

        // Verify cross-tenant access prevention
        TenantContext.setCurrentTenant(tenantA);
        SearchResponse crossTenantSearch = elasticsearchService.search("test-data", 
            QueryBuilders.termQuery("tenant", "B"));
        assertThat(crossTenantSearch.getHits().getTotalHits().value).isEqualTo(0);
    }

    /**
     * Test 3: Search isolation validation
     */
    @Test
    @Order(3)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test search isolation validation")
    void testSearchIsolationValidation() throws Exception {
        log.info("Testing search isolation validation");

        UUID tenantA = createTestTenant("Isolation Test A", "isolation-a");
        UUID tenantB = createTestTenant("Isolation Test B", "isolation-b");

        String today = LocalDate.now().format(dateFormatter);

        // Setup data for both tenants
        TenantContext.setCurrentTenant(tenantA);
        String indexA = elasticsearchService.createTenantIndex("isolation-test", today);
        testIndexNames.add(indexA);

        TenantContext.setCurrentTenant(tenantB);
        String indexB = elasticsearchService.createTenantIndex("isolation-test", today);
        testIndexNames.add(indexB);

        // Index test data
        TenantContext.setCurrentTenant(tenantA);
        for (int i = 0; i < 5; i++) {
            Map<String, Object> doc = new HashMap<>();
            doc.put("tenant_id", tenantA.toString());
            doc.put("data", "tenant-a-data-" + i);
            doc.put("secret", "tenant-a-secret-" + i);
            elasticsearchService.indexDocument("isolation-test", "a-doc-" + i, doc);
        }

        TenantContext.setCurrentTenant(tenantB);
        for (int i = 0; i < 3; i++) {
            Map<String, Object> doc = new HashMap<>();
            doc.put("tenant_id", tenantB.toString());
            doc.put("data", "tenant-b-data-" + i);
            doc.put("secret", "tenant-b-secret-" + i);
            elasticsearchService.indexDocument("isolation-test", "b-doc-" + i, doc);
        }

        elasticsearchService.refreshTenantIndexes(tenantA);
        elasticsearchService.refreshTenantIndexes(tenantB);

        // Run isolation validation
        TenantContext.setCurrentTenant(tenantA);
        Map<String, Object> isolationResultA = isolationValidator.validateTenantIsolation(
            tenantA, "isolation-test", 100);

        assertThat(isolationResultA.get("isolation_score")).isEqualTo(100.0);
        assertThat(isolationResultA.get("cross_tenant_leaks")).isEqualTo(0);
        assertThat(isolationResultA.get("total_documents")).isEqualTo(5);

        TenantContext.setCurrentTenant(tenantB);
        Map<String, Object> isolationResultB = isolationValidator.validateTenantIsolation(
            tenantB, "isolation-test", 100);

        assertThat(isolationResultB.get("isolation_score")).isEqualTo(100.0);
        assertThat(isolationResultB.get("cross_tenant_leaks")).isEqualTo(0);
        assertThat(isolationResultB.get("total_documents")).isEqualTo(3);

        // Test comprehensive isolation report
        Map<String, Object> comprehensiveReport = isolationValidator.generateIsolationReport(
            List.of(tenantA, tenantB), "isolation-test");

        assertThat(comprehensiveReport.get("total_tenants_tested")).isEqualTo(2);
        assertThat(comprehensiveReport.get("overall_isolation_score")).isEqualTo(100.0);
        assertThat(comprehensiveReport.get("security_violations")).isEqualTo(0);
    }

    /**
     * Test 4: Index lifecycle management
     */
    @Test
    @Order(4)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test index lifecycle management")
    void testIndexLifecycleManagement() throws Exception {
        log.info("Testing index lifecycle management");

        UUID tenantId = createTestTenant("Lifecycle Test", "lifecycle-test");
        TenantContext.setCurrentTenant(tenantId);

        // Test index rotation
        String alertsIndex = indexLifecycleService.createTenantIndex(tenantId, "alerts");
        String logsIndex = indexLifecycleService.createTenantIndex(tenantId, "logs");
        testIndexNames.addAll(List.of(alertsIndex, logsIndex));

        // Verify indexes created
        assertThat(indexLifecycleService.indexExists(alertsIndex)).isTrue();
        assertThat(indexLifecycleService.indexExists(logsIndex)).isTrue();

        // Test retention policy application
        Map<String, Object> retentionPolicies = new HashMap<>();
        retentionPolicies.put("alerts", "30d");
        retentionPolicies.put("logs", "90d");
        retentionPolicies.put("incidents", "1y");

        indexLifecycleService.applyRetentionPolicies(tenantId, retentionPolicies);

        // Verify policies applied
        Map<String, String> appliedPolicies = indexLifecycleService.getTenantRetentionPolicies(tenantId);
        assertThat(appliedPolicies.get("alerts")).isEqualTo("30d");
        assertThat(appliedPolicies.get("logs")).isEqualTo("90d");

        // Test index template management
        Map<String, Object> templateSettings = new HashMap<>();
        templateSettings.put("number_of_shards", 1);
        templateSettings.put("number_of_replicas", 0);
        templateSettings.put("refresh_interval", "1s");

        indexLifecycleService.createTenantIndexTemplate(tenantId, "test-template", 
            "utmstack-" + tenantId + "-*", templateSettings);

        // Verify template exists
        boolean templateExists = indexLifecycleService.templateExists("test-template-" + tenantId);
        assertThat(templateExists).isTrue();

        // Test automatic cleanup of old indexes
        List<String> oldIndexes = indexLifecycleService.identifyOldIndexes(tenantId, "alerts", 30);
        // Should be empty for new indexes
        assertThat(oldIndexes).isEmpty();
    }

    /**
     * Test 5: Concurrent Elasticsearch operations
     */
    @Test
    @Order(5)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test concurrent Elasticsearch operations")
    void testConcurrentElasticsearchOperations() throws Exception {
        log.info("Testing concurrent Elasticsearch operations");

        UUID tenantA = createTestTenant("Concurrent A", "concurrent-a");
        UUID tenantB = createTestTenant("Concurrent B", "concurrent-b");

        String today = LocalDate.now().format(dateFormatter);

        // Create indexes
        TenantContext.setCurrentTenant(tenantA);
        String indexA = elasticsearchService.createTenantIndex("concurrent-test", today);
        testIndexNames.add(indexA);

        TenantContext.setCurrentTenant(tenantB);
        String indexB = elasticsearchService.createTenantIndex("concurrent-test", today);
        testIndexNames.add(indexB);

        ExecutorService executor = Executors.newFixedThreadPool(10);
        List<CompletableFuture<Void>> futures = new ArrayList<>();

        // Create concurrent indexing operations
        IntStream.range(0, 20).forEach(i -> {
            UUID tenant = (i % 2 == 0) ? tenantA : tenantB;
            
            futures.add(CompletableFuture.runAsync(() -> {
                TenantContext.setCurrentTenant(tenant);
                try {
                    Map<String, Object> doc = new HashMap<>();
                    doc.put("tenant_id", tenant.toString());
                    doc.put("thread_data", "concurrent-" + i);
                    doc.put("timestamp", System.currentTimeMillis());
                    doc.put("thread", Thread.currentThread().getName());

                    elasticsearchService.indexDocument("concurrent-test", "doc-" + i, doc);
                } catch (Exception e) {
                    log.error("Concurrent indexing failed", e);
                    fail("Concurrent operation failed", e);
                } finally {
                    TenantContext.clear();
                }
            }, executor));
        });

        // Wait for all operations to complete
        CompletableFuture.allOf(futures.toArray(new CompletableFuture[0])).join();

        // Refresh indexes
        elasticsearchService.refreshTenantIndexes(tenantA);
        elasticsearchService.refreshTenantIndexes(tenantB);

        // Verify data isolation maintained during concurrent operations
        TenantContext.setCurrentTenant(tenantA);
        SearchResponse responseA = elasticsearchService.search("concurrent-test", QueryBuilders.matchAllQuery());
        assertThat(responseA.getHits().getTotalHits().value).isEqualTo(10);

        TenantContext.setCurrentTenant(tenantB);
        SearchResponse responseB = elasticsearchService.search("concurrent-test", QueryBuilders.matchAllQuery());
        assertThat(responseB.getHits().getTotalHits().value).isEqualTo(10);

        // Verify no cross-tenant contamination
        for (SearchHit hit : responseA.getHits().getHits()) {
            assertThat(hit.getSourceAsMap().get("tenant_id")).isEqualTo(tenantA.toString());
        }

        for (SearchHit hit : responseB.getHits().getHits()) {
            assertThat(hit.getSourceAsMap().get("tenant_id")).isEqualTo(tenantB.toString());
        }

        executor.shutdown();
    }

    /**
     * Test 6: Advanced search operations
     */
    @Test
    @Order(6)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test advanced search operations")
    void testAdvancedSearchOperations() throws Exception {
        log.info("Testing advanced search operations");

        UUID tenantId = createTestTenant("Search Test", "search-test");
        TenantContext.setCurrentTenant(tenantId);

        String today = LocalDate.now().format(dateFormatter);
        String index = elasticsearchService.createTenantIndex("search-test", today);
        testIndexNames.add(index);

        // Index sample data
        List<Map<String, Object>> testDocs = Arrays.asList(
            Map.of("title", "Alert: High CPU Usage", "severity", "HIGH", "category", "system", "count", 10),
            Map.of("title", "Alert: Network Anomaly", "severity", "MEDIUM", "category", "network", "count", 5),
            Map.of("title", "Alert: Failed Login", "severity", "HIGH", "category", "security", "count", 15),
            Map.of("title", "Info: System Update", "severity", "LOW", "category", "system", "count", 1),
            Map.of("title", "Warning: Disk Space", "severity", "MEDIUM", "category", "system", "count", 8)
        );

        for (int i = 0; i < testDocs.size(); i++) {
            elasticsearchService.indexDocument("search-test", "doc-" + i, testDocs.get(i));
        }

        elasticsearchService.refreshTenantIndexes(tenantId);

        // Test term query
        SearchResponse termResponse = elasticsearchService.search("search-test", 
            QueryBuilders.termQuery("severity", "HIGH"));
        assertThat(termResponse.getHits().getTotalHits().value).isEqualTo(2);

        // Test range query
        SearchResponse rangeResponse = elasticsearchService.search("search-test",
            QueryBuilders.rangeQuery("count").gte(5).lte(10));
        assertThat(rangeResponse.getHits().getTotalHits().value).isEqualTo(3);

        // Test boolean query
        SearchResponse boolResponse = elasticsearchService.search("search-test",
            QueryBuilders.boolQuery()
                .must(QueryBuilders.termQuery("category", "system"))
                .mustNot(QueryBuilders.termQuery("severity", "LOW")));
        assertThat(boolResponse.getHits().getTotalHits().value).isEqualTo(2);

        // Test aggregations
        Map<String, Object> aggResult = elasticsearchService.searchWithAggregations("search-test",
            QueryBuilders.matchAllQuery(),
            Map.of("severity_counts", "terms:severity", "avg_count", "avg:count"));

        assertThat(aggResult).containsKeys("hits", "aggregations");
        assertThat(aggResult.get("aggregations")).isInstanceOf(Map.class);

        // Test multi-index search (should only search tenant indexes)
        SearchResponse multiIndexResponse = elasticsearchService.searchMultipleIndexes(
            List.of("search-test"), QueryBuilders.matchAllQuery());
        assertThat(multiIndexResponse.getHits().getTotalHits().value).isEqualTo(5);
    }

    /**
     * Test 7: Performance and scaling
     */
    @Test
    @Order(7)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test performance and scaling")
    void testPerformanceAndScaling() throws Exception {
        log.info("Testing performance and scaling");

        UUID tenantId = createTestTenant("Performance Test", "performance-test");
        TenantContext.setCurrentTenant(tenantId);

        String today = LocalDate.now().format(dateFormatter);
        String index = elasticsearchService.createTenantIndex("performance-test", today);
        testIndexNames.add(index);

        // Bulk index performance test
        long startTime = System.currentTimeMillis();
        
        List<Map<String, Object>> bulkDocs = new ArrayList<>();
        for (int i = 0; i < 1000; i++) {
            Map<String, Object> doc = new HashMap<>();
            doc.put("id", i);
            doc.put("timestamp", System.currentTimeMillis());
            doc.put("message", "Performance test message " + i);
            doc.put("category", "category-" + (i % 10));
            doc.put("value", Math.random() * 100);
            bulkDocs.add(doc);
        }

        elasticsearchService.bulkIndex("performance-test", bulkDocs);
        elasticsearchService.refreshTenantIndexes(tenantId);

        long indexingTime = System.currentTimeMillis() - startTime;
        log.info("Bulk indexing of 1000 documents took {} ms", indexingTime);

        // Verify all documents indexed
        SearchResponse countResponse = elasticsearchService.search("performance-test", 
            QueryBuilders.matchAllQuery());
        assertThat(countResponse.getHits().getTotalHits().value).isEqualTo(1000);

        // Search performance test
        startTime = System.currentTimeMillis();
        
        for (int i = 0; i < 100; i++) {
            SearchResponse searchResponse = elasticsearchService.search("performance-test",
                QueryBuilders.termQuery("category", "category-" + (i % 10)));
            assertThat(searchResponse.getHits().getTotalHits().value).isGreaterThan(0);
        }

        long searchTime = System.currentTimeMillis() - startTime;
        log.info("100 search operations took {} ms", searchTime);

        // Verify performance is within acceptable limits
        assertThat(indexingTime).isLessThan(30000); // 30 seconds max for 1000 docs
        assertThat(searchTime).isLessThan(5000); // 5 seconds max for 100 searches
    }

    /**
     * Test 8: Error handling and edge cases
     */
    @Test
    @Order(8)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test error handling and edge cases")
    void testErrorHandlingAndEdgeCases() throws Exception {
        log.info("Testing error handling and edge cases");

        UUID tenantId = createTestTenant("Error Test", "error-test");
        TenantContext.setCurrentTenant(tenantId);

        // Test indexing to non-existent index type
        assertThatThrownBy(() -> {
            elasticsearchService.indexDocument("non-existent-type", "doc1", Map.of("test", "data"));
        }).isInstanceOf(Exception.class);

        // Test searching with malformed query
        assertThatThrownBy(() -> {
            elasticsearchService.search("test", QueryBuilders.queryStringQuery("invalid:query:syntax:"));
        }).isInstanceOf(Exception.class);

        // Test operations without tenant context
        TenantContext.clear();
        assertThatThrownBy(() -> {
            elasticsearchService.createTenantIndex("test", "2023.01.01");
        }).isInstanceOf(IllegalStateException.class);

        // Test large document indexing
        TenantContext.setCurrentTenant(tenantId);
        String today = LocalDate.now().format(dateFormatter);
        String index = elasticsearchService.createTenantIndex("large-doc-test", today);
        testIndexNames.add(index);

        Map<String, Object> largeDoc = new HashMap<>();
        largeDoc.put("large_field", "x".repeat(1000000)); // 1MB string
        largeDoc.put("timestamp", System.currentTimeMillis());

        // Should handle large documents gracefully
        assertThatCode(() -> {
            elasticsearchService.indexDocument("large-doc-test", "large-doc", largeDoc);
        }).doesNotThrowAnyException();

        // Test search with very large result set
        List<Map<String, Object>> manyDocs = new ArrayList<>();
        for (int i = 0; i < 10000; i++) {
            manyDocs.add(Map.of("id", i, "type", "test"));
        }

        elasticsearchService.bulkIndex("large-doc-test", manyDocs);
        elasticsearchService.refreshTenantIndexes(tenantId);

        // Test pagination for large result sets
        SearchResponse paginatedResponse = elasticsearchService.searchWithPagination(
            "large-doc-test", QueryBuilders.matchAllQuery(), 0, 100);
        
        assertThat(paginatedResponse.getHits().getHits()).hasSize(100);
        assertThat(paginatedResponse.getHits().getTotalHits().value).isGreaterThan(10000);
    }

    // Helper methods

    private UUID createTestTenant(String name, String subdomain) throws Exception {
        TenantProvisioningRequest request = new TenantProvisioningRequest();
        request.setName(name);
        request.setSubdomain(subdomain);
        request.setTier("standard");

        var result = tenantProvisioningService.provisionTenant(request).get();
        UUID tenantId = result.getTenantId();
        testTenantIds.add(tenantId);
        return tenantId;
    }

    private void cleanup() {
        try {
            TenantContext.clear();

            // Cleanup Elasticsearch indexes
            for (String indexName : testIndexNames) {
                try {
                    DeleteIndexRequest deleteRequest = new DeleteIndexRequest(indexName);
                    elasticsearchClient.indices().delete(deleteRequest, RequestOptions.DEFAULT);
                } catch (Exception e) {
                    log.warn("Failed to cleanup index: {}", indexName, e);
                }
            }
            testIndexNames.clear();

            // Cleanup tenants
            for (UUID tenantId : testTenantIds) {
                try {
                    tenantRepository.deleteById(tenantId);
                } catch (Exception e) {
                    log.warn("Failed to cleanup tenant: {}", tenantId, e);
                }
            }
            testTenantIds.clear();
        } catch (Exception e) {
            log.error("Error during cleanup", e);
        }
    }
}
