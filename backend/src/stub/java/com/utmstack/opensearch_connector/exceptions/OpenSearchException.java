package com.utmstack.opensearch_connector.exceptions;

public class OpenSearchException extends Exception {
    public OpenSearchException() {
        super();
    }
    
    public OpenSearchException(String message) {
        super(message);
    }
    
    public OpenSearchException(String message, Throwable cause) {
        super(message, cause);
    }
    
    public OpenSearchException(Throwable cause) {
        super(cause);
    }
}
