package com.park.utmstack.security.audit;

import com.fasterxml.jackson.annotation.JsonFormat;

import java.time.Instant;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

/**
 * Security audit event for multi-tenant environment.
 */
public class SecurityAuditEvent {

    public enum EventType {
        // Authentication Events
        LOGIN_SUCCESS,
        LOGIN_FAILURE,
        LOGOUT,
        TOKEN_REFRESH,
        PASSWORD_CHANGE,
        ACCOUNT_LOCKED,
        ACCOUNT_UNLOCKED,

        // Authorization Events
        ACCESS_GRANTED,
        ACCESS_DENIED,
        PERMISSION_CHECK,
        ROLE_ASSIGNED,
        ROLE_REMOVED,

        // Tenant Operations
        TENANT_ACCESSED,
        TENANT_CREATED,
        TENANT_UPDATED,
        TENANT_DELETED,
        TENANT_STATUS_CHANGED,

        // Data Access Events
        DATA_READ,
        DATA_CREATED,
        DATA_UPDATED,
        DATA_DELETED,
        BULK_OPERATION,

        // Configuration Changes
        CONFIG_CHANGED,
        SYSTEM_SETTINGS_CHANGED,
        SECURITY_POLICY_CHANGED,

        // Suspicious Activities
        SUSPICIOUS_LOGIN_PATTERN,
        MULTIPLE_FAILED_LOGINS,
        CROSS_TENANT_ACCESS_ATTEMPT,
        UNUSUAL_DATA_ACCESS,
        PRIVILEGE_ESCALATION_ATTEMPT,

        // System Events
        SYSTEM_ERROR,
        SECURITY_VIOLATION,
        COMPLIANCE_VIOLATION
    }

    public enum Severity {
        LOW,
        MEDIUM,
        HIGH,
        CRITICAL
    }

    private String eventId;
    private EventType eventType;
    private Severity severity;
    
