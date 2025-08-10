package com.utmstack.opensearch_connector.types;

import com.utmstack.opensearch_connector.enums.IndexSortableProperty;
import org.opensearch.client.opensearch._types.SortOrder;

public class IndexSort {
    public static IndexSort unSorted(){ return new IndexSort(); }
    public static Builder builder(){ return new Builder(); }
    public static class Builder{
        public Builder with(IndexSortableProperty p, SortOrder o){ return this; }
        public IndexSort build(){ return new IndexSort(); }
    }
}
