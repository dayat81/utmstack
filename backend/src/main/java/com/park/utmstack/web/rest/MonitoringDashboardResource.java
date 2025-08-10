package com.park.utmstack.web.rest;

import com.park.utmstack.service.monitoring.MultiTenantMonitoringService;
import com.park.utmstack.service.monitoring.MultiTenantMonitoringService.*;
import com.park.utmstack.service.alerting.MultiTenantAlertingService;
import com.park.utmstack.service.alerting.MultiTenantAlertingService.*;
import com.park.utmstack.service.operations.TenantOperationsAutomationService;
import com.park.utmstack.service.operations.TenantOperationsAutomationService.*;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

import javax.validation.Valid;
import java.util.List;
import java.util.UUID;

/**
 * REST controller for monitoring dashboards and operational insights.
 * Provides comprehensive monitoring, alerting, and automation management APIs.
 */
@RestController
@RequestMapping("/api/admin/monitoring")
@PreAuthorize("hasAuthority('SUPER_ADMIN')")
public class MonitoringDashboardResource {

    private static final Logger log = LoggerFactory.getLogger(MonitoringDashboardResource.class);

    private final MultiTenantMonitoringService monitoringService;
    private final MultiTenantAlertingService alertingService;
    private final TenantOperationsAutomationService automationService;

    public MonitoringDashboardResource(MultiTenantMonitoringService monitoringService,
                                     MultiTenantAlertingService alertingService,
                                     TenantOperationsAutomationService automationService) {
        this.monitoringService = monitoringService;
        this.alertingService = alertingService;
        this.automationService = automationService;
    }

    /**
     * Get comprehensive monitoring dashboard
     */
    @GetMapping("/dashboard")
    public ResponseEntity<MonitoringDashboard> getMonitoringDashboard() {
        try {
            log.debug("Fetching monitoring dashboard");
            MonitoringDashboard dashboard = monitoringService.getMonitoringDashboard();
            return ResponseEntity.ok(dashboard);
        } catch (Exception e) {
            log.error("Error fetching monitoring dashboard", e);
            return ResponseEntity.status(500).build();
        }
    }

    /**
     * Get system health status
     */
    @GetMapping("/health")
    public ResponseEntity<SystemHealthStatus> getSystemHealth() {
        try {
            log.debug("Fetching system health status");
            SystemHealthStatus health = monitoringService.getSystemHealthStatus();
            return ResponseEntity.ok(health);
        } catch (Exception e) {
            log.error("Error fetching system health", e);
            return ResponseEntity.status(500).build();
        }
    }

    /**
     * Get aggregated metrics across all tenants
     */
    @GetMapping("/metrics/aggregated")
    public ResponseEntity<AggregatedMetrics> getAggregatedMetrics() {
        try {
            log.debug("Fetching aggregated metrics");
            AggregatedMetrics metrics = monitoringService.getAggregatedMetrics();
            return ResponseEntity.ok(metrics);
        } catch (Exception e) {
            log.error("Error fetching aggregated metrics", e);
            return ResponseEntity.status(500).build();
        }
    }

    /**
     * Get tenant-specific metrics
     */
    @GetMapping("/metrics/tenant/{tenantId}")
    public ResponseEntity<TenantMetrics> getTenantMetrics(@PathVariable UUID tenantId) {
        try {
            log.debug("Fetching metrics for tenant: {}", tenantId);
            TenantMetrics metrics = monitoringService.getTenantMetrics(tenantId);
            return ResponseEntity.ok(metrics);
        } catch (Exception e) {
            log.error("Error fetching tenant metrics for {}", tenantId, e);
            return ResponseEntity.status(500).build();
        }
    }

    /**
     * Record tenant provisioning metrics
     */
    @PostMapping("/metrics/provisioning")
    public ResponseEntity<Void> recordProvisioningMetrics(@RequestBody ProvisioningMetricsRequest request) {
        try {
            log.debug("Recording provisioning metrics for tenant: {}", request.getTenantId());
            monitoringService.recordTenantProvisioning(
                request.getTenantId(), 
                request.getTier(), 
                request.getDurationMs(), 
                request.isSuccess()
            );
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            log.error("Error recording provisioning metrics", e);
            return ResponseEntity.status(500).build();
        }
    }

