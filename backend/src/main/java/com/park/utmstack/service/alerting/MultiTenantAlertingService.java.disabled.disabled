package com.park.utmstack.service.alerting;

import com.park.utmstack.service.monitoring.MultiTenantMonitoringService;
import com.park.utmstack.service.TenantService;
import com.park.utmstack.service.TenantProvisioningService;
import com.park.utmstack.service.TenantResourceQuotaService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Service;

import javax.annotation.PostConstruct;
import java.time.Instant;
import java.time.LocalDateTime;
import java.util.*;
import java.util.concurrent.*;
import java.util.stream.Collectors;

/**
 * Advanced alerting service for multi-tenant system monitoring.
 * Provides intelligent alerts, escalation policies, and notification management.
 */
@Service
public class MultiTenantAlertingService {

    private static final Logger log = LoggerFactory.getLogger(MultiTenantAlertingService.class);

    private final MultiTenantMonitoringService monitoringService;
    private final TenantService tenantService;
    private final TenantProvisioningService provisioningService;
    private final TenantResourceQuotaService quotaService;
    private final ApplicationEventPublisher eventPublisher;
    private final ScheduledExecutorService scheduler = Executors.newScheduledThreadPool(3);

    // Alert management
    private final Map<String, AlertRule> alertRules = new ConcurrentHashMap<>();
    private final Map<String, ActiveAlert> activeAlerts = new ConcurrentHashMap<>();
    private final List<AlertNotificationChannel> notificationChannels = new ArrayList<>();

    public MultiTenantAlertingService(MultiTenantMonitoringService monitoringService,
    TenantService tenantService,
    TenantProvisioningService provisioningService,
                                 TenantResourceQuotaService quotaService,
                                 ApplicationEventPublisher eventPublisher) {
    this.monitoringService = monitoringService;
        this.tenantService = tenantService;
        this.provisioningService = provisioningService;
        this.quotaService = quotaService;
        this.eventPublisher = eventPublisher;
    }

    @PostConstruct
    public void initializeAlerting() {
        log.info("Initializing multi-tenant alerting system");
        
        // Setup default alert rules
        setupDefaultAlertRules();
        
        // Start alert monitoring
        startAlertMonitoring();
        
        log.info("Multi-tenant alerting system initialized successfully");
    }

    /**
     * Create a new alert rule
     */
    public String createAlertRule(AlertRuleDefinition definition) {
        String ruleId = UUID.randomUUID().toString();
        
        AlertRule rule = new AlertRule(ruleId, definition);
        alertRules.put(ruleId, rule);
        
        log.info("Created alert rule: ruleId={}, name={}, condition={}", 
                ruleId, definition.getName(), definition.getCondition());
        
        return ruleId;
    }

    /**
     * Update an existing alert rule
     */
    public void updateAlertRule(String ruleId, AlertRuleDefinition definition) {
        AlertRule existingRule = alertRules.get(ruleId);
        if (existingRule != null) {
            existingRule.updateDefinition(definition);
            log.info("Updated alert rule: ruleId={}, name={}", ruleId, definition.getName());
        } else {
            throw new IllegalArgumentException("Alert rule not found: " + ruleId);
        }
    }

    /**
     * Delete an alert rule
     */
    public void deleteAlertRule(String ruleId) {
        AlertRule rule = alertRules.remove(ruleId);
        if (rule != null) {
            // Resolve any active alerts for this rule
            resolveAlertsForRule(ruleId);
            log.info("Deleted alert rule: ruleId={}", ruleId);
        }
    }

    /**
     * Trigger an alert manually
     */
    public String triggerAlert(String alertType, String message, AlertSeverity severity, 
                              Map<String, Object> context) {
        String alertId = UUID.randomUUID().toString();
        
        ActiveAlert alert = new ActiveAlert();
        alert.setAlertId(alertId);
        alert.setAlertType(alertType);
        alert.setMessage(message);
        alert.setSeverity(severity);
        alert.setContext(context);
        alert.setTriggeredAt(Instant.now());
        alert.setStatus(AlertStatus.ACTIVE);
        
        activeAlerts.put(alertId, alert);
        
        // Send notifications
        sendAlertNotifications(alert);
        
        // Publish alert event
        eventPublisher.publishEvent(new AlertTriggeredEvent(alert));
        
        log.warn("Alert triggered: alertId={}, type={}, severity={}, message={}", 
                alertId, alertType, severity, message);
        
        return alertId;
    }

