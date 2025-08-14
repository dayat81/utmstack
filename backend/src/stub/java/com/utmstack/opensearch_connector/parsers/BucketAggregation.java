package com.utmstack.opensearch_connector.parsers;

import java.util.Map;

public class BucketAggregation {
    private String key;
    private long docCount;
    private Map<String, Object> aggregations;
    
    public BucketAggregation() {}
    
    public String getKey() { return key; }
    public void setKey(String key) { this.key = key; }
    public long getDocCount() { return docCount; }
    public void setDocCount(long docCount) { this.docCount = docCount; }
    public Map<String, Object> getAggregations() { return aggregations; }
    public void setAggregations(Map<String, Object> aggregations) { this.aggregations = aggregations; }
}
