package com.park.utmstack.service.elasticsearch;

import com.park.utmstack.security.TenantContext;
import com.park.utmstack.service.TenantService;
import com.utmstack.opensearch_connector.OpenSearch;
import com.utmstack.opensearch_connector.enums.IndexSortableProperty;
import com.utmstack.opensearch_connector.enums.TermOrder;
import com.utmstack.opensearch_connector.exceptions.OpenSearchException;
import com.utmstack.opensearch_connector.types.ElasticCluster;
import org.opensearch.client.opensearch._types.SortOrder;
import org.opensearch.client.opensearch._types.query_dsl.Query;
import org.opensearch.client.opensearch.cat.indices.IndicesRecord;
import org.opensearch.client.opensearch.core.IndexResponse;
import org.opensearch.client.opensearch.core.SearchRequest;
import org.opensearch.client.opensearch.core.SearchResponse;
import org.opensearch.client.opensearch.indices.CreateIndexRequest;
import org.opensearch.client.opensearch.indices.ExistsRequest;
import org.opensearch.client.opensearch.indices.PutIndexTemplateRequest;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;

import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.*;
import java.util.stream.Collectors;

/**
 * Multi-tenant Elasticsearch service that provides tenant-isolated search operations.
 * All operations are automatically scoped to the current tenant context.
 */
@Service
public class MultiTenantElasticsearchService {

    private static final String CLASSNAME = "MultiTenantElasticsearchService";
    private final Logger log = LoggerFactory.getLogger(MultiTenantElasticsearchService.class);

    private final OpensearchClientBuilder clientBuilder;
    private final TenantService tenantService;

    // Index naming patterns for multi-tenant support
    private static final String TENANT_INDEX_PREFIX = "utmstack";
    private static final String LOG_INDEX_PATTERN = "logs";
    private static final String ALERT_INDEX_PATTERN = "alerts";
    private static final String METRIC_INDEX_PATTERN = "metrics";
    private static final String AUDIT_INDEX_PATTERN = "audit";

    public MultiTenantElasticsearchService(OpensearchClientBuilder clientBuilder, TenantService tenantService) {
        this.clientBuilder = clientBuilder;
        this.tenantService = tenantService;
    }

    /**
     * Get tenant-aware index name
     * Pattern: utmstack-{tenantId}-{indexType}-{date}
     */
    public String getTenantIndexName(String indexType, String tenantId) {
        if (!StringUtils.hasText(tenantId)) {
            throw new IllegalArgumentException("Tenant ID is required for index operations");
        }
        
        String dateString = DateTimeFormatter.ofPattern("yyyy-MM-dd").format(LocalDateTime.now());
        return String.format("%s-%s-%s-%s", TENANT_INDEX_PREFIX, tenantId, indexType, dateString);
    }

    /**
     * Get tenant-aware index pattern
     * Pattern: utmstack-{tenantId}-{indexType}-*
     */
    public String getTenantIndexPattern(String indexType, String tenantId) {
        if (!StringUtils.hasText(tenantId)) {
            throw new IllegalArgumentException("Tenant ID is required for index pattern operations");
        }
        
        return String.format("%s-%s-%s-*", TENANT_INDEX_PREFIX, tenantId, indexType);
    }

    /**
     * Get current tenant index pattern for the context
     */
    public String getCurrentTenantIndexPattern(String indexType) {
        String tenantId = TenantContext.getCurrentTenant();
        if (tenantId == null) {
            throw new IllegalStateException("No tenant context available for index operations");
        }
        return getTenantIndexPattern(indexType, tenantId);
    }

    /**
     * Search with automatic tenant scoping
     */
    public <T> SearchResponse<T> search(SearchRequest request, Class<T> clazz) throws OpenSearchException {
        return search(request, clazz, LOG_INDEX_PATTERN);
    }