    /**
     * Resolve an active alert
     */
    public void resolveAlert(String alertId, String resolution) {
        ActiveAlert alert = activeAlerts.get(alertId);
        if (alert != null) {
            alert.setStatus(AlertStatus.RESOLVED);
            alert.setResolvedAt(Instant.now());
            alert.setResolution(resolution);
            
            // Send resolution notifications
            sendResolutionNotifications(alert);
            
            // Publish resolution event
            eventPublisher.publishEvent(new AlertResolvedEvent(alert));
            
            log.info("Alert resolved: alertId={}, resolution={}", alertId, resolution);
        }
    }

    /**
     * Get all active alerts
     */
    public List<ActiveAlert> getActiveAlerts() {
        return activeAlerts.values().stream()
            .filter(alert -> alert.getStatus() == AlertStatus.ACTIVE)
            .sorted(Comparator.comparing(ActiveAlert::getTriggeredAt).reversed())
            .toList();
    }

    /**
     * Get alerts by severity
     */
    public List<ActiveAlert> getAlertsBySeverity(AlertSeverity severity) {
        return activeAlerts.values().stream()
            .filter(alert -> alert.getSeverity() == severity && alert.getStatus() == AlertStatus.ACTIVE)
            .sorted(Comparator.comparing(ActiveAlert::getTriggeredAt).reversed())
            .toList();
    }

    /**
     * Get alert history
     */
    public List<ActiveAlert> getAlertHistory(int limit) {
        return activeAlerts.values().stream()
            .sorted(Comparator.comparing(ActiveAlert::getTriggeredAt).reversed())
            .limit(limit)
            .toList();
    }

    /**
     * Add notification channel
     */
    public void addNotificationChannel(AlertNotificationChannel channel) {
        notificationChannels.add(channel);
        log.info("Added notification channel: type={}, name={}", 
                channel.getType(), channel.getName());
    }

    /**
     * Remove notification channel
     */
    public void removeNotificationChannel(String channelId) {
        notificationChannels.removeIf(channel -> channelId.equals(channel.getId()));
        log.info("Removed notification channel: channelId={}", channelId);
    }

    /**
     * Get alert statistics
     */
    public AlertStatistics getAlertStatistics() {
        AlertStatistics stats = new AlertStatistics();
        stats.setGeneratedAt(LocalDateTime.now());
        
        // Count alerts by status
        long activeCount = activeAlerts.values().stream()
            .filter(alert -> alert.getStatus() == AlertStatus.ACTIVE).count();
        long resolvedCount = activeAlerts.values().stream()
            .filter(alert -> alert.getStatus() == AlertStatus.RESOLVED).count();
        
        stats.setActiveAlerts((int) activeCount);
        stats.setResolvedAlerts((int) resolvedCount);
        stats.setTotalAlerts(activeAlerts.size());
        
        // Count by severity
        Map<AlertSeverity, Long> severityCount = activeAlerts.values().stream()
            .filter(alert -> alert.getStatus() == AlertStatus.ACTIVE)
            .collect(Collectors.groupingBy(ActiveAlert::getSeverity, Collectors.counting()));
        
        stats.setCriticalAlerts(severityCount.getOrDefault(AlertSeverity.CRITICAL, 0L).intValue());
        stats.setWarningAlerts(severityCount.getOrDefault(AlertSeverity.WARNING, 0L).intValue());
        stats.setInfoAlerts(severityCount.getOrDefault(AlertSeverity.INFO, 0L).intValue());
        
        // Calculate alert trends
        stats.setAlertsLast24Hours(getAlertsInLastPeriod(24 * 60));
        stats.setAlertsLastHour(getAlertsInLastPeriod(60));
        
        return stats;
    }

    /**
     * Create tenant-specific alert
     */
    public String createAlert(UUID tenantId, String alertType, String severity, String message) {
        Map<String, Object> context = new HashMap<>();
        context.put("tenant_id", tenantId.toString());
        
        AlertSeverity alertSeverity;
        try {
            alertSeverity = AlertSeverity.valueOf(severity.toUpperCase());
        } catch (IllegalArgumentException e) {
            alertSeverity = AlertSeverity.INFO;
        }
        
        return triggerAlert(alertType, message, alertSeverity, context);
    }