    /**
     * Record quota violation
     */
    @PostMapping("/metrics/quota-violation")
    public ResponseEntity<Void> recordQuotaViolation(@RequestBody QuotaViolationRequest request) {
        try {
            log.debug("Recording quota violation for tenant: {}", request.getTenantId());
            monitoringService.recordQuotaViolation(
                request.getTenantId(), 
                request.getResourceType(), 
                request.getTier()
            );
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            log.error("Error recording quota violation", e);
            return ResponseEntity.status(500).build();
        }
    }

    /**
     * Record API response metrics
     */
    @PostMapping("/metrics/api-response")
    public ResponseEntity<Void> recordAPIResponse(@RequestBody APIResponseMetricsRequest request) {
        try {
            monitoringService.recordAPIResponse(
                request.getEndpoint(), 
                request.getMethod(), 
                request.getResponseTimeMs(), 
                request.getStatusCode()
            );
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            log.error("Error recording API response metrics", e);
            return ResponseEntity.status(500).build();
        }
    }

    // ===== ALERTING ENDPOINTS =====

    /**
     * Get all active alerts
     */
    @GetMapping("/alerts/active")
    public ResponseEntity<List<ActiveAlert>> getActiveAlerts() {
        try {
            log.debug("Fetching active alerts");
            List<ActiveAlert> alerts = alertingService.getActiveAlerts();
            return ResponseEntity.ok(alerts);
        } catch (Exception e) {
            log.error("Error fetching active alerts", e);
            return ResponseEntity.status(500).build();
        }
    }

    /**
     * Get alerts by severity
     */
    @GetMapping("/alerts/severity/{severity}")
    public ResponseEntity<List<ActiveAlert>> getAlertsBySeverity(@PathVariable AlertSeverity severity) {
        try {
            log.debug("Fetching alerts by severity: {}", severity);
            List<ActiveAlert> alerts = alertingService.getAlertsBySeverity(severity);
            return ResponseEntity.ok(alerts);
        } catch (Exception e) {
            log.error("Error fetching alerts by severity", e);
            return ResponseEntity.status(500).build();
        }
    }

    /**
     * Get alert history
     */
    @GetMapping("/alerts/history")
    public ResponseEntity<List<ActiveAlert>> getAlertHistory(@RequestParam(defaultValue = "100") int limit) {
        try {
            log.debug("Fetching alert history with limit: {}", limit);
            List<ActiveAlert> alerts = alertingService.getAlertHistory(limit);
            return ResponseEntity.ok(alerts);
        } catch (Exception e) {
            log.error("Error fetching alert history", e);
            return ResponseEntity.status(500).build();
        }
    }

    /**
     * Trigger manual alert
     */
    @PostMapping("/alerts/trigger")
    public ResponseEntity<AlertTriggerResponse> triggerAlert(@Valid @RequestBody TriggerAlertRequest request) {
        try {
            log.info("Triggering manual alert: type={}, severity={}", request.getAlertType(), request.getSeverity());
            String alertId = alertingService.triggerAlert(
                request.getAlertType(),
                request.getMessage(),
                request.getSeverity(),
                request.getContext()
            );
            
            AlertTriggerResponse response = new AlertTriggerResponse();
            response.setAlertId(alertId);
            response.setSuccess(true);
            
            return ResponseEntity.ok(response);
        } catch (Exception e) {
            log.error("Error triggering alert", e);
            return ResponseEntity.status(500).build();
        }
    }

    /**
     * Resolve an alert
     */
    @PostMapping("/alerts/{alertId}/resolve")
    public ResponseEntity<Void> resolveAlert(@PathVariable String alertId, 
                                           @RequestBody ResolveAlertRequest request) {
        try {
            log.info("Resolving alert: alertId={}, resolution={}", alertId, request.getResolution());
            alertingService.resolveAlert(alertId, request.getResolution());
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            log.error("Error resolving alert: {}", alertId, e);
            return ResponseEntity.status(500).build();
        }
    }

    /**
     * Create alert rule
     */
    @PostMapping("/alerts/rules")
    public ResponseEntity<AlertRuleCreateResponse> createAlertRule(@Valid @RequestBody AlertRuleDefinition definition) {
        try {
            log.info("Creating alert rule: name={}", definition.getName());
            String ruleId = alertingService.createAlertRule(definition);
            
            AlertRuleCreateResponse response = new AlertRuleCreateResponse();
            response.setRuleId(ruleId);
            response.setSuccess(true);
            
            return ResponseEntity.ok(response);
        } catch (Exception e) {
            log.error("Error creating alert rule", e);
            return ResponseEntity.status(500).build();
        }
    }

