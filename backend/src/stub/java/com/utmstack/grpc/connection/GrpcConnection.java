package com.utmstack.grpc.connection;

import com.utmstack.grpc.exception.GrpcConnectionException;
import com.utmstack.grpc.jclient.config.interceptors.impl.GrpcEmptyAuthInterceptor;

public class GrpcConnection {
    public GrpcConnection() throws GrpcConnectionException { /* no real channel */ }
    
    public Object createChannel(String host, Integer port, GrpcEmptyAuthInterceptor interceptor) throws GrpcConnectionException {
        return new Object(); // Stub channel
    }
}
