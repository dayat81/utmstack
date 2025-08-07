package com.utmstack.opensearch_connector.enums;

public enum IndexSortableProperty {
    CreationDate, DocsCount, StoreSize;
    public static IndexSortableProperty fromJsonValue(String v){
        try { return valueOf(v); } catch(Exception e){ return CreationDate; }
    }
}