    /**
     * Update alert rule
     */
    @PutMapping("/alerts/rules/{ruleId}")
    public ResponseEntity<Void> updateAlertRule(@PathVariable String ruleId, 
                                              @Valid @RequestBody AlertRuleDefinition definition) {
        try {
            log.info("Updating alert rule: ruleId={}", ruleId);
            alertingService.updateAlertRule(ruleId, definition);
            return ResponseEntity.ok().build();
        } catch (IllegalArgumentException e) {
            return ResponseEntity.notFound().build();
        } catch (Exception e) {
            log.error("Error updating alert rule: {}", ruleId, e);
            return ResponseEntity.status(500).build();
        }
    }

    /**
     * Delete alert rule
     */
    @DeleteMapping("/alerts/rules/{ruleId}")
    public ResponseEntity<Void> deleteAlertRule(@PathVariable String ruleId) {
        try {
            log.info("Deleting alert rule: ruleId={}", ruleId);
            alertingService.deleteAlertRule(ruleId);
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            log.error("Error deleting alert rule: {}", ruleId, e);
            return ResponseEntity.status(500).build();
        }
    }

    /**
     * Get alert statistics
     */
    @GetMapping("/alerts/statistics")
    public ResponseEntity<AlertStatistics> getAlertStatistics() {
        try {
            log.debug("Fetching alert statistics");
            AlertStatistics stats = alertingService.getAlertStatistics();
            return ResponseEntity.ok(stats);
        } catch (Exception e) {
            log.error("Error fetching alert statistics", e);
            return ResponseEntity.status(500).build();
        }
    }

    // ===== AUTOMATION ENDPOINTS =====

    /**
     * Execute automated maintenance
     */
    @PostMapping("/automation/maintenance")
    public ResponseEntity<AutomationExecutionResult> executeAutomatedMaintenance() {
        try {
            log.info("Executing automated maintenance");
            AutomationExecutionResult result = automationService.executeAutomatedMaintenance();
            return ResponseEntity.ok(result);
        } catch (Exception e) {
            log.error("Error executing automated maintenance", e);
            return ResponseEntity.status(500).build();
        }
    }

    /**
     * Perform automated tenant scaling
     */
    @PostMapping("/automation/scaling")
    public ResponseEntity<TenantScalingResult> performAutomatedScaling() {
        try {
            log.info("Performing automated tenant scaling");
            TenantScalingResult result = automationService.performAutomatedTenantScaling();
            return ResponseEntity.ok(result);
        } catch (Exception e) {
            log.error("Error performing automated scaling", e);
            return ResponseEntity.status(500).build();
        }
    }

    /**
     * Perform automated health checks
     */
    @PostMapping("/automation/health-checks")
    public ResponseEntity<TenantHealthCheckResult> performHealthChecks() {
        try {
            log.info("Performing automated health checks");
            TenantHealthCheckResult result = automationService.performAutomatedHealthChecks();
            return ResponseEntity.ok(result);
        } catch (Exception e) {
            log.error("Error performing health checks", e);
            return ResponseEntity.status(500).build();
        }
    }

    /**
     * Execute lifecycle automation
     */
    @PostMapping("/automation/lifecycle")
    public ResponseEntity<LifecycleAutomationResult> executeLifecycleAutomation() {
        try {
            log.info("Executing lifecycle automation");
            LifecycleAutomationResult result = automationService.executeLifecycleAutomation();
            return ResponseEntity.ok(result);
        } catch (Exception e) {
            log.error("Error executing lifecycle automation", e);
            return ResponseEntity.status(500).build();
        }
    }

    /**
     * Create automation rule
     */
    @PostMapping("/automation/rules")
    public ResponseEntity<AutomationRuleCreateResponse> createAutomationRule(
            @Valid @RequestBody AutomationRuleDefinition definition) {
        try {
            log.info("Creating automation rule: name={}", definition.getName());
            String ruleId = automationService.createAutomationRule(definition);
            
            AutomationRuleCreateResponse response = new AutomationRuleCreateResponse();
            response.setRuleId(ruleId);
            response.setSuccess(true);
            
            return ResponseEntity.ok(response);
        } catch (Exception e) {
            log.error("Error creating automation rule", e);
            return ResponseEntity.status(500).build();
        }
    }