    /**
     * Search with automatic tenant scoping for specific index type
     */
    public <T> SearchResponse<T> search(SearchRequest request, Class<T> clazz, String indexType) throws OpenSearchException {
        final String ctx = CLASSNAME + ".search";
        
        try {
            String tenantId = TenantContext.getCurrentTenant();
            if (tenantId == null) {
                throw new IllegalStateException("No tenant context available for search operations");
            }

            // Modify request to use tenant-scoped indices
            String tenantIndexPattern = getTenantIndexPattern(indexType, tenantId);
            SearchRequest tenantScopedRequest = enhanceSearchRequestForTenant(request, tenantIndexPattern, tenantId);

            log.debug("Executing tenant-scoped search: tenant={}, indexPattern={}", tenantId, tenantIndexPattern);
            
            return clientBuilder.getClient().getClient().search(tenantScopedRequest, clazz);
        } catch (Exception e) {
            log.error(ctx + ": Error executing tenant-scoped search", e);
            throw new OpenSearchException(ctx + ": " + e.getMessage(), e);
        }
    }

    /**
     * Index document with automatic tenant scoping
     */
    public IndexResponse indexDocument(String indexType, String documentId, Object document) throws OpenSearchException {
        final String ctx = CLASSNAME + ".indexDocument";
        
        try {
            String tenantId = TenantContext.getCurrentTenant();
            if (tenantId == null) {
                throw new IllegalStateException("No tenant context available for indexing operations");
            }

            String tenantIndexName = getTenantIndexName(indexType, tenantId);
            
            // Ensure index exists
            ensureTenantIndexExists(tenantIndexName, indexType, tenantId);
            
            // Add tenant metadata to document
            Map<String, Object> enhancedDocument = enhanceDocumentWithTenantData(document, tenantId);
            
            log.debug("Indexing document to tenant index: tenant={}, index={}, docId={}", 
                tenantId, tenantIndexName, documentId);
            
            return clientBuilder.getClient().getClient().index(tenantIndexName, documentId, enhancedDocument);
        } catch (Exception e) {
            log.error(ctx + ": Error indexing document to tenant index", e);
            throw new OpenSearchException(ctx + ": " + e.getMessage(), e);
        }
    }

    /**
     * Get field values with tenant scoping
     */
    public Map<String, Long> getFieldValues(String field, String indexType, Query query, Integer size, 
                                           TermOrder order, SortOrder sortOrder) throws OpenSearchException {
        final String ctx = CLASSNAME + ".getFieldValues";
        
        try {
            String tenantId = TenantContext.getCurrentTenant();
            if (tenantId == null) {
                throw new IllegalStateException("No tenant context available for field value operations");
            }

            String tenantIndexPattern = getTenantIndexPattern(indexType, tenantId);
            Query enhancedQuery = enhanceQueryWithTenantFilter(query, tenantId);
            
            log.debug("Getting field values for tenant: tenant={}, field={}, indexPattern={}", 
                tenantId, field, tenantIndexPattern);
            
            return clientBuilder.getClient().getFieldValues(field, tenantIndexPattern, enhancedQuery, 
                size != null ? size : 10000, order, sortOrder);
        } catch (Exception e) {
            log.error(ctx + ": Error getting field values for tenant", e);
            throw new OpenSearchException(ctx + ": " + e.getMessage(), e);
        }
    }

    /**
     * Get tenant-specific indices
     */
    public List<IndicesRecord> getTenantIndices(String tenantId) throws OpenSearchException {
        final String ctx = CLASSNAME + ".getTenantIndices";
        
        try {
            if (!StringUtils.hasText(tenantId)) {
                throw new IllegalArgumentException("Tenant ID is required");
            }

            List<IndicesRecord> allIndices = clientBuilder.getClient().getIndices();
            String tenantPrefix = TENANT_INDEX_PREFIX + "-" + tenantId + "-";
            
            return allIndices.stream()
                .filter(index -> index.index() != null && index.index().startsWith(tenantPrefix))
                .collect(Collectors.toList());
        } catch (Exception e) {
            log.error(ctx + ": Error getting tenant indices", e);
            throw new OpenSearchException(ctx + ": " + e.getMessage(), e);
        }
    }

