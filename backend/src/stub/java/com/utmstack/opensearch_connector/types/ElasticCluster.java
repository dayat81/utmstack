package com.utmstack.opensearch_connector.types;

public class ElasticCluster {
private String name;
private String url;

public ElasticCluster() {}

public ElasticCluster(String name, String url) {
this.name = name;
this.url = url;
}

public String getName() { return name; }
public void setName(String name) { this.name = name; }
public String getUrl() { return url; }
public void setUrl(String url) { this.url = url; }
    
    public String getResume() { return "Cluster running"; }
    public String getDiskUsedPercent() { return "50%"; }
}