    /**
     * Event listeners for tenant lifecycle events
     */
    @EventListener
    public void handleTenantProvisioningSuccess(TenantProvisioningService.TenantProvisionedEvent event) {
        log.info("Tenant provisioning completed successfully: {}", event.getTenantId());
        
        Map<String, Object> context = new HashMap<>();
        context.put("tenant_id", event.getTenantId().toString());
        context.put("provisioning_time", event.getProvisioningTimeMs());
        context.put("tier", event.getTier());
        
        triggerAlert("TENANT_PROVISIONED", 
                    String.format("Tenant %s provisioned successfully in %dms", 
                                event.getTenantId(), event.getProvisioningTimeMs()),
                    AlertSeverity.INFO, context);
    }

    @EventListener
    public void handleTenantProvisioningFailure(TenantProvisioningService.TenantProvisioningFailedEvent event) {
        log.error("Tenant provisioning failed: {}", event.getTenantId());
        
        Map<String, Object> context = new HashMap<>();
        context.put("tenant_id", event.getTenantId().toString());
        context.put("error", event.getError());
        context.put("provisioning_time", event.getProvisioningTimeMs());
        
        triggerAlert("TENANT_PROVISIONING_FAILED",
                    String.format("Tenant %s provisioning failed: %s", 
                                event.getTenantId(), event.getError()),
                    AlertSeverity.CRITICAL, context);
    }

    @EventListener
    public void handleQuotaViolation(TenantResourceQuotaService.QuotaViolationEvent event) {
        log.warn("Quota violation detected for tenant {}: {} usage at {}%", 
                event.getTenantId(), event.getResourceType(), event.getUsagePercentage());
        
        Map<String, Object> context = new HashMap<>();
        context.put("tenant_id", event.getTenantId().toString());
        context.put("resource_type", event.getResourceType());
        context.put("usage_percentage", event.getUsagePercentage());
        context.put("quota_limit", event.getQuotaLimit());
        context.put("current_usage", event.getCurrentUsage());
        
        AlertSeverity severity = event.getUsagePercentage() > 95 ? AlertSeverity.CRITICAL : AlertSeverity.WARNING;
        
        triggerAlert("QUOTA_VIOLATION",
                    String.format("Tenant %s exceeded %s quota: %.1f%% usage", 
                                event.getTenantId(), event.getResourceType(), event.getUsagePercentage()),
                    severity, context);
    }

    @EventListener
    public void handleTenantHealthDegradation(MultiTenantMonitoringService.TenantHealthEvent event) {
        if (event.getHealthScore() < 70.0) {
            log.warn("Tenant health degradation detected: {} (score: {})", 
                    event.getTenantId(), event.getHealthScore());
            
            Map<String, Object> context = new HashMap<>();
            context.put("tenant_id", event.getTenantId().toString());
            context.put("health_score", event.getHealthScore());
            context.put("previous_score", event.getPreviousHealthScore());
            
            AlertSeverity severity = event.getHealthScore() < 50.0 ? AlertSeverity.CRITICAL : AlertSeverity.WARNING;
            
            triggerAlert("TENANT_HEALTH_DEGRADATION",
                        String.format("Tenant %s health degraded to %.1f (was %.1f)", 
                                    event.getTenantId(), event.getHealthScore(), event.getPreviousHealthScore()),
                        severity, context);
        }
    }

