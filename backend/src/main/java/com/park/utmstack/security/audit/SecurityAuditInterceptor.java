package com.park.utmstack.security.audit;

import com.park.utmstack.security.TenantContext;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.web.servlet.HandlerInterceptor;

import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.time.Instant;
import java.util.Set;
import java.util.UUID;

/**
 * Interceptor to automatically audit security-relevant HTTP requests.
 */
@Component
public class SecurityAuditInterceptor implements HandlerInterceptor {

    private static final Logger log = LoggerFactory.getLogger(SecurityAuditInterceptor.class);

    private final SecurityAuditService auditService;

    // Sensitive endpoints that should always be audited
    private static final Set<String> ALWAYS_AUDIT_PATHS = Set.of(
        "/api/authenticate",
        "/api/account",
        "/api/admin",
        "/management",
        "/api/users",
        "/api/tenants"
    );

    // HTTP methods that modify data
    private static final Set<String> MODIFYING_METHODS = Set.of("POST", "PUT", "DELETE", "PATCH");

    public SecurityAuditInterceptor(SecurityAuditService auditService) {
        this.auditService = auditService;
    }

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) {
        try {
            String requestPath = request.getRequestURI();
            String method = request.getMethod();
            
            // Check if this request should be audited
            if (shouldAuditRequest(requestPath, method)) {
                auditRequest(request);
            }

            // Check for cross-tenant access attempts
            checkCrossTenantAccess(request);

            return true;
        } catch (Exception e) {
            log.error("Error in security audit interceptor", e);
            return true; // Don't block the request due to audit errors
        }
    }

    @Override
    public void afterCompletion(HttpServletRequest request, HttpServletResponse response, Object handler, Exception ex) {
        try {
            String requestPath = request.getRequestURI();
            String method = request.getMethod();
            
            // Audit the response if it was a sensitive operation
            if (shouldAuditRequest(requestPath, method)) {
                auditResponse(request, response, ex);
            }

            // Check for suspicious response patterns
            checkSuspiciousResponse(request, response);

        } catch (Exception e) {
            log.error("Error in security audit interceptor afterCompletion", e);
        }
    }

    /**
     * Audit the incoming request
     */
    private void auditRequest(HttpServletRequest request) {
        String tenantId = TenantContext.getCurrentTenant();
        String userId = getCurrentUserId();
        String userLogin = getCurrentUserLogin();
        String ipAddress = getClientIpAddress(request);
        String userAgent = request.getHeader("User-Agent");
        String requestPath = request.getRequestURI();
        String method = request.getMethod();

        SecurityAuditEvent event = new SecurityAuditEvent.Builder(
            SecurityAuditEvent.EventType.DATA_READ, SecurityAuditEvent.Severity.LOW)
            .tenantId(tenantId)
            .userId(userId)
            .userLogin(userLogin)
            .ipAddress(ipAddress)
            .resource(requestPath)
            .action(method)
            .description("HTTP request to " + method + " " + requestPath)
            .metadata("user_agent", userAgent)
            .metadata("query_string", request.getQueryString())
            .requestId(generateRequestId())
            .build();

        // Adjust event type and severity based on the request
        if (MODIFYING_METHODS.contains(method)) {
            if (method.equals("POST")) {
                event.setEventType(SecurityAuditEvent.EventType.DATA_CREATED);
            } else if (method.equals("PUT") || method.equals("PATCH")) {
                event.setEventType(SecurityAuditEvent.EventType.DATA_UPDATED);
            } else if (method.equals("DELETE")) {
                event.setEventType(SecurityAuditEvent.EventType.DATA_DELETED);
                event.setSeverity(SecurityAuditEvent.Severity.MEDIUM);
            }
        }

        // Increase severity for admin endpoints
        if (requestPath.contains("/admin") || requestPath.contains("/management")) {
            event.setSeverity(SecurityAuditEvent.Severity.MEDIUM);
        }

        auditService.audit(event);
    }

    /**
     * Audit the response
     */
    private void auditResponse(HttpServletRequest request, HttpServletResponse response, Exception ex) {
        String tenantId = TenantContext.getCurrentTenant();
        String userId = getCurrentUserId();
        String requestPath = request.getRequestURI();
        String method = request.getMethod();
        int statusCode = response.getStatus();

        String outcome = (statusCode >= 200 && statusCode < 300) ? "SUCCESS" : "FAILURE";
        SecurityAuditEvent.Severity severity = (statusCode >= 400) ? 
            SecurityAuditEvent.Severity.MEDIUM : SecurityAuditEvent.Severity.LOW;

        SecurityAuditEvent event = new SecurityAuditEvent.Builder(
            SecurityAuditEvent.EventType.DATA_READ, severity)
            .tenantId(tenantId)
            .userId(userId)
            .resource(requestPath)
            .action(method + "_RESPONSE")
            .outcome(outcome)
            .description("HTTP response for " + method + " " + requestPath + " - Status: " + statusCode)
            .metadata("status_code", statusCode)
            .metadata("response_time_ms", System.currentTimeMillis() - getRequestStartTime(request))
            .build();

        if (ex != null) {
            event.setEventType(SecurityAuditEvent.EventType.SYSTEM_ERROR);
            event.setSeverity(SecurityAuditEvent.Severity.HIGH);
            event.setOutcome("ERROR");
            event.addMetadata("exception", ex.getClass().getSimpleName());
            event.addMetadata("error_message", ex.getMessage());
        }

        // Check for access denied responses
        if (statusCode == 401 || statusCode == 403) {
            event.setEventType(SecurityAuditEvent.EventType.ACCESS_DENIED);
            event.setSeverity(SecurityAuditEvent.Severity.MEDIUM);
        }

        auditService.audit(event);
    }

    /**
     * Check for cross-tenant access attempts
     */
    private void checkCrossTenantAccess(HttpServletRequest request) {
        String currentTenantId = TenantContext.getCurrentTenant();
        String requestedTenantId = request.getParameter("tenantId");
        
        if (currentTenantId != null && requestedTenantId != null && 
            !currentTenantId.equals(requestedTenantId)) {
            
            String userId = getCurrentUserId();
            String requestPath = request.getRequestURI();
            
            SecurityAuditEvent event = SecurityAuditEvent.crossTenantAccessAttempt(
                currentTenantId, requestedTenantId, userId, requestPath);
            event.setIpAddress(getClientIpAddress(request));
            event.addMetadata("request_uri", request.getRequestURI());
            event.addMetadata("query_string", request.getQueryString());
            
            auditService.audit(event);
            
            log.warn("Cross-tenant access attempt detected: user={}, currentTenant={}, requestedTenant={}, path={}",
                userId, currentTenantId, requestedTenantId, requestPath);
        }
    }

    /**
     * Check for suspicious response patterns
     */
    private void checkSuspiciousResponse(HttpServletRequest request, HttpServletResponse response) {
        String ipAddress = getClientIpAddress(request);
        String userId = getCurrentUserId();
        String tenantId = TenantContext.getCurrentTenant();
        
        // Check for multiple failed authentication attempts
        if (request.getRequestURI().contains("/authenticate") && response.getStatus() == 401) {
            // This would typically check a cache/database for recent failed attempts
            // For now, just log the event
            SecurityAuditEvent event = new SecurityAuditEvent.Builder(
                SecurityAuditEvent.EventType.MULTIPLE_FAILED_LOGINS, SecurityAuditEvent.Severity.HIGH)
                .tenantId(tenantId)
                .userId(userId)
                .ipAddress(ipAddress)
                .action("FAILED_LOGIN_ATTEMPT")
                .description("Failed login attempt detected")
                .build();
            
            auditService.audit(event);
        }

        // Check for unusual data access patterns
        if (response.getStatus() == 200 && MODIFYING_METHODS.contains(request.getMethod())) {
            long responseTime = System.currentTimeMillis() - getRequestStartTime(request);
            
            // If request took unusually long, it might indicate bulk operations
            if (responseTime > 5000) { // 5 seconds threshold
                SecurityAuditEvent event = new SecurityAuditEvent.Builder(
                    SecurityAuditEvent.EventType.UNUSUAL_DATA_ACCESS, SecurityAuditEvent.Severity.MEDIUM)
                    .tenantId(tenantId)
                    .userId(userId)
                    .resource(request.getRequestURI())
                    .action("SLOW_OPERATION")
                    .description("Unusually slow operation detected")
                    .metadata("response_time_ms", responseTime)
                    .build();
                
                auditService.audit(event);
            }
        }
    }

    /**
     * Determine if a request should be audited
     */
    private boolean shouldAuditRequest(String requestPath, String method) {
        // Always audit sensitive paths
        if (ALWAYS_AUDIT_PATHS.stream().anyMatch(requestPath::startsWith)) {
            return true;
        }

        // Always audit modifying operations
        if (MODIFYING_METHODS.contains(method)) {
            return true;
        }

        // Audit API calls (excluding static resources)
        return requestPath.startsWith("/api/") && !requestPath.contains("/static/");
    }

    /**
     * Get current user ID from security context
     */
    private String getCurrentUserId() {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication != null && authentication.isAuthenticated()) {
            return authentication.getName();
        }
        return null;
    }

    /**
     * Get current user login from security context
     */
    private String getCurrentUserLogin() {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication != null && authentication.isAuthenticated()) {
            return authentication.getName();
        }
        return null;
    }

    /**
     * Extract client IP address from request
     */
    private String getClientIpAddress(HttpServletRequest request) {
        String xForwardedFor = request.getHeader("X-Forwarded-For");
        if (xForwardedFor != null && !xForwardedFor.isEmpty()) {
            return xForwardedFor.split(",")[0].trim();
        }
        
        String xRealIp = request.getHeader("X-Real-IP");
        if (xRealIp != null && !xRealIp.isEmpty()) {
            return xRealIp;
        }
        
        return request.getRemoteAddr();
    }

    /**
     * Generate unique request ID for correlation
     */
    private String generateRequestId() {
        return "req-" + UUID.randomUUID().toString().substring(0, 8);
    }

    /**
     * Get request start time (would be set by another interceptor or filter)
     */
    private long getRequestStartTime(HttpServletRequest request) {
        Object startTime = request.getAttribute("REQUEST_START_TIME");
        if (startTime instanceof Long) {
            return (Long) startTime;
        }
        return System.currentTimeMillis(); // Fallback
    }
}
