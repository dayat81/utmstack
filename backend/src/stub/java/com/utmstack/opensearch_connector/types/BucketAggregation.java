package com.utmstack.opensearch_connector.types;

import java.util.*;

public class BucketAggregation {
    private String key="";
    private Long docCount=0L;
    private java.util.Map<String,org.opensearch.client.opensearch._types.aggregations.Aggregate> sub = java.util.Collections.emptyMap();
    public String getKey(){return key;}
    public void setKey(String k){key=k;}
    public Long getDocCount(){return docCount;}
    public java.util.Map<String,org.opensearch.client.opensearch._types.aggregations.Aggregate> getSubAggregations(){ return sub; }
}
