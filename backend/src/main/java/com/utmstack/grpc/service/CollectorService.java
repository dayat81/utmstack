package com.utmstack.grpc.service;

import com.utmstack.grpc.connection.GrpcConnection;
import agent.*;

@SuppressWarnings("unused")
public class CollectorService {
    public CollectorService(GrpcConnection c){}
    public agent.CollectorOuterClass.ListCollectorResponse
         listCollector(agent.Common.ListRequest r,String k){
        return agent.CollectorOuterClass.ListCollectorResponse.getDefault();
    }
    public agent.CollectorOuterClass.CollectorHostnames
         ListCollectorHostnames(agent.Common.ListRequest r,String k){
        return agent.CollectorOuterClass.CollectorHostnames.getDefault();
    }
    public agent.CollectorOuterClass.ListCollectorResponse
         GetCollectorsByHostnameAndModule(agent.CollectorOuterClass.FilterByHostAndModule r,String k){
        return agent.CollectorOuterClass.ListCollectorResponse.getDefault();
    }
    public agent.CollectorOuterClass.CollectorConfig
         requestCollectorConfig(agent.CollectorOuterClass.ConfigRequest r, agent.Common.AuthResponse a){
        return agent.CollectorOuterClass.CollectorConfig.getDefault();
    }
    public void deleteCollector(agent.CollectorOuterClass.CollectorDelete d, agent.Common.AuthResponse a){}
}