    /**
     * Setup default alert rules for multi-tenant system
     */
    private void setupDefaultAlertRules() {
        // System health alert
        AlertRuleDefinition systemHealthRule = new AlertRuleDefinition();
        systemHealthRule.setName("System Health Critical");
        systemHealthRule.setDescription("Alert when overall system health drops below 70%");
        systemHealthRule.setCondition("system.health.score < 70");
        systemHealthRule.setSeverity(AlertSeverity.CRITICAL);
        systemHealthRule.setEvaluationInterval(60); // 1 minute
        systemHealthRule.setEnabled(true);
        createAlertRule(systemHealthRule);

        // High tenant quota usage alert
        AlertRuleDefinition quotaRule = new AlertRuleDefinition();
        quotaRule.setName("Tenant Quota High Usage");
        quotaRule.setDescription("Alert when tenant quota usage exceeds 90%");
        quotaRule.setCondition("tenant.quota.usage > 90");
        quotaRule.setSeverity(AlertSeverity.WARNING);
        quotaRule.setEvaluationInterval(300); // 5 minutes
        quotaRule.setEnabled(true);
        createAlertRule(quotaRule);

        // API response time alert
        AlertRuleDefinition apiResponseRule = new AlertRuleDefinition();
        apiResponseRule.setName("API Response Time High");
        apiResponseRule.setDescription("Alert when API response time exceeds 5 seconds");
        apiResponseRule.setCondition("api.response.time.avg > 5000");
        apiResponseRule.setSeverity(AlertSeverity.WARNING);
        apiResponseRule.setEvaluationInterval(120); // 2 minutes
        apiResponseRule.setEnabled(true);
        createAlertRule(apiResponseRule);

        // Tenant provisioning failure alert
        AlertRuleDefinition provisioningFailureRule = new AlertRuleDefinition();
        provisioningFailureRule.setName("Tenant Provisioning Failure");
        provisioningFailureRule.setDescription("Alert on tenant provisioning failures");
        provisioningFailureRule.setCondition("tenant.provisioning.failure");
        provisioningFailureRule.setSeverity(AlertSeverity.CRITICAL);
        provisioningFailureRule.setEvaluationInterval(60); // 1 minute
        provisioningFailureRule.setEnabled(true);
        createAlertRule(provisioningFailureRule);

        // Database connectivity alert
        AlertRuleDefinition dbConnectivityRule = new AlertRuleDefinition();
        dbConnectivityRule.setName("Database Connectivity Issue");
        dbConnectivityRule.setDescription("Alert on database connectivity problems");
        dbConnectivityRule.setCondition("database.health < 50");
        dbConnectivityRule.setSeverity(AlertSeverity.CRITICAL);
        dbConnectivityRule.setEvaluationInterval(30); // 30 seconds
        dbConnectivityRule.setEnabled(true);
        createAlertRule(dbConnectivityRule);

        log.info("Setup {} default alert rules", alertRules.size());
    }

    /**
     * Start periodic alert monitoring
     */
    private void startAlertMonitoring() {
        // Evaluate alert rules every minute
        scheduler.scheduleAtFixedRate(this::evaluateAlertRules, 0, 1, TimeUnit.MINUTES);
        
        // Check for alert escalations every 5 minutes
        scheduler.scheduleAtFixedRate(this::checkAlertEscalations, 0, 5, TimeUnit.MINUTES);
        
        // Cleanup resolved alerts older than 7 days
        scheduler.scheduleAtFixedRate(this::cleanupOldAlerts, 0, 24, TimeUnit.HOURS);
        
        log.info("Started alert monitoring tasks");
    }

    /**
     * Evaluate all active alert rules
     */
    private void evaluateAlertRules() {
        try {
            for (AlertRule rule : alertRules.values()) {
                if (rule.isEnabled()) {
                    evaluateAlertRule(rule);
                }
            }
        } catch (Exception e) {
            log.error("Error evaluating alert rules", e);
        }
    }

    /**
     * Evaluate a specific alert rule
     */
    private void evaluateAlertRule(AlertRule rule) {
        try {
            boolean conditionMet = evaluateCondition(rule.getDefinition().getCondition());
            
            if (conditionMet) {
                String existingAlertId = findActiveAlertForRule(rule.getRuleId());
                
                if (existingAlertId == null) {
                    // Trigger new alert
                    Map<String, Object> context = new HashMap<>();
                    context.put("rule_id", rule.getRuleId());
                    context.put("condition", rule.getDefinition().getCondition());
                    
                    triggerAlert(rule.getDefinition().getName(), 
                               rule.getDefinition().getDescription(),
                               rule.getDefinition().getSeverity(),
                               context);
                } else {
                    // Update existing alert
                    updateAlertTimestamp(existingAlertId);
                }
            } else {
                // Check if we should auto-resolve
                String existingAlertId = findActiveAlertForRule(rule.getRuleId());
                if (existingAlertId != null && rule.getDefinition().isAutoResolve()) {
                    resolveAlert(existingAlertId, "Condition no longer met - auto-resolved");
                }
            }
            
        } catch (Exception e) {
            log.error("Error evaluating alert rule: {}", rule.getRuleId(), e);
        }
    }

