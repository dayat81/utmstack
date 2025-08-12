package com.park.utmstack.service;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.park.utmstack.domain.SecurityAuditEvent;
import com.park.utmstack.repository.SecurityAuditEventRepository;
import com.park.utmstack.security.TenantContext;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Map;
import java.util.UUID;

@Service
@Transactional
public class SecurityAuditService {

    private static final Logger log = LoggerFactory.getLogger(SecurityAuditService.class);

    @Autowired
    private SecurityAuditEventRepository auditEventRepository;

    @Autowired
    private ObjectMapper objectMapper;

    public enum EventType {
        USER_LOGIN("LOW"),
        USER_LOGOUT("LOW"),
        AUTHENTICATION_FAILURE("HIGH"),
        AUTHORIZATION_FAILURE("MEDIUM"),
        DATA_ACCESS("LOW"),
        DATA_MODIFICATION("MEDIUM"),
        ADMIN_ACCESS("MEDIUM"),
        SECURITY_VIOLATION("HIGH"),
        TENANT_ACCESS_VIOLATION("CRITICAL"),
        PRIVILEGE_ESCALATION("CRITICAL"),
        SUSPICIOUS_ACTIVITY("HIGH"),
        COMPLIANCE_VIOLATION("HIGH"),
        DATA_EXPORT("MEDIUM"),
        CONFIGURATION_CHANGE("MEDIUM"),
        BULK_OPERATION("MEDIUM");

        private final String defaultSeverity;

        EventType(String defaultSeverity) {
            this.defaultSeverity = defaultSeverity;
        }

        public String getDefaultSeverity() {
            return defaultSeverity;
        }
    }

    public SecurityAuditEvent createAuditEvent(EventType eventType, String userId, String description, Map<String, Object> metadata) {
        try {
            SecurityAuditEvent event = new SecurityAuditEvent();
            event.setTenantId(TenantContext.getCurrentTenantId());
            event.setUserId(userId);
            event.setEventType(eventType.name());
            event.setDescription(description);
            event.setSeverity(eventType.getDefaultSeverity());
            
            if (metadata != null) {
                String metadataJson = objectMapper.writeValueAsString(metadata);
                event.setMetadata(metadataJson);
                
                // Extract common fields from metadata
                if (metadata.containsKey("ip_address")) {
                    event.setIpAddress((String) metadata.get("ip_address"));
                }
                if (metadata.containsKey("user_agent")) {
                    event.setUserAgent((String) metadata.get("user_agent"));
                }
                if (metadata.containsKey("session_id")) {
                    event.setSessionId((String) metadata.get("session_id"));
                }
            }
            
            event = auditEventRepository.save(event);
            log.debug("Created audit event: {} for tenant: {}", event.getId(), event.getTenantId());
            
            return event;
        } catch (JsonProcessingException e) {
            log.error("Failed to serialize audit event metadata", e);
            throw new RuntimeException("Failed to create audit event", e);
        }
    }

    @Async
    public void auditAsync(EventType eventType, String userId, String description, Map<String, Object> metadata) {
        createAuditEvent(eventType, userId, description, metadata);
    }

    public void auditUserLogin(String userId, String ipAddress, String userAgent) {
        Map<String, Object> metadata = Map.of(
            "ip_address", ipAddress,
            "user_agent", userAgent
        );
        createAuditEvent(EventType.USER_LOGIN, userId, "User logged in successfully", metadata);
    }

    public void auditAuthenticationFailure(String userId, String reason, String ipAddress) {
        Map<String, Object> metadata = Map.of(
            "ip_address", ipAddress,
            "failure_reason", reason
        );
        createAuditEvent(EventType.AUTHENTICATION_FAILURE, userId, "Authentication failed: " + reason, metadata);
    }

    public void auditAuthorizationFailure(String userId, String resource, String action, String ipAddress) {
        Map<String, Object> metadata = Map.of(
            "ip_address", ipAddress,
            "resource", resource,
            "action", action
        );
        createAuditEvent(EventType.AUTHORIZATION_FAILURE, userId, 
            String.format("Access denied to %s for action %s", resource, action), metadata);
    }

    public void auditDataAccess(String userId, String resource, String operation) {
        Map<String, Object> metadata = Map.of(
            "resource", resource,
            "operation", operation
        );
        createAuditEvent(EventType.DATA_ACCESS, userId, 
            String.format("Data access: %s on %s", operation, resource), metadata);
    }

    public void auditTenantAccessViolation(String userId, UUID attemptedTenantId, String details) {
        Map<String, Object> metadata = Map.of(
            "attempted_tenant_id", attemptedTenantId.toString(),
            "current_tenant_id", TenantContext.getCurrentTenantId().toString(),
            "violation_details", details
        );
        createAuditEvent(EventType.TENANT_ACCESS_VIOLATION, userId, 
            "Cross-tenant access violation detected", metadata);
    }

    public void auditComplianceViolation(String userId, String complianceType, String violation, String severity) {
        Map<String, Object> metadata = Map.of(
            "compliance_type", complianceType,
            "violation_type", violation,
            "severity", severity
        );
        createAuditEvent(EventType.COMPLIANCE_VIOLATION, userId, 
            String.format("%s compliance violation: %s", complianceType, violation), metadata);
    }

    public List<SecurityAuditEvent> getAuditEventsForTenant(UUID tenantId, Instant fromDate, Instant toDate) {
        return auditEventRepository.findByTenantIdAndTimestampBetween(tenantId, fromDate, toDate);
    }

    public List<SecurityAuditEvent> getHighSeverityEvents(UUID tenantId, int hours) {
        Instant fromDate = Instant.now().minus(hours, ChronoUnit.HOURS);
        return auditEventRepository.findByTenantIdAndSeverityInAndTimestampGreaterThan(
            tenantId, List.of("HIGH", "CRITICAL"), fromDate);
    }

    public long getEventCountByType(UUID tenantId, EventType eventType, int hours) {
        Instant fromDate = Instant.now().minus(hours, ChronoUnit.HOURS);
        return auditEventRepository.countByTenantIdAndEventTypeAndTimestampGreaterThan(
            tenantId, eventType.name(), fromDate);
    }

    public List<SecurityAuditEvent> findSuspiciousActivity(UUID tenantId, int hours) {
        Instant fromDate = Instant.now().minus(hours, ChronoUnit.HOURS);
        return auditEventRepository.findByTenantIdAndEventTypeInAndTimestampGreaterThan(
            tenantId, 
            List.of(
                EventType.AUTHENTICATION_FAILURE.name(),
                EventType.TENANT_ACCESS_VIOLATION.name(),
                EventType.PRIVILEGE_ESCALATION.name(),
                EventType.SUSPICIOUS_ACTIVITY.name()
            ), 
            fromDate
        );
    }

    public void cleanupOldEvents(int retentionDays) {
        Instant cutoffDate = Instant.now().minus(retentionDays, ChronoUnit.DAYS);
        auditEventRepository.deleteByTimestampBefore(cutoffDate);
        log.info("Cleaned up audit events older than {} days", retentionDays);
    }
}