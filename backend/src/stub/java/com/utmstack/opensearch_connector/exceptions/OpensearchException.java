package com.utmstack.opensearch_connector.exceptions;

public class OpensearchException extends Exception {
    public OpensearchException() {}
    public OpensearchException(String message) { super(message); }
    public OpensearchException(String message, Throwable cause) { super(message, cause); }
}