    /**
     * Evaluate alert condition based on current metrics
     */
    private boolean evaluateCondition(String condition) {
        try {
            // Simplified condition evaluation - would use expression parser in production
            if (condition.contains("system.health.score")) {
                var healthStatus = monitoringService.getSystemHealthStatus();
                double healthScore = healthStatus.getOverallHealthScore();
                
                if (condition.contains("< 70")) {
                    return healthScore < 70;
                }
            }
            
            if (condition.contains("api.response.time.avg")) {
                var aggregatedMetrics = monitoringService.getAggregatedMetrics();
                double avgResponseTime = aggregatedMetrics.getAverageAPIResponseTime();
                
                if (condition.contains("> 5000")) {
                    return avgResponseTime > 5000;
                }
            }
            
            if (condition.contains("database.health")) {
                var healthStatus = monitoringService.getSystemHealthStatus();
                double dbHealth = healthStatus.getDatabaseHealth();
                
                if (condition.contains("< 50")) {
                    return dbHealth < 50;
                }
            }
            
            // Default to false for unknown conditions
            return false;
            
        } catch (Exception e) {
            log.error("Error evaluating condition: {}", condition, e);
            return false;
        }
    }

    /**
     * Check for alert escalations
     */
    private void checkAlertEscalations() {
        try {
            Instant escalationThreshold = Instant.now().minusSeconds(3600); // 1 hour
            
            for (ActiveAlert alert : activeAlerts.values()) {
                if (alert.getStatus() == AlertStatus.ACTIVE && 
                    alert.getTriggeredAt().isBefore(escalationThreshold) &&
                    !alert.isEscalated()) {
                    
                    escalateAlert(alert);
                }
            }
        } catch (Exception e) {
            log.error("Error checking alert escalations", e);
        }
    }

    /**
     * Escalate an alert to higher severity or additional channels
     */
    private void escalateAlert(ActiveAlert alert) {
        alert.setEscalated(true);
        alert.setEscalatedAt(Instant.now());
        
        // Escalate severity if possible
        AlertSeverity currentSeverity = alert.getSeverity();
        if (currentSeverity == AlertSeverity.WARNING) {
            alert.setSeverity(AlertSeverity.CRITICAL);
        }
        
        // Send escalation notifications
        sendEscalationNotifications(alert);
        
        log.warn("Alert escalated: alertId={}, originalSeverity={}, newSeverity={}", 
                alert.getAlertId(), currentSeverity, alert.getSeverity());
    }

    /**
     * Cleanup old resolved alerts
     */
    private void cleanupOldAlerts() {
        try {
            Instant cutoff = Instant.now().minusSeconds(7 * 24 * 3600); // 7 days
            
            activeAlerts.entrySet().removeIf(entry -> {
                ActiveAlert alert = entry.getValue();
                return alert.getStatus() == AlertStatus.RESOLVED && 
                       alert.getResolvedAt() != null && 
                       alert.getResolvedAt().isBefore(cutoff);
            });
            
            log.debug("Cleaned up old resolved alerts");
            
        } catch (Exception e) {
            log.error("Error cleaning up old alerts", e);
        }
    }

    /**
     * Send alert notifications through configured channels
     */
    private void sendAlertNotifications(ActiveAlert alert) {
        for (AlertNotificationChannel channel : notificationChannels) {
            if (channel.shouldNotify(alert)) {
                try {
                    channel.sendNotification(alert);
                } catch (Exception e) {
                    log.error("Error sending alert notification through channel {}: {}", 
                            channel.getName(), e.getMessage());
                }
            }
        }
    }

    /**
     * Send resolution notifications
     */
    private void sendResolutionNotifications(ActiveAlert alert) {
        for (AlertNotificationChannel channel : notificationChannels) {
            if (channel.shouldNotify(alert)) {
                try {
                    channel.sendResolutionNotification(alert);
                } catch (Exception e) {
                    log.error("Error sending resolution notification through channel {}: {}", 
                            channel.getName(), e.getMessage());
                }
            }
        }
    }

    /**
     * Send escalation notifications
     */
    private void sendEscalationNotifications(ActiveAlert alert) {
        for (AlertNotificationChannel channel : notificationChannels) {
            if (channel.shouldNotify(alert)) {
                try {
                    channel.sendEscalationNotification(alert);
                } catch (Exception e) {
                    log.error("Error sending escalation notification through channel {}: {}", 
                            channel.getName(), e.getMessage());
                }
            }
        }
    }

