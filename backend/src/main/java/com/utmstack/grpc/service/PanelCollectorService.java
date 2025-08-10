package com.utmstack.grpc.service;

import com.utmstack.grpc.connection.GrpcConnection;
import agent.*;

public class PanelCollectorService{
    public PanelCollectorService(GrpcConnection c){}
    public agent.CollectorOuterClass.ConfigKnowledge
         insertCollectorConfig(agent.CollectorOuterClass.CollectorConfig c,String k){
        return agent.CollectorOuterClass.ConfigKnowledge.getDefault();
    }
}