    /**
     * Create tenant-specific index template
     */
    public void createTenantIndexTemplate(String tenantId, String indexType) throws OpenSearchException {
        final String ctx = CLASSNAME + ".createTenantIndexTemplate";
        
        try {
            String templateName = String.format("%s-%s-%s-template", TENANT_INDEX_PREFIX, tenantId, indexType);
            String indexPattern = getTenantIndexPattern(indexType, tenantId);
            
            Map<String, Object> templateSettings = createIndexTemplateSettings(indexType);
            Map<String, Object> templateMappings = createIndexTemplateMappings(indexType);
            
            PutIndexTemplateRequest templateRequest = PutIndexTemplateRequest.of(builder -> builder
                .name(templateName)
                .indexPatterns(indexPattern)
                .template(template -> template
                    .settings(s -> {
                        templateSettings.forEach((key, value) -> s.otherSettings(key, value));
                        return s;
                    })
                    .mappings(m -> {
                        templateMappings.forEach((key, value) -> {
                            // Add mappings configuration
                            if ("properties".equals(key) && value instanceof Map) {
                                @SuppressWarnings("unchecked")
                                Map<String, Object> properties = (Map<String, Object>) value;
                                properties.forEach((propKey, propValue) -> {
                                    // Configure property mappings
                                });
                            }
                        });
                        return m;
                    })
                )
            );
            
            clientBuilder.getClient().getClient().indices().putIndexTemplate(templateRequest);
            
            log.info("Created tenant index template: tenant={}, template={}, pattern={}", 
                tenantId, templateName, indexPattern);
                
        } catch (Exception e) {
            log.error(ctx + ": Error creating tenant index template", e);
            throw new OpenSearchException(ctx + ": " + e.getMessage(), e);
        }
    }

    /**
     * Ensure tenant index exists with proper configuration
     */
    private void ensureTenantIndexExists(String indexName, String indexType, String tenantId) throws OpenSearchException {
        try {
            ExistsRequest existsRequest = ExistsRequest.of(builder -> builder.index(indexName));
            boolean exists = clientBuilder.getClient().getClient().indices().exists(existsRequest).value();
            
            if (!exists) {
                createTenantIndex(indexName, indexType, tenantId);
            }
        } catch (Exception e) {
            log.error("Error checking/creating tenant index: {}", indexName, e);
            throw new OpenSearchException("Failed to ensure tenant index exists: " + e.getMessage(), e);
        }
    }

    /**
     * Create tenant-specific index
     */
    private void createTenantIndex(String indexName, String indexType, String tenantId) throws OpenSearchException {
        try {
            Map<String, Object> indexSettings = createIndexSettings(indexType);
            Map<String, Object> indexMappings = createIndexMappings(indexType);
            
            CreateIndexRequest createRequest = CreateIndexRequest.of(builder -> builder
                .index(indexName)
                .settings(s -> {
                    indexSettings.forEach((key, value) -> s.otherSettings(key, value));
                    return s;
                })
                .mappings(m -> {
                    // Configure mappings for tenant data
                    return m.properties("tenant_id", p -> p.keyword(k -> k))
                            .properties("@timestamp", p -> p.date(d -> d))
                            .properties("message", p -> p.text(t -> t))
                            .properties("level", p -> p.keyword(k -> k));
                })
            );
            
            clientBuilder.getClient().getClient().indices().create(createRequest);
            
            log.info("Created tenant index: tenant={}, index={}, type={}", tenantId, indexName, indexType);
            
        } catch (Exception e) {
            log.error("Error creating tenant index: {}", indexName, e);
            throw new OpenSearchException("Failed to create tenant index: " + e.getMessage(), e);
        }
    }

