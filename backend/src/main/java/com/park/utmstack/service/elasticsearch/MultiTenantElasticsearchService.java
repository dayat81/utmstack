package com.park.utmstack.service.elasticsearch;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.park.utmstack.security.TenantContext;
import org.elasticsearch.action.bulk.BulkRequest;
import org.elasticsearch.action.bulk.BulkResponse;
import org.elasticsearch.action.delete.DeleteRequest;
import org.elasticsearch.action.delete.DeleteResponse;
import org.elasticsearch.action.get.GetRequest;
import org.elasticsearch.action.get.GetResponse;
import org.elasticsearch.action.index.IndexRequest;
import org.elasticsearch.action.index.IndexResponse;
import org.elasticsearch.action.search.SearchRequest;
import org.elasticsearch.action.search.SearchResponse;
import org.elasticsearch.action.update.UpdateRequest;
import org.elasticsearch.action.update.UpdateResponse;
import org.elasticsearch.client.RequestOptions;
import org.elasticsearch.client.RestHighLevelClient;
import org.elasticsearch.client.indices.CreateIndexRequest;
import org.elasticsearch.client.indices.DeleteIndexRequest;
import org.elasticsearch.client.indices.GetIndexRequest;
import org.elasticsearch.common.xcontent.XContentType;
import org.elasticsearch.index.query.BoolQueryBuilder;
import org.elasticsearch.index.query.QueryBuilder;
import org.elasticsearch.index.query.QueryBuilders;
import org.elasticsearch.search.SearchHit;
import org.elasticsearch.search.builder.SearchSourceBuilder;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.io.IOException;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.*;

@Service
public class MultiTenantElasticsearchService {

    private static final Logger log = LoggerFactory.getLogger(MultiTenantElasticsearchService.class);

    @Autowired
    private RestHighLevelClient elasticsearchClient;

    @Autowired
    private ObjectMapper objectMapper;

    private static final String INDEX_PREFIX = "utmstack";
    private static final DateTimeFormatter DATE_FORMATTER = DateTimeFormatter.ofPattern("yyyy.MM.dd");

    public String generateTenantIndex(String type) {
        UUID tenantId = TenantContext.getCurrentTenantId();
        if (tenantId == null) {
            throw new IllegalStateException("No tenant context available");
        }
        String date = LocalDate.now().format(DATE_FORMATTER);
        return String.format("%s-%s-%s-%s", INDEX_PREFIX, tenantId.toString(), type, date);
    }

    public String generateTenantIndex(String type, LocalDate date) {
        UUID tenantId = TenantContext.getCurrentTenantId();
        if (tenantId == null) {
            throw new IllegalStateException("No tenant context available");
        }
        String dateStr = date.format(DATE_FORMATTER);
        return String.format("%s-%s-%s-%s", INDEX_PREFIX, tenantId.toString(), type, dateStr);
    }

    public List<String> getTenantIndexPattern(String type) {
        UUID tenantId = TenantContext.getCurrentTenantId();
        if (tenantId == null) {
            throw new IllegalStateException("No tenant context available");
        }
        return List.of(String.format("%s-%s-%s-*", INDEX_PREFIX, tenantId.toString(), type));
    }

    public boolean createIndex(String indexName, Map<String, Object> settings, Map<String, Object> mappings) throws IOException {
        CreateIndexRequest request = new CreateIndexRequest(indexName);
        
        if (settings != null) {
            request.settings(settings);
        }
        
        if (mappings != null) {
            request.mapping(mappings);
        }
        
        try {
            elasticsearchClient.indices().create(request, RequestOptions.DEFAULT);
            log.info("Created index: {}", indexName);
            return true;
        } catch (Exception e) {
            log.error("Failed to create index: {}", indexName, e);
            return false;
        }
    }

    public boolean indexExists(String indexName) throws IOException {
        GetIndexRequest request = new GetIndexRequest(indexName);
        return elasticsearchClient.indices().exists(request, RequestOptions.DEFAULT);
    }

    public boolean deleteIndex(String indexName) throws IOException {
        try {
            DeleteIndexRequest request = new DeleteIndexRequest(indexName);
            elasticsearchClient.indices().delete(request, RequestOptions.DEFAULT);
            log.info("Deleted index: {}", indexName);
            return true;
        } catch (Exception e) {
            log.error("Failed to delete index: {}", indexName, e);
            return false;
        }
    }

    public IndexResponse indexDocument(String type, String id, Map<String, Object> document) throws IOException {
        String indexName = generateTenantIndex(type);
        
        // Add tenant ID to document for additional isolation
        document.put("tenant_id", TenantContext.getCurrentTenantId().toString());
        
        IndexRequest request = new IndexRequest(indexName)
            .id(id)
            .source(document, XContentType.JSON);
        
        return elasticsearchClient.index(request, RequestOptions.DEFAULT);
    }

    public GetResponse getDocument(String type, String id) throws IOException {
        String indexName = generateTenantIndex(type);
        GetRequest request = new GetRequest(indexName, id);
        
        GetResponse response = elasticsearchClient.get(request, RequestOptions.DEFAULT);
        
        // Verify tenant isolation
        if (response.isExists()) {
            Map<String, Object> source = response.getSourceAsMap();
            String docTenantId = (String) source.get("tenant_id");
            UUID currentTenantId = TenantContext.getCurrentTenantId();
            
            if (!currentTenantId.toString().equals(docTenantId)) {
                log.warn("Tenant isolation violation detected: doc tenant {} != current tenant {}", 
                    docTenantId, currentTenantId);
                throw new SecurityException("Cross-tenant access violation");
            }
        }
        
        return response;
    }