    @JsonFormat(pattern = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'")
    private Instant timestamp;
    
    private String tenantId;
    private String userId;
    private String userLogin;
    private String sessionId;
    private String ipAddress;
    private String userAgent;
    
    private String resource;
    private String action;
    private String outcome;
    private String description;
    
    private Map<String, Object> metadata;
    private Map<String, Object> beforeState;
    private Map<String, Object> afterState;
    
    private String requestId;
    private String correlationId;

    public SecurityAuditEvent() {
        this.eventId = UUID.randomUUID().toString();
        this.timestamp = Instant.now();
        this.metadata = new HashMap<>();
        this.beforeState = new HashMap<>();
        this.afterState = new HashMap<>();
    }

    public SecurityAuditEvent(EventType eventType, Severity severity) {
        this();
        this.eventType = eventType;
        this.severity = severity;
    }

    // Static factory methods for common events
    public static SecurityAuditEvent loginSuccess(String tenantId, String userId, String ipAddress) {
        SecurityAuditEvent event = new SecurityAuditEvent(EventType.LOGIN_SUCCESS, Severity.LOW);
        event.setTenantId(tenantId);
        event.setUserId(userId);
        event.setIpAddress(ipAddress);
        event.setAction("LOGIN");
        event.setOutcome("SUCCESS");
        event.setDescription("User successfully logged in");
        return event;
    }

    public static SecurityAuditEvent loginFailure(String tenantId, String userLogin, String ipAddress, String reason) {
        SecurityAuditEvent event = new SecurityAuditEvent(EventType.LOGIN_FAILURE, Severity.MEDIUM);
        event.setTenantId(tenantId);
        event.setUserLogin(userLogin);
        event.setIpAddress(ipAddress);
        event.setAction("LOGIN");
        event.setOutcome("FAILURE");
        event.setDescription("Login attempt failed: " + reason);
        event.addMetadata("failure_reason", reason);
        return event;
    }

    public static SecurityAuditEvent accessDenied(String tenantId, String userId, String resource, String permission) {
        SecurityAuditEvent event = new SecurityAuditEvent(EventType.ACCESS_DENIED, Severity.MEDIUM);
        event.setTenantId(tenantId);
        event.setUserId(userId);
        event.setResource(resource);
        event.setAction("ACCESS");
        event.setOutcome("DENIED");
        event.setDescription("Access denied to resource: " + resource);
        event.addMetadata("required_permission", permission);
        return event;
    }

    public static SecurityAuditEvent crossTenantAccessAttempt(String sourceTenantId, String targetTenantId, String userId, String resource) {
        SecurityAuditEvent event = new SecurityAuditEvent(EventType.CROSS_TENANT_ACCESS_ATTEMPT, Severity.HIGH);
        event.setTenantId(sourceTenantId);
        event.setUserId(userId);
        event.setResource(resource);
        event.setAction("CROSS_TENANT_ACCESS");
        event.setOutcome("BLOCKED");
        event.setDescription("Attempt to access resource from different tenant");
        event.addMetadata("target_tenant_id", targetTenantId);
        event.addMetadata("source_tenant_id", sourceTenantId);
        return event;
    }

    public static SecurityAuditEvent dataModification(String tenantId, String userId, String resource, String action, 
                                                     Map<String, Object> beforeState, Map<String, Object> afterState) {
        SecurityAuditEvent event = new SecurityAuditEvent(
            action.equals("CREATE") ? EventType.DATA_CREATED : 
            action.equals("UPDATE") ? EventType.DATA_UPDATED : EventType.DATA_DELETED, 
            Severity.LOW);
        event.setTenantId(tenantId);
        event.setUserId(userId);
        event.setResource(resource);
        event.setAction(action);
        event.setOutcome("SUCCESS");
        event.setDescription("Data " + action.toLowerCase() + " operation completed");
        event.setBeforeState(beforeState);
        event.setAfterState(afterState);
        return event;
    }

    public static SecurityAuditEvent tenantOperation(String tenantId, String userId, String operation, String targetTenantId) {
        SecurityAuditEvent event = new SecurityAuditEvent(
            operation.equals("CREATE") ? EventType.TENANT_CREATED :
            operation.equals("UPDATE") ? EventType.TENANT_UPDATED : EventType.TENANT_DELETED,
            Severity.MEDIUM);
        event.setTenantId(tenantId);
        event.setUserId(userId);
        event.setResource("tenant");
        event.setAction(operation);
        event.setOutcome("SUCCESS");
        event.setDescription("Tenant " + operation.toLowerCase() + " operation");
        event.addMetadata("target_tenant_id", targetTenantId);
        return event;
    }

    public static SecurityAuditEvent suspiciousActivity(String tenantId, String userId, String activityType, String description) {
        SecurityAuditEvent event = new SecurityAuditEvent(EventType.SUSPICIOUS_LOGIN_PATTERN, Severity.HIGH);
        event.setTenantId(tenantId);
        event.setUserId(userId);
        event.setAction("SUSPICIOUS_ACTIVITY");
        event.setOutcome("DETECTED");
        event.setDescription(description);
        event.addMetadata("activity_type", activityType);
        return event;
    }

    // Builder pattern for complex events
    public static class Builder {
        private SecurityAuditEvent event;

        public Builder(EventType eventType, Severity severity) {
            this.event = new SecurityAuditEvent(eventType, severity);
        }

        public Builder tenantId(String tenantId) {
            event.setTenantId(tenantId);
            return this;
        }

        public Builder userId(String userId) {
            event.setUserId(userId);
            return this;
        }

        public Builder userLogin(String userLogin) {
            event.setUserLogin(userLogin);
            return this;
        }

        public Builder ipAddress(String ipAddress) {
            event.setIpAddress(ipAddress);
            return this;
        }

        public Builder resource(String resource) {
            event.setResource(resource);
            return this;
        }

        public Builder action(String action) {
            event.setAction(action);
            return this;
        }

        public Builder outcome(String outcome) {
            event.setOutcome(outcome);
            return this;
        }

        public Builder description(String description) {
            event.setDescription(description);
            return this;
        }

        public Builder metadata(String key, Object value) {
            event.addMetadata(key, value);
            return this;
        }

        public Builder requestId(String requestId) {
            event.setRequestId(requestId);
            return this;
        }

        public SecurityAuditEvent build() {
            return event;
        }
    }

    // Getters and Setters
    public String getEventId() {
        return eventId;
    }

    public void setEventId(String eventId) {
        this.eventId = eventId;
    }

    public EventType getEventType() {
        return eventType;
    }

    public void setEventType(EventType eventType) {
        this.eventType = eventType;
    }

    public Severity getSeverity() {
        return severity;
    }

    public void setSeverity(Severity severity) {
        this.severity = severity;
    }

    public Instant getTimestamp() {
        return timestamp;
    }

    public void setTimestamp(Instant timestamp) {
        this.timestamp = timestamp;
    }

    public String getTenantId() {
        return tenantId;
    }

    public void setTenantId(String tenantId) {
        this.tenantId = tenantId;
    }

    public String getUserId() {
        return userId;
    }

    public void setUserId(String userId) {
        this.userId = userId;
    }

    public String getUserLogin() {
        return userLogin;
    }

    public void setUserLogin(String userLogin) {
        this.userLogin = userLogin;
    }

    public String getSessionId() {
        return sessionId;
    }

    public void setSessionId(String sessionId) {
        this.sessionId = sessionId;
    }

    public String getIpAddress() {
        return ipAddress;
    }

    public void setIpAddress(String ipAddress) {
        this.ipAddress = ipAddress;
    }

    public String getUserAgent() {
        return userAgent;
    }

    public void setUserAgent(String userAgent) {
        this.userAgent = userAgent;
    }

    public String getResource() {
        return resource;
    }

    public void setResource(String resource) {
        this.resource = resource;
    }

    public String getAction() {
        return action;
    }

    public void setAction(String action) {
        this.action = action;
    }

    public String getOutcome() {
        return outcome;
    }

    public void setOutcome(String outcome) {
        this.outcome = outcome;
    }

    public String getDescription() {
        return description;
    }

    public void setDescription(String description) {
        this.description = description;
    }

    public Map<String, Object> getMetadata() {
        return metadata;
    }

    public void setMetadata(Map<String, Object> metadata) {
        this.metadata = metadata;
    }

    public void addMetadata(String key, Object value) {
        if (this.metadata == null) {
            this.metadata = new HashMap<>();
        }
        this.metadata.put(key, value);
    }

    public Map<String, Object> getBeforeState() {
        return beforeState;
    }

    public void setBeforeState(Map<String, Object> beforeState) {
        this.beforeState = beforeState;
    }

    public Map<String, Object> getAfterState() {
        return afterState;
    }

    public void setAfterState(Map<String, Object> afterState) {
        this.afterState = afterState;
    }

    public String getRequestId() {
        return requestId;
    }

    public void setRequestId(String requestId) {
        this.requestId = requestId;
    }

    public String getCorrelationId() {
        return correlationId;
    }

    public void setCorrelationId(String correlationId) {
        this.correlationId = correlationId;
    }

    @Override
    public String toString() {
        return "SecurityAuditEvent{" +
            "eventId='" + eventId + '\'' +
            ", eventType=" + eventType +
            ", severity=" + severity +
            ", timestamp=" + timestamp +
            ", tenantId='" + tenantId + '\'' +
            ", userId='" + userId + '\'' +
            ", resource='" + resource + '\'' +
            ", action='" + action + '\'' +
            ", outcome='" + outcome + '\'' +
            '}';
    }
}