    /**
     * Enhance search request with tenant context
     */
    private SearchRequest enhanceSearchRequestForTenant(SearchRequest originalRequest, String tenantIndexPattern, String tenantId) {
        return SearchRequest.of(builder -> {
            // Copy original request properties
            builder.index(tenantIndexPattern);
            
            if (originalRequest.query() != null) {
                // Add tenant filter to existing query
                Query enhancedQuery = enhanceQueryWithTenantFilter(originalRequest.query(), tenantId);
                builder.query(enhancedQuery);
            } else {
                // Create tenant filter query
                builder.query(createTenantFilterQuery(tenantId));
            }
            
            // Copy other request properties
            if (originalRequest.size() != null) builder.size(originalRequest.size());
            if (originalRequest.from() != null) builder.from(originalRequest.from());
            if (originalRequest.sort() != null) builder.sort(originalRequest.sort());
            if (originalRequest.source() != null) builder.source(originalRequest.source());
            if (originalRequest.aggregations() != null) builder.aggregations(originalRequest.aggregations());
            
            return builder;
        });
    }

    /**
     * Enhance query with tenant filter
     */
    private Query enhanceQueryWithTenantFilter(Query originalQuery, String tenantId) {
        Query tenantFilter = createTenantFilterQuery(tenantId);
        
        return Query.of(q -> q.bool(b -> b
            .must(originalQuery)
            .filter(tenantFilter)
        ));
    }

    /**
     * Create tenant filter query
     */
    private Query createTenantFilterQuery(String tenantId) {
        return Query.of(q -> q.term(t -> t
            .field("tenant_id")
            .value(tenantId)
        ));
    }

    /**
     * Enhance document with tenant metadata
     */
    @SuppressWarnings("unchecked")
    private Map<String, Object> enhanceDocumentWithTenantData(Object document, String tenantId) {
        Map<String, Object> enhancedDoc;
        
        if (document instanceof Map) {
            enhancedDoc = new HashMap<>((Map<String, Object>) document);
        } else {
            // Convert object to map (simplified)
            enhancedDoc = new HashMap<>();
            enhancedDoc.put("data", document);
        }
        
        // Add tenant metadata
        enhancedDoc.put("tenant_id", tenantId);
        enhancedDoc.put("indexed_at", Instant.now().toString());
        
        return enhancedDoc;
    }

    /**
     * Create index settings based on type
     */
    private Map<String, Object> createIndexSettings(String indexType) {
        Map<String, Object> settings = new HashMap<>();
        settings.put("number_of_shards", 2);
        settings.put("number_of_replicas", 1);
        
        // Index-specific settings
        switch (indexType) {
            case LOG_INDEX_PATTERN:
                settings.put("refresh_interval", "5s");
                break;
            case ALERT_INDEX_PATTERN:
                settings.put("refresh_interval", "1s");
                break;
            case METRIC_INDEX_PATTERN:
                settings.put("refresh_interval", "30s");
                break;
            case AUDIT_INDEX_PATTERN:
                settings.put("refresh_interval", "1s");
                break;
        }
        
        return settings;
    }

    /**
     * Create index mappings based on type
     */
    private Map<String, Object> createIndexMappings(String indexType) {
        Map<String, Object> mappings = new HashMap<>();
        Map<String, Object> properties = new HashMap<>();
        
        // Common properties
        properties.put("tenant_id", Map.of("type", "keyword"));
        properties.put("@timestamp", Map.of("type", "date"));
        properties.put("indexed_at", Map.of("type", "date"));
        
        // Type-specific properties
        switch (indexType) {
            case LOG_INDEX_PATTERN:
                properties.put("message", Map.of("type", "text"));
                properties.put("level", Map.of("type", "keyword"));
                properties.put("source", Map.of("type", "keyword"));
                properties.put("host", Map.of("type", "keyword"));
                break;
            case ALERT_INDEX_PATTERN:
                properties.put("alert_name", Map.of("type", "keyword"));
                properties.put("severity", Map.of("type", "keyword"));
                properties.put("status", Map.of("type", "keyword"));
                properties.put("source_ip", Map.of("type", "ip"));
                properties.put("dest_ip", Map.of("type", "ip"));
                break;
            case METRIC_INDEX_PATTERN:
                properties.put("metric_name", Map.of("type", "keyword"));
                properties.put("value", Map.of("type", "double"));
                properties.put("unit", Map.of("type", "keyword"));
                break;
            case AUDIT_INDEX_PATTERN:
                properties.put("event_type", Map.of("type", "keyword"));
                properties.put("user_id", Map.of("type", "keyword"));
                properties.put("action", Map.of("type", "keyword"));
                properties.put("resource", Map.of("type", "keyword"));
                break;
        }
        
        mappings.put("properties", properties);
        return mappings;
    }

