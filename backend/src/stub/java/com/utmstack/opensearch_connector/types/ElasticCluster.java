package com.utmstack.opensearch_connector.types;

public class ElasticCluster {
    private final Resume resume=new Resume();
    public Resume getResume(){ return resume; }
    public static class Resume{
        public float getDiskUsedPercent(){ return 0f; }
    }
}