    // Helper methods
    private void resolveAlertsForRule(String ruleId) {
        activeAlerts.values().stream()
            .filter(alert -> alert.getStatus() == AlertStatus.ACTIVE)
            .filter(alert -> ruleId.equals(alert.getContext().get("rule_id")))
            .forEach(alert -> resolveAlert(alert.getAlertId(), "Alert rule deleted"));
    }

    private String findActiveAlertForRule(String ruleId) {
        return activeAlerts.values().stream()
            .filter(alert -> alert.getStatus() == AlertStatus.ACTIVE)
            .filter(alert -> ruleId.equals(alert.getContext().get("rule_id")))
            .map(ActiveAlert::getAlertId)
            .findFirst()
            .orElse(null);
    }

    private void updateAlertTimestamp(String alertId) {
        ActiveAlert alert = activeAlerts.get(alertId);
        if (alert != null) {
            alert.setLastTriggered(Instant.now());
        }
    }

    private int getAlertsInLastPeriod(int minutes) {
        Instant cutoff = Instant.now().minusSeconds(minutes * 60L);
        return (int) activeAlerts.values().stream()
            .filter(alert -> alert.getTriggeredAt().isAfter(cutoff))
            .count();
    }

    // Data classes
    public static class AlertRule {
        private String ruleId;
        private AlertRuleDefinition definition;
        private Instant createdAt;
        private Instant updatedAt;

        public AlertRule(String ruleId, AlertRuleDefinition definition) {
            this.ruleId = ruleId;
            this.definition = definition;
            this.createdAt = Instant.now();
            this.updatedAt = Instant.now();
        }

        public void updateDefinition(AlertRuleDefinition newDefinition) {
            this.definition = newDefinition;
            this.updatedAt = Instant.now();
        }

        public boolean isEnabled() {
            return definition.isEnabled();
        }

        // Getters and setters
        public String getRuleId() { return ruleId; }
        public void setRuleId(String ruleId) { this.ruleId = ruleId; }

        public AlertRuleDefinition getDefinition() { return definition; }
        public void setDefinition(AlertRuleDefinition definition) { this.definition = definition; }

        public Instant getCreatedAt() { return createdAt; }
        public void setCreatedAt(Instant createdAt) { this.createdAt = createdAt; }

        public Instant getUpdatedAt() { return updatedAt; }
        public void setUpdatedAt(Instant updatedAt) { this.updatedAt = updatedAt; }
    }

    public static class AlertRuleDefinition {
        private String name;
        private String description;
        private String condition;
        private AlertSeverity severity;
        private int evaluationInterval = 60; // seconds
        private boolean enabled = true;
        private boolean autoResolve = true;
        private Map<String, Object> metadata = new HashMap<>();

        // Getters and setters
        public String getName() { return name; }
        public void setName(String name) { this.name = name; }

        public String getDescription() { return description; }
        public void setDescription(String description) { this.description = description; }

        public String getCondition() { return condition; }
        public void setCondition(String condition) { this.condition = condition; }

        public AlertSeverity getSeverity() { return severity; }
        public void setSeverity(AlertSeverity severity) { this.severity = severity; }

        public int getEvaluationInterval() { return evaluationInterval; }
        public void setEvaluationInterval(int evaluationInterval) { this.evaluationInterval = evaluationInterval; }

        public boolean isEnabled() { return enabled; }
        public void setEnabled(boolean enabled) { this.enabled = enabled; }

        public boolean isAutoResolve() { return autoResolve; }
        public void setAutoResolve(boolean autoResolve) { this.autoResolve = autoResolve; }

        public Map<String, Object> getMetadata() { return metadata; }
        public void setMetadata(Map<String, Object> metadata) { this.metadata = metadata; }
    }

    public static class ActiveAlert {
        private String alertId;
        private String alertType;
        private String message;
        private AlertSeverity severity;
        private AlertStatus status;
        private Map<String, Object> context;
        private Instant triggeredAt;
        private Instant lastTriggered;
        private Instant resolvedAt;
        private String resolution;
        private boolean escalated = false;
        private Instant escalatedAt;

        // Getters and setters
        public String getAlertId() { return alertId; }
        public void setAlertId(String alertId) { this.alertId = alertId; }