    /**
     * Create index template settings
     */
    private Map<String, Object> createIndexTemplateSettings(String indexType) {
        Map<String, Object> settings = createIndexSettings(indexType);
        
        // Add lifecycle policy
        settings.put("index.lifecycle.name", String.format("tenant-%s-policy", indexType));
        settings.put("index.lifecycle.rollover_alias", 
            String.format("%s-{tenant-id}-%s", TENANT_INDEX_PREFIX, indexType));
        
        return settings;
    }

    /**
     * Create index template mappings
     */
    private Map<String, Object> createIndexTemplateMappings(String indexType) {
        return createIndexMappings(indexType);
    }

    /**
     * Delete tenant data (for tenant cleanup)
     */
    public void deleteTenantData(String tenantId) throws OpenSearchException {
        final String ctx = CLASSNAME + ".deleteTenantData";
        
        try {
            if (!StringUtils.hasText(tenantId)) {
                throw new IllegalArgumentException("Tenant ID is required");
            }

            List<IndicesRecord> tenantIndices = getTenantIndices(tenantId);
            
            for (IndicesRecord index : tenantIndices) {
                try {
                    clientBuilder.getClient().getClient().indices().delete(d -> d.index(index.index()));
                    log.info("Deleted tenant index: tenant={}, index={}", tenantId, index.index());
                } catch (Exception e) {
                    log.error("Failed to delete tenant index: tenant={}, index={}", tenantId, index.index(), e);
                }
            }
            
            log.info("Completed tenant data deletion: tenant={}, indices_deleted={}", tenantId, tenantIndices.size());
            
        } catch (Exception e) {
            log.error(ctx + ": Error deleting tenant data", e);
            throw new OpenSearchException(ctx + ": " + e.getMessage(), e);
        }
    }

    /**
     * Create tenant index templates for all standard index types
     */
    public void createTenantIndexTemplates(UUID tenantId) throws OpenSearchException {
        String tenantIdStr = tenantId.toString();
        createTenantIndexTemplate(tenantIdStr, LOG_INDEX_PATTERN);
        createTenantIndexTemplate(tenantIdStr, ALERT_INDEX_PATTERN);
        createTenantIndexTemplate(tenantIdStr, METRIC_INDEX_PATTERN);
        createTenantIndexTemplate(tenantIdStr, AUDIT_INDEX_PATTERN);
        log.info("Created all index templates for tenant: {}", tenantId);
    }

    /**
     * Create a specific tenant index
     */
    public void createTenantIndex(UUID tenantId, String indexType) throws OpenSearchException {
        String tenantIdStr = tenantId.toString();
        String indexName = getTenantIndexName(indexType, tenantIdStr);
        createTenantIndex(indexName, indexType, tenantIdStr);
        log.info("Created tenant index: tenant={}, type={}, index={}", tenantId, indexType, indexName);
    }

    /**
     * Check if tenant index is healthy
     */
    public boolean isIndexHealthy(UUID tenantId) {
        try {
            String tenantIdStr = tenantId.toString();
            List<IndicesRecord> indices = getTenantIndices(tenantIdStr);
            
            if (indices.isEmpty()) {
                return false;
            }
            
            // Check if at least one index is healthy (green or yellow status)
            for (IndicesRecord index : indices) {
                String health = index.health();
                if ("green".equals(health) || "yellow".equals(health)) {
                    return true;
                }
            }
            
            return false;
        } catch (Exception e) {
            log.error("Error checking index health for tenant: {}", tenantId, e);
            return false;
        }
    }

    /**
     * Cleanup all tenant indices (for deprovisioning)
     */
    public void cleanupTenantIndices(UUID tenantId) throws OpenSearchException {
        deleteTenantData(tenantId.toString());
    }
}