    /**
     * Get automation statistics
     */
    @GetMapping("/automation/statistics")
    public ResponseEntity<AutomationStatistics> getAutomationStatistics() {
        try {
            log.debug("Fetching automation statistics");
            AutomationStatistics stats = automationService.getAutomationStatistics();
            return ResponseEntity.ok(stats);
        } catch (Exception e) {
            log.error("Error fetching automation statistics", e);
            return ResponseEntity.status(500).build();
        }
    }

    // Request/Response DTOs
    public static class ProvisioningMetricsRequest {
        private UUID tenantId;
        private String tier;
        private long durationMs;
        private boolean success;

        // Getters and setters
        public UUID getTenantId() { return tenantId; }
        public void setTenantId(UUID tenantId) { this.tenantId = tenantId; }

        public String getTier() { return tier; }
        public void setTier(String tier) { this.tier = tier; }

        public long getDurationMs() { return durationMs; }
        public void setDurationMs(long durationMs) { this.durationMs = durationMs; }

        public boolean isSuccess() { return success; }
        public void setSuccess(boolean success) { this.success = success; }
    }

    public static class QuotaViolationRequest {
        private UUID tenantId;
        private String resourceType;
        private String tier;

        // Getters and setters
        public UUID getTenantId() { return tenantId; }
        public void setTenantId(UUID tenantId) { this.tenantId = tenantId; }

        public String getResourceType() { return resourceType; }
        public void setResourceType(String resourceType) { this.resourceType = resourceType; }

        public String getTier() { return tier; }
        public void setTier(String tier) { this.tier = tier; }
    }

    public static class APIResponseMetricsRequest {
        private String endpoint;
        private String method;
        private long responseTimeMs;
        private int statusCode;

        // Getters and setters
        public String getEndpoint() { return endpoint; }
        public void setEndpoint(String endpoint) { this.endpoint = endpoint; }

        public String getMethod() { return method; }
        public void setMethod(String method) { this.method = method; }

        public long getResponseTimeMs() { return responseTimeMs; }
        public void setResponseTimeMs(long responseTimeMs) { this.responseTimeMs = responseTimeMs; }

        public int getStatusCode() { return statusCode; }
        public void setStatusCode(int statusCode) { this.statusCode = statusCode; }
    }

    public static class TriggerAlertRequest {
        private String alertType;
        private String message;
        private AlertSeverity severity;
        private java.util.Map<String, Object> context;

        // Getters and setters
        public String getAlertType() { return alertType; }
        public void setAlertType(String alertType) { this.alertType = alertType; }

        public String getMessage() { return message; }
        public void setMessage(String message) { this.message = message; }

        public AlertSeverity getSeverity() { return severity; }
        public void setSeverity(AlertSeverity severity) { this.severity = severity; }

        public java.util.Map<String, Object> getContext() { return context; }
        public void setContext(java.util.Map<String, Object> context) { this.context = context; }
    }

    public static class AlertTriggerResponse {
        private String alertId;
        private boolean success;

        // Getters and setters
        public String getAlertId() { return alertId; }
        public void setAlertId(String alertId) { this.alertId = alertId; }

        public boolean isSuccess() { return success; }
        public void setSuccess(boolean success) { this.success = success; }
    }

    public static class ResolveAlertRequest {
        private String resolution;

        // Getters and setters
        public String getResolution() { return resolution; }
        public void setResolution(String resolution) { this.resolution = resolution; }
    }

    public static class AlertRuleCreateResponse {
        private String ruleId;
        private boolean success;

        // Getters and setters
        public String getRuleId() { return ruleId; }
        public void setRuleId(String ruleId) { this.ruleId = ruleId; }

        public boolean isSuccess() { return success; }
        public void setSuccess(boolean success) { this.success = success; }
    }

    public static class AutomationRuleCreateResponse {
        private String ruleId;
        private boolean success;

        // Getters and setters
        public String getRuleId() { return ruleId; }
        public void setRuleId(String ruleId) { this.ruleId = ruleId; }

        public boolean isSuccess() { return success; }
        public void setSuccess(boolean success) { this.success = success; }
    }
}
