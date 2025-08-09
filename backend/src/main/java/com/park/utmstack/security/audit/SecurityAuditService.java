package com.park.utmstack.security.audit;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.park.utmstack.security.TenantContext;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.event.EventListener;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;

import javax.annotation.PostConstruct;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardOpenOption;
import java.time.Instant;
import java.time.format.DateTimeFormatter;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.LinkedBlockingQueue;

/**
 * Service for handling security audit events in multi-tenant environment.
 */
@Service
public class SecurityAuditService {

    private static final Logger log = LoggerFactory.getLogger(SecurityAuditService.class);
    private static final Logger auditLogger = LoggerFactory.getLogger("SECURITY_AUDIT");

    @Value("${utmstack.audit.log-to-file:true}")
    private boolean logToFile;

    @Value("${utmstack.audit.log-directory:./logs/audit}")
    private String auditLogDirectory;

    @Value("${utmstack.audit.max-queue-size:10000}")
    private int maxQueueSize;

    @Value("${utmstack.audit.async-processing:true}")
    private boolean asyncProcessing;

    private final ObjectMapper objectMapper;
    private final BlockingQueue<SecurityAuditEvent> auditQueue;
    private volatile boolean processingEnabled = true;

    public SecurityAuditService() {
        this.objectMapper = new ObjectMapper();
        this.auditQueue = new LinkedBlockingQueue<>();
    }

    @PostConstruct
    public void initialize() {
        if (logToFile) {
            try {
                Path auditDir = Paths.get(auditLogDirectory);
                if (!Files.exists(auditDir)) {
                    Files.createDirectories(auditDir);
                    log.info("Created audit log directory: {}", auditDir);
                }
            } catch (IOException e) {
                log.error("Failed to create audit log directory: {}", auditLogDirectory, e);
                logToFile = false;
            }
        }

        if (asyncProcessing) {
            startAsyncProcessor();
        }

        log.info("Security audit service initialized - logToFile: {}, asyncProcessing: {}", logToFile, asyncProcessing);
    }

    /**
     * Log a security audit event
     */
    public void audit(SecurityAuditEvent event) {
        try {
            // Enrich event with current context if not already set
            enrichEventContext(event);

            if (asyncProcessing) {
                if (auditQueue.size() < maxQueueSize) {
                    auditQueue.offer(event);
                } else {
                    log.warn("Audit queue is full, processing event synchronously");
                    processAuditEvent(event);
                }
            } else {
                processAuditEvent(event);
            }
        } catch (Exception e) {
            log.error("Failed to audit security event: {}", event, e);
        }
    }

    /**
     * Convenience methods for common audit events
     */
    public void auditLogin(String tenantId, String userId, String ipAddress, boolean success, String reason) {
        SecurityAuditEvent event = success ? 
            SecurityAuditEvent.loginSuccess(tenantId, userId, ipAddress) :
            SecurityAuditEvent.loginFailure(tenantId, userId, ipAddress, reason);
        audit(event);
    }

    public void auditAccessDenied(String resource, String permission) {
        String tenantId = TenantContext.getCurrentTenant();
        String userId = getCurrentUserId(); // This would be extracted from security context
        SecurityAuditEvent event = SecurityAuditEvent.accessDenied(tenantId, userId, resource, permission);
        audit(event);
    }

    public void auditDataModification(String resource, String action, Object beforeState, Object afterState) {
        String tenantId = TenantContext.getCurrentTenant();
        String userId = getCurrentUserId();
        
        SecurityAuditEvent event = SecurityAuditEvent.dataModification(
            tenantId, userId, resource, action,
            convertToMap(beforeState), convertToMap(afterState));
        audit(event);
    }

    public void auditTenantOperation(String operation, String targetTenantId) {
        String tenantId = TenantContext.getCurrentTenant();
        String userId = getCurrentUserId();
        SecurityAuditEvent event = SecurityAuditEvent.tenantOperation(tenantId, userId, operation, targetTenantId);
        audit(event);
    }

    public void auditSuspiciousActivity(String activityType, String description) {
        String tenantId = TenantContext.getCurrentTenant();
        String userId = getCurrentUserId();
        SecurityAuditEvent event = SecurityAuditEvent.suspiciousActivity(tenantId, userId, activityType, description);
        audit(event);
    }

