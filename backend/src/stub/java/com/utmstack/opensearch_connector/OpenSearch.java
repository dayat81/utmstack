package com.utmstack.opensearch_connector;

import com.utmstack.opensearch_connector.enums.TermOrder;
import com.utmstack.opensearch_connector.enums.HttpMethod;
import com.utmstack.opensearch_connector.enums.HttpScheme;
import com.utmstack.opensearch_connector.types.IndexSort;
import com.utmstack.opensearch_connector.types.ElasticCluster;
import org.opensearch.client.opensearch._types.SortOrder;
import org.opensearch.client.opensearch._types.query_dsl.Query;
import org.opensearch.client.opensearch.core.SearchRequest;
import java.util.*;

public class OpenSearch {
    private OpenSearch() {}
    public void close() {}

    /* ---------- builder ---------- */
    public static Builder builder() { return new Builder(); }
    public static final class Builder {
        private String host; 
        private int port; 
        private HttpScheme scheme;
        
        public Builder withHost(String host, int port, HttpScheme scheme) {
            this.host = host; 
            this.port = port; 
            this.scheme = scheme; 
            return this;
        }
        
        public OpenSearch build() { return new OpenSearch(); }
    }

    // getFieldValues methods - return Map for keySet() compatibility
    public Map<String, Long> getFieldValues(String idx, String field, Object q, int size,
                                      TermOrder ord, SortOrder so) { return new HashMap<>(); }
    
    public Map<String, Long> getFieldValues(String idx, String field, Query q, Integer size,
                                      Object orderBy, SortOrder so) { return new HashMap<>(); }
    
    public boolean indexExist(String idx) { return true; }
    
    public <T> org.opensearch.client.opensearch.core.IndexResponse index(String idx, T doc) { 
        return null; // Return null for IndexResponse compatibility
    }
    
    public Map<String, String> getIndexProperties(String idx) { return new HashMap<>(); }
    
    public List<org.opensearch.client.opensearch.cat.indices.IndicesRecord> getIndices(String p, IndexSort s) { 
        return new ArrayList<>(); 
    }
    
    public boolean deleteIndex(List<String> idx) { return true; }
    
    public <T> org.opensearch.client.opensearch.core.SearchResponse<T> search(SearchRequest r, Class<T> c) { 
        return null; // Return null for SearchResponse compatibility
    }
    
    public boolean updateByQuery(Query q, String script, String idx) { return true; }
    
    public java.util.Optional<ElasticCluster> getClusterNodesInfo() { 
        return java.util.Optional.of(new ElasticCluster()); 
    }
    
    public <T> T executeHttpRequest(String ep, Object params, Object body, HttpMethod m) { return null; }
    
    public <T> T executeHttpRequest(String ep, Map<String, String> params, Object body, HttpMethod m) { return null; }
}
