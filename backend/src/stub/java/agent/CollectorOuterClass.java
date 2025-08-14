package agent;

import java.util.*;

@SuppressWarnings("unused")
public final class CollectorOuterClass {

    private CollectorOuterClass(){}

    /* ---------------- enums ---------------- */
    public enum CollectorModule { 
        UNKNOWN, AS_400
        // name() method is inherited from Enum and works automatically
    }
    
    public enum CollectorStatus {
        ACTIVE, INACTIVE, UNKNOWN
        // name() method is inherited from Enum and works automatically
    }

    /* ---------------- "messages" ----------- */

    public static final class Collector {
        private String id = "1";
        private CollectorStatus status = CollectorStatus.ACTIVE;
        private String lastSeen = "2023-01-01T00:00:00Z";
        private String version = "1.0.0";
        private String ip = "127.0.0.1";
        private String hostname = "localhost";
        private String collectorKey = "test-key";
        private CollectorModule module = CollectorModule.UNKNOWN;
        
        public static Collector getDefaultInstance(){ return new Collector(); }
        public String getId() { return id; }
        public CollectorStatus getStatus() { return status; }
        public String getLastSeen() { return lastSeen; }
        public String getVersion() { return version; }
        public String getIp() { return ip; }
        public String getHostname() { return hostname; }
        public String getCollectorKey() { return collectorKey; }
        public CollectorModule getModule() { return module; }
    }

    public static final class CollectorDelete {
        private String deletedBy="";
        public static Builder newBuilder(){ return new Builder(); }
        public String getDeletedBy(){ return deletedBy; }
        public static final class Builder{
            private final CollectorDelete obj=new CollectorDelete();
            public Builder setDeletedBy(String v){ obj.deletedBy=v; return this; }
            public CollectorDelete build(){ return obj; }
        }
    }

    public static final class FilterByHostAndModule {
        private String hostname="";
        private CollectorModule module=CollectorModule.UNKNOWN;
        public static Builder newBuilder(){ return new Builder(); }
        public String getHostname(){ return hostname; }
        public CollectorModule getModule(){ return module; }
        public static final class Builder{
            private final FilterByHostAndModule obj=new FilterByHostAndModule();
            public Builder setHostname(String h){ obj.hostname=h; return this; }
            public Builder setModule(CollectorModule m){ obj.module=m; return this; }
            public FilterByHostAndModule build(){ return obj; }
        }
    }

    public static final class CollectorConfig {
        public static Builder newBuilder(){ return new Builder(); }
        public static CollectorConfig getDefault(){ return new CollectorConfig(); }
        public static final class Builder{
            private final CollectorConfig obj=new CollectorConfig();
            public Builder setCollectorKey(String k){ return this; }
            public Builder setRequestId(String id){ return this; }
            public Builder addAllGroups(java.util.Collection<?> c){ return this; }
            public CollectorConfig build(){ return obj; }
        }
    }

    public static final class CollectorConfigGroup {
        public static Builder newBuilder(){ return new Builder(); }
        public static final class Builder{
            public Builder setGroupName(String v){ return this; }
            public Builder setGroupDescription(String v){ return this; }
            public Builder addAllConfigurations(java.util.Collection<?> c){ return this; }
            public Builder setCollectorId(int i){ return this; }
            public CollectorConfigGroup build(){ return new CollectorConfigGroup(); }
        }
    }

    public static final class CollectorGroupConfigurations {
        public static Builder newBuilder(){ return new Builder(); }
        public static final class Builder{
            public Builder setConfKey(String v){ return this; }
            public Builder setConfName(String v){ return this; }
            public Builder setConfDescription(String v){ return this; }
            public Builder setConfDataType(String v){ return this; }
            public Builder setConfValue(String v){ return this; }
            public Builder setConfRequired(boolean b){ return this; }
            public CollectorGroupConfigurations build(){ return new CollectorGroupConfigurations(); }
        }
    }

    public static final class ConfigRequest {
        public static Builder newBuilder(){ return new Builder(); }
        public static final class Builder{
            public Builder setModule(CollectorModule module) { return this; }
            public ConfigRequest build(){ return new ConfigRequest(); }
        }
    }

    public static final class ConfigKnowledge {
        public static ConfigKnowledge getDefault(){ return new ConfigKnowledge(); }
    }

    public static final class ListCollectorResponse {
        private java.util.List<Collector> rows = java.util.Collections.emptyList();
        private int total=0;
        public java.util.List<Collector> getRowsList(){ return rows; }
        public int getTotal(){ return total; }
        public static ListCollectorResponse getDefault(){ return new ListCollectorResponse(); }
    }

    public static final class CollectorHostnames {
        public static CollectorHostnames getDefault(){ return new CollectorHostnames(); }
    }
}