    public UpdateResponse updateDocument(String type, String id, Map<String, Object> updates) throws IOException {
        String indexName = generateTenantIndex(type);
        
        // Add tenant ID to updates for additional isolation
        updates.put("tenant_id", TenantContext.getCurrentTenantId().toString());
        
        UpdateRequest request = new UpdateRequest(indexName, id)
            .doc(updates, XContentType.JSON);
        
        return elasticsearchClient.update(request, RequestOptions.DEFAULT);
    }

    public DeleteResponse deleteDocument(String type, String id) throws IOException {
        String indexName = generateTenantIndex(type);
        DeleteRequest request = new DeleteRequest(indexName, id);
        
        return elasticsearchClient.delete(request, RequestOptions.DEFAULT);
    }

    public SearchResponse search(String type, QueryBuilder query, int from, int size) throws IOException {
        List<String> indices = getTenantIndexPattern(type);
        
        // Add tenant isolation filter
        BoolQueryBuilder tenantQuery = QueryBuilders.boolQuery()
            .must(query)
            .filter(QueryBuilders.termQuery("tenant_id", TenantContext.getCurrentTenantId().toString()));
        
        SearchSourceBuilder sourceBuilder = new SearchSourceBuilder()
            .query(tenantQuery)
            .from(from)
            .size(size);
        
        SearchRequest request = new SearchRequest(indices.toArray(new String[0]))
            .source(sourceBuilder);
        
        return elasticsearchClient.search(request, RequestOptions.DEFAULT);
    }

    public SearchResponse search(String type, QueryBuilder query) throws IOException {
        return search(type, query, 0, 10);
    }

    public BulkResponse bulkIndex(String type, List<Map<String, Object>> documents) throws IOException {
        String indexName = generateTenantIndex(type);
        UUID tenantId = TenantContext.getCurrentTenantId();
        
        BulkRequest bulkRequest = new BulkRequest();
        
        for (Map<String, Object> document : documents) {
            // Add tenant ID for isolation
            document.put("tenant_id", tenantId.toString());
            
            String docId = (String) document.getOrDefault("id", UUID.randomUUID().toString());
            IndexRequest request = new IndexRequest(indexName)
                .id(docId)
                .source(document, XContentType.JSON);
            
            bulkRequest.add(request);
        }
        
        return elasticsearchClient.bulk(bulkRequest, RequestOptions.DEFAULT);
    }

    public List<Map<String, Object>> searchDocuments(String type, QueryBuilder query, int maxResults) throws IOException {
        SearchResponse response = search(type, query, 0, maxResults);
        List<Map<String, Object>> documents = new ArrayList<>();
        
        for (SearchHit hit : response.getHits()) {
            Map<String, Object> document = hit.getSourceAsMap();
            document.put("_id", hit.getId());
            document.put("_index", hit.getIndex());
            documents.add(document);
        }
        
        return documents;
    }

    public long countDocuments(String type, QueryBuilder query) throws IOException {
        List<String> indices = getTenantIndexPattern(type);
        
        // Add tenant isolation filter
        BoolQueryBuilder tenantQuery = QueryBuilders.boolQuery()
            .must(query)
            .filter(QueryBuilders.termQuery("tenant_id", TenantContext.getCurrentTenantId().toString()));
        
        SearchSourceBuilder sourceBuilder = new SearchSourceBuilder()
            .query(tenantQuery)
            .size(0);
        
        SearchRequest request = new SearchRequest(indices.toArray(new String[0]))
            .source(sourceBuilder);
        
        SearchResponse response = elasticsearchClient.search(request, RequestOptions.DEFAULT);
        return response.getHits().getTotalHits().value;
    }

    public boolean validateTenantIsolation(String type, String documentId) throws IOException {
        GetResponse response = getDocument(type, documentId);
        
        if (!response.isExists()) {
            return true; // Document doesn't exist, no isolation issue
        }
        
        Map<String, Object> source = response.getSourceAsMap();
        String docTenantId = (String) source.get("tenant_id");
        UUID currentTenantId = TenantContext.getCurrentTenantId();
        
        boolean isolated = currentTenantId.toString().equals(docTenantId);
        
        if (!isolated) {
            log.warn("Tenant isolation validation failed for document {} in type {}: doc tenant {} != current tenant {}", 
                documentId, type, docTenantId, currentTenantId);
        }
        
        return isolated;
    }

    public Map<String, Long> getTenantIndexStats(String type) throws IOException {
        List<String> indices = getTenantIndexPattern(type);
        Map<String, Long> stats = new HashMap<>();
        
        try {
            SearchResponse response = search(type, QueryBuilders.matchAllQuery(), 0, 0);
            stats.put("total_documents", response.getHits().getTotalHits().value);
            stats.put("tenant_id_count", 1L); // Current tenant only
            return stats;
        } catch (Exception e) {
            log.error("Failed to get tenant index stats for type: {}", type, e);
            stats.put("total_documents", 0L);
            stats.put("tenant_id_count", 0L);
            return stats;
        }
    }
}