    /**
     * Event listener for Spring application events
     */
    @EventListener
    @Async
    public void handleSecurityAuditEvent(SecurityAuditEvent event) {
        audit(event);
    }

    /**
     * Process audit event (write to logs, database, etc.)
     */
    private void processAuditEvent(SecurityAuditEvent event) {
        try {
            // Log to application logger
            auditLogger.info("AUDIT_EVENT: {}", objectMapper.writeValueAsString(event));

            // Log to file if enabled
            if (logToFile) {
                writeToAuditFile(event);
            }

            // TODO: Add database storage if needed
            // TODO: Add external SIEM integration if needed

        } catch (Exception e) {
            log.error("Failed to process audit event: {}", event, e);
        }
    }

    /**
     * Write audit event to file
     */
    private void writeToAuditFile(SecurityAuditEvent event) {
        try {
            String dateString = DateTimeFormatter.ofPattern("yyyy-MM-dd").format(event.getTimestamp());
            String fileName = String.format("security-audit-%s.log", dateString);
            Path filePath = Paths.get(auditLogDirectory, fileName);

            String logLine = objectMapper.writeValueAsString(event) + System.lineSeparator();
            Files.write(filePath, logLine.getBytes(), StandardOpenOption.CREATE, StandardOpenOption.APPEND);

        } catch (IOException e) {
            log.error("Failed to write audit event to file", e);
        }
    }

    /**
     * Enrich event with current context information
     */
    private void enrichEventContext(SecurityAuditEvent event) {
        // Set tenant ID if not already set
        if (event.getTenantId() == null) {
            event.setTenantId(TenantContext.getCurrentTenant());
        }

        // Set user ID if not already set
        if (event.getUserId() == null) {
            event.setUserId(getCurrentUserId());
        }

        // TODO: Extract additional context from HTTP request
        // - IP address
        // - User agent
        // - Session ID
        // - Request ID
    }

    /**
     * Start asynchronous audit event processor
     */
    private void startAsyncProcessor() {
        Thread processorThread = new Thread(() -> {
            log.info("Started async audit event processor");
            
            while (processingEnabled) {
                try {
                    SecurityAuditEvent event = auditQueue.take();
                    processAuditEvent(event);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    log.info("Audit processor thread interrupted");
                    break;
                } catch (Exception e) {
                    log.error("Error in audit processor thread", e);
                }
            }
            
            log.info("Stopped async audit event processor");
        });

        processorThread.setName("audit-processor");
        processorThread.setDaemon(true);
        processorThread.start();
    }

    /**
     * Get current user ID from security context
     */
    private String getCurrentUserId() {
        // TODO: Extract from Spring Security context
        // This is a placeholder implementation
        return "current-user-id";
    }

    /**
     * Convert object to map for audit trail
     */
    @SuppressWarnings("unchecked")
    private java.util.Map<String, Object> convertToMap(Object obj) {
        if (obj == null) {
            return null;
        }
        
        try {
            return objectMapper.convertValue(obj, java.util.Map.class);
        } catch (Exception e) {
            log.warn("Failed to convert object to map for audit: {}", obj.getClass().getSimpleName());
            return java.util.Map.of("object_type", obj.getClass().getSimpleName(), "toString", obj.toString());
        }
    }

    /**
     * Shutdown the audit service gracefully
     */
    public void shutdown() {
        log.info("Shutting down security audit service");
        processingEnabled = false;
        
        // Process remaining events in queue
        while (!auditQueue.isEmpty()) {
            try {
                SecurityAuditEvent event = auditQueue.poll();
                if (event != null) {
                    processAuditEvent(event);
                }
            } catch (Exception e) {
                log.error("Error processing remaining audit events during shutdown", e);
            }
        }
    }

    /**
     * Get audit queue size for monitoring
     */
    public int getQueueSize() {
        return auditQueue.size();
    }

    /**
     * Check if audit service is healthy
     */
    public boolean isHealthy() {
        return processingEnabled && auditQueue.size() < maxQueueSize * 0.9;
    }
}
