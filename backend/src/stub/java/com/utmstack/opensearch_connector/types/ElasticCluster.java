package com.utmstack.opensearch_connector.types;

public class ElasticCluster {
private String name;
private String url;
private final ClusterResume resume = new ClusterResume();

public ElasticCluster() {}

public ElasticCluster(String name, String url) {
this.name = name;
this.url = url;
}

public String getName() { return name; }
public void setName(String name) { this.name = name; }
public String getUrl() { return url; }
public void setUrl(String url) { this.url = url; }
    
    public ClusterResume getResume() { return resume; }
    
    public static class ClusterResume {
        public Float getDiskUsedPercent() { return 50.0f; }
        public Float getDiskTotal() { return 1000.0f; }
        public Float getDiskUsed() { return 500.0f; }
        public Float getRamMax() { return 8192.0f; }
        public Float getRamCurrent() { return 4096.0f; }
        public Float getHeapMax() { return 2048.0f; }
        public Float getHeapCurrent() { return 1024.0f; }
    }
}