        public String getAlertType() { return alertType; }
        public void setAlertType(String alertType) { this.alertType = alertType; }

        public String getMessage() { return message; }
        public void setMessage(String message) { this.message = message; }

        public AlertSeverity getSeverity() { return severity; }
        public void setSeverity(AlertSeverity severity) { this.severity = severity; }

        public AlertStatus getStatus() { return status; }
        public void setStatus(AlertStatus status) { this.status = status; }

        public Map<String, Object> getContext() { return context; }
        public void setContext(Map<String, Object> context) { this.context = context; }

        public Instant getTriggeredAt() { return triggeredAt; }
        public void setTriggeredAt(Instant triggeredAt) { this.triggeredAt = triggeredAt; }

        public Instant getLastTriggered() { return lastTriggered; }
        public void setLastTriggered(Instant lastTriggered) { this.lastTriggered = lastTriggered; }

        public Instant getResolvedAt() { return resolvedAt; }
        public void setResolvedAt(Instant resolvedAt) { this.resolvedAt = resolvedAt; }

        public String getResolution() { return resolution; }
        public void setResolution(String resolution) { this.resolution = resolution; }

        public boolean isEscalated() { return escalated; }
        public void setEscalated(boolean escalated) { this.escalated = escalated; }

        public Instant getEscalatedAt() { return escalatedAt; }
        public void setEscalatedAt(Instant escalatedAt) { this.escalatedAt = escalatedAt; }
    }

    public enum AlertSeverity {
        INFO, WARNING, CRITICAL
    }

    public enum AlertStatus {
        ACTIVE, RESOLVED, SUPPRESSED
    }

    public static class AlertStatistics {
        private LocalDateTime generatedAt;
        private int totalAlerts;
        private int activeAlerts;
        private int resolvedAlerts;
        private int criticalAlerts;
        private int warningAlerts;
        private int infoAlerts;
        private int alertsLast24Hours;
        private int alertsLastHour;

        // Getters and setters
        public LocalDateTime getGeneratedAt() { return generatedAt; }
        public void setGeneratedAt(LocalDateTime generatedAt) { this.generatedAt = generatedAt; }

        public int getTotalAlerts() { return totalAlerts; }
        public void setTotalAlerts(int totalAlerts) { this.totalAlerts = totalAlerts; }

        public int getActiveAlerts() { return activeAlerts; }
        public void setActiveAlerts(int activeAlerts) { this.activeAlerts = activeAlerts; }

        public int getResolvedAlerts() { return resolvedAlerts; }
        public void setResolvedAlerts(int resolvedAlerts) { this.resolvedAlerts = resolvedAlerts; }

        public int getCriticalAlerts() { return criticalAlerts; }
        public void setCriticalAlerts(int criticalAlerts) { this.criticalAlerts = criticalAlerts; }

        public int getWarningAlerts() { return warningAlerts; }
        public void setWarningAlerts(int warningAlerts) { this.warningAlerts = warningAlerts; }

        public int getInfoAlerts() { return infoAlerts; }
        public void setInfoAlerts(int infoAlerts) { this.infoAlerts = infoAlerts; }

        public int getAlertsLast24Hours() { return alertsLast24Hours; }
        public void setAlertsLast24Hours(int alertsLast24Hours) { this.alertsLast24Hours = alertsLast24Hours; }

        public int getAlertsLastHour() { return alertsLastHour; }
        public void setAlertsLastHour(int alertsLastHour) { this.alertsLastHour = alertsLastHour; }
    }

    // Notification channel interface
    public interface AlertNotificationChannel {
        String getId();
        String getName();
        String getType();
        boolean shouldNotify(ActiveAlert alert);
        void sendNotification(ActiveAlert alert);
        void sendResolutionNotification(ActiveAlert alert);
        void sendEscalationNotification(ActiveAlert alert);
    }

    // Event classes for Spring Events
    public static class AlertTriggeredEvent {
        private final ActiveAlert alert;

        public AlertTriggeredEvent(ActiveAlert alert) {
            this.alert = alert;
        }

        public ActiveAlert getAlert() {
            return alert;
        }
    }

    public static class AlertResolvedEvent {
        private final ActiveAlert alert;

        public AlertResolvedEvent(ActiveAlert alert) {
            this.alert = alert;
        }

        public ActiveAlert getAlert() {
            return alert;
        }
    }
}
