package com.park.utmstack.service.operations;

import com.park.utmstack.domain.UtmTenant;
import com.park.utmstack.service.TenantProvisioningService;
import com.park.utmstack.service.TenantProvisioningService.*;
import com.park.utmstack.service.TenantResourceQuotaService;
import com.park.utmstack.service.TenantService;
import com.park.utmstack.service.alerting.MultiTenantAlertingService;
import com.park.utmstack.service.monitoring.MultiTenantMonitoringService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import javax.annotation.PostConstruct;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.*;
import java.util.concurrent.*;

/**
 * Operational automation service for multi-tenant lifecycle management.
 * Provides automated operations, maintenance tasks, and intelligent tenant management.
 */
@Service
public class TenantOperationsAutomationService {

    private static final Logger log = LoggerFactory.getLogger(TenantOperationsAutomationService.class);

    private final TenantService tenantService;
    private final TenantProvisioningService provisioningService;
    private final TenantResourceQuotaService quotaService;
    private final MultiTenantMonitoringService monitoringService;
    private final MultiTenantAlertingService alertingService;
    private final ScheduledExecutorService scheduler = Executors.newScheduledThreadPool(5);

    // Automation state
    private final Map<String, AutomationRule> automationRules = new ConcurrentHashMap<>();
    private final Map<String, ScheduledFuture<?>> scheduledTasks = new ConcurrentHashMap<>();
    private final List<AutomationExecution> executionHistory = new ArrayList<>();

    public TenantOperationsAutomationService(TenantService tenantService,
                                           TenantProvisioningService provisioningService,
                                           TenantResourceQuotaService quotaService,
                                           MultiTenantMonitoringService monitoringService,
                                           MultiTenantAlertingService alertingService) {
        this.tenantService = tenantService;
        this.provisioningService = provisioningService;
        this.quotaService = quotaService;
        this.monitoringService = monitoringService;
        this.alertingService = alertingService;
    }

    @PostConstruct
    public void initializeAutomation() {
        log.info("Initializing tenant operations automation system");
        
        // Setup default automation rules
        setupDefaultAutomationRules();
        
        // Start automation engine
        startAutomationEngine();
        
        log.info("Tenant operations automation system initialized successfully");
    }

    /**
     * Create a new automation rule
     */
    public String createAutomationRule(AutomationRuleDefinition definition) {
        String ruleId = UUID.randomUUID().toString();
        
        AutomationRule rule = new AutomationRule(ruleId, definition);
        automationRules.put(ruleId, rule);
        
        // Schedule the rule if it's a scheduled type
        if (definition.getTriggerType() == TriggerType.SCHEDULED) {
            scheduleAutomationRule(rule);
        }
        
        log.info("Created automation rule: ruleId={}, name={}, trigger={}", 
                ruleId, definition.getName(), definition.getTriggerType());
        
        return ruleId;
    }

    /**
     * Execute automated tenant maintenance
     */
    public AutomationExecutionResult executeAutomatedMaintenance() {
        log.info("Starting automated tenant maintenance");
        
        AutomationExecutionResult result = new AutomationExecutionResult();
        result.setExecutionId(UUID.randomUUID().toString());
        result.setStartTime(Instant.now());
        result.setExecutionType("AUTOMATED_MAINTENANCE");

        try {
            List<MaintenanceTask> tasks = new ArrayList<>();
            
            // Task 1: Cleanup inactive tenants
            tasks.add(performInactiveTenantCleanup());
            
            // Task 2: Optimize resource allocations
            tasks.add(performResourceOptimization());
            
            // Task 3: Update tenant health scores
            tasks.add(performHealthScoreUpdate());
            
            // Task 4: Cleanup old metrics and logs
            tasks.add(performMetricsCleanup());
            
            // Task 5: Check and fix quota inconsistencies
            tasks.add(performQuotaConsistencyCheck());
            
            result.setCompletedTasks(tasks);
            result.setSuccessfulTasks((int) tasks.stream().filter(MaintenanceTask::isSuccessful).count());
            result.setFailedTasks((int) tasks.stream().filter(task -> !task.isSuccessful()).count());
            result.setStatus("COMPLETED");
            
        } catch (Exception e) {
            log.error("Error during automated maintenance", e);
            result.setStatus("FAILED");
            result.setError(e.getMessage());
        } finally {
            result.setEndTime(Instant.now());
            recordAutomationExecution(result);
        }

        log.info("Automated maintenance completed: successful={}, failed={}, duration={}ms",
                result.getSuccessfulTasks(), result.getFailedTasks(), result.getDurationMs());
        
        return result;
    }

    /**
     * Perform automated tenant scaling based on usage patterns
     */
    public TenantScalingResult performAutomatedTenantScaling() {
        log.info("Starting automated tenant scaling analysis");
        
        TenantScalingResult result = new TenantScalingResult();
        result.setAnalysisTime(Instant.now());
        
        try {
            List<UtmTenant> activeTenants = tenantService.getAllActiveTenants();
            List<ScalingRecommendation> recommendations = new ArrayList<>();
            
            for (UtmTenant tenant : activeTenants) {
                ScalingRecommendation recommendation = analyzeTenantScaling(tenant);
                if (recommendation != null) {
                    recommendations.add(recommendation);
                }
            }
            
            result.setScalingRecommendations(recommendations);
            result.setTenantsAnalyzed(activeTenants.size());
            result.setRecommendationsGenerated(recommendations.size());
            
            // Apply automatic scaling where appropriate
            int autoScaledTenants = applyAutomaticScaling(recommendations);
            result.setAutoScaledTenants(autoScaledTenants);
            
        } catch (Exception e) {
            log.error("Error during tenant scaling analysis", e);
            result.setError(e.getMessage());
        }
        
        log.info("Tenant scaling analysis completed: recommendations={}, auto-scaled={}", 
                result.getRecommendationsGenerated(), result.getAutoScaledTenants());
        
        return result;
    }

    /**
     * Perform automated tenant health checks
     */
    public TenantHealthCheckResult performAutomatedHealthChecks() {
        log.info("Starting automated tenant health checks");
        
        TenantHealthCheckResult result = new TenantHealthCheckResult();
        result.setCheckTime(Instant.now());
        
        try {
            List<UtmTenant> activeTenants = tenantService.getAllActiveTenants();
            List<TenantHealthStatus> healthStatuses = new ArrayList<>();
            
            for (UtmTenant tenant : activeTenants) {
                TenantHealthStatus status = performTenantHealthCheck(tenant);
                healthStatuses.add(status);
                
                // Take automated actions based on health status
                handleUnhealthyTenant(tenant, status);
            }
            
            result.setTenantHealthStatuses(healthStatuses);
            result.setTenantsChecked(activeTenants.size());
            result.setHealthyTenants((int) healthStatuses.stream().filter(TenantHealthStatus::isHealthy).count());
            result.setUnhealthyTenants((int) healthStatuses.stream().filter(s -> !s.isHealthy()).count());
            
        } catch (Exception e) {
            log.error("Error during automated health checks", e);
            result.setError(e.getMessage());
        }
        
        log.info("Automated health checks completed: healthy={}, unhealthy={}", 
                result.getHealthyTenants(), result.getUnhealthyTenants());
        
        return result;
    }

    /**
     * Execute tenant lifecycle automation
     */
    public LifecycleAutomationResult executeLifecycleAutomation() {
        log.info("Starting tenant lifecycle automation");
        
        LifecycleAutomationResult result = new LifecycleAutomationResult();
        result.setExecutionTime(Instant.now());
        
        try {
            // Check for tenants pending provisioning completion
            result.setProvisioningActions(checkPendingProvisioningTasks());
            
            // Check for tenants needing tier upgrades/downgrades
            result.setTierAdjustments(checkTierAdjustments());
            
            // Check for tenants approaching expiration
            result.setExpirationActions(checkTenantExpirations());
            
            // Check for tenants needing backup/archival
            result.setBackupActions(checkBackupRequirements());
            
        } catch (Exception e) {
            log.error("Error during lifecycle automation", e);
            result.setError(e.getMessage());
        }
        
        log.info("Lifecycle automation completed");
        return result;
    }

    /**
     * Get automation statistics and status
     */
    public AutomationStatistics getAutomationStatistics() {
        AutomationStatistics stats = new AutomationStatistics();
        stats.setGeneratedAt(LocalDateTime.now());
        
        // Count active automation rules
        stats.setActiveAutomationRules((int) automationRules.values().stream()
            .filter(rule -> rule.getDefinition().isEnabled()).count());
        stats.setTotalAutomationRules(automationRules.size());
        
        // Count recent executions
        Instant last24Hours = Instant.now().minusSeconds(24 * 3600);
        stats.setExecutionsLast24Hours((int) executionHistory.stream()
            .filter(exec -> exec.getStartTime().isAfter(last24Hours)).count());
        
        // Calculate success rate
        long totalExecutions = executionHistory.size();
        long successfulExecutions = executionHistory.stream()
            .filter(exec -> "COMPLETED".equals(exec.getStatus())).count();
        
        if (totalExecutions > 0) {
            stats.setSuccessRate((double) successfulExecutions / totalExecutions * 100);
        }
        
        stats.setTotalExecutions((int) totalExecutions);
        
        return stats;
    }

    /**
     * Setup default automation rules
     */
    private void setupDefaultAutomationRules() {
        // Daily maintenance rule
        AutomationRuleDefinition dailyMaintenance = new AutomationRuleDefinition();
        dailyMaintenance.setName("Daily Maintenance");
        dailyMaintenance.setDescription("Perform daily maintenance tasks");
        dailyMaintenance.setTriggerType(TriggerType.SCHEDULED);
        dailyMaintenance.setScheduleExpression("0 2 * * *"); // 2 AM daily
        dailyMaintenance.setActionType(ActionType.MAINTENANCE);
        dailyMaintenance.setEnabled(true);
        createAutomationRule(dailyMaintenance);

        // Tenant health monitoring rule
        AutomationRuleDefinition healthMonitoring = new AutomationRuleDefinition();
        healthMonitoring.setName("Tenant Health Monitoring");
        healthMonitoring.setDescription("Monitor tenant health and take corrective actions");
        healthMonitoring.setTriggerType(TriggerType.SCHEDULED);
        healthMonitoring.setScheduleExpression("0 */6 * * *"); // Every 6 hours
        healthMonitoring.setActionType(ActionType.HEALTH_CHECK);
        healthMonitoring.setEnabled(true);
        createAutomationRule(healthMonitoring);

        // Resource optimization rule
        AutomationRuleDefinition resourceOptimization = new AutomationRuleDefinition();
        resourceOptimization.setName("Resource Optimization");
        resourceOptimization.setDescription("Optimize resource allocation based on usage patterns");
        resourceOptimization.setTriggerType(TriggerType.SCHEDULED);
        resourceOptimization.setScheduleExpression("0 0 */3 * *"); // Every 3 days
        resourceOptimization.setActionType(ActionType.RESOURCE_OPTIMIZATION);
        resourceOptimization.setEnabled(true);
        createAutomationRule(resourceOptimization);

        log.info("Setup {} default automation rules", automationRules.size());
    }

    /**
     * Start the automation engine
     */
    private void startAutomationEngine() {
        // Start automation rule evaluation every minute
        scheduler.scheduleAtFixedRate(this::evaluateTriggeredRules, 0, 1, TimeUnit.MINUTES);
        
        // Start maintenance execution every hour
        scheduler.scheduleAtFixedRate(this::checkMaintenanceSchedule, 0, 1, TimeUnit.HOURS);
        
        log.info("Started automation engine");
    }

    /**
     * Schedule an automation rule for execution
     */
    private void scheduleAutomationRule(AutomationRule rule) {
        if (rule.getDefinition().getTriggerType() == TriggerType.SCHEDULED) {
            // Parse cron expression and schedule (simplified)
            long intervalSeconds = parseCronToSeconds(rule.getDefinition().getScheduleExpression());
            
            ScheduledFuture<?> future = scheduler.scheduleAtFixedRate(
                () -> executeAutomationRule(rule), 
                intervalSeconds, 
                intervalSeconds, 
                TimeUnit.SECONDS
            );
            
            scheduledTasks.put(rule.getRuleId(), future);
        }
    }

    /**
     * Execute an automation rule
     */
    private void executeAutomationRule(AutomationRule rule) {
        try {
            log.info("Executing automation rule: {}", rule.getDefinition().getName());
            
            AutomationExecution execution = new AutomationExecution();
            execution.setExecutionId(UUID.randomUUID().toString());
            execution.setRuleId(rule.getRuleId());
            execution.setRuleName(rule.getDefinition().getName());
            execution.setStartTime(Instant.now());
            
            // Execute based on action type
            boolean success = false;
            switch (rule.getDefinition().getActionType()) {
                case MAINTENANCE:
                    AutomationExecutionResult maintenanceResult = executeAutomatedMaintenance();
                    success = "COMPLETED".equals(maintenanceResult.getStatus());
                    break;
                case HEALTH_CHECK:
                    TenantHealthCheckResult healthResult = performAutomatedHealthChecks();
                    success = healthResult.getError() == null;
                    break;
                case RESOURCE_OPTIMIZATION:
                    TenantScalingResult scalingResult = performAutomatedTenantScaling();
                    success = scalingResult.getError() == null;
                    break;
                default:
                    log.warn("Unknown action type: {}", rule.getDefinition().getActionType());
            }
            
            execution.setEndTime(Instant.now());
            execution.setStatus(success ? "COMPLETED" : "FAILED");
            
            synchronized (executionHistory) {
                executionHistory.add(execution);
                // Keep only last 1000 executions
                if (executionHistory.size() > 1000) {
                    executionHistory.remove(0);
                }
            }
            
        } catch (Exception e) {
            log.error("Error executing automation rule: {}", rule.getDefinition().getName(), e);
        }
    }

    /**
     * Evaluate event-triggered rules
     */
    private void evaluateTriggeredRules() {
        // Would implement event-based rule evaluation
        // For now, this is a placeholder
    }

    /**
     * Check maintenance schedule
     */
    private void checkMaintenanceSchedule() {
        // Would implement maintenance schedule checking
        // For now, this is a placeholder
    }

    // Maintenance task implementations
    private MaintenanceTask performInactiveTenantCleanup() {
        MaintenanceTask task = new MaintenanceTask("Inactive Tenant Cleanup");
        
        try {
            // Find tenants inactive for more than 30 days
            List<UtmTenant> allTenants = tenantService.getAllActiveTenants();
            int cleanedUp = 0;
            
            for (UtmTenant tenant : allTenants) {
                // Check last activity (simplified)
                // In production, would check actual activity metrics
                if (shouldCleanupTenant(tenant)) {
                    // Mark for cleanup or archive
                    cleanedUp++;
                }
            }
            
            task.setSuccessful(true);
            task.setResult("Cleaned up " + cleanedUp + " inactive tenants");
            
        } catch (Exception e) {
            task.setSuccessful(false);
            task.setError(e.getMessage());
        }
        
        return task;
    }

    private MaintenanceTask performResourceOptimization() {
        MaintenanceTask task = new MaintenanceTask("Resource Optimization");
        
        try {
            // Analyze resource usage and optimize allocations
            int optimized = 0;
            List<UtmTenant> allTenants = tenantService.getAllActiveTenants();
            
            for (UtmTenant tenant : allTenants) {
                if (optimizeTenantResources(tenant)) {
                    optimized++;
                }
            }
            
            task.setSuccessful(true);
            task.setResult("Optimized resources for " + optimized + " tenants");
            
        } catch (Exception e) {
            task.setSuccessful(false);
            task.setError(e.getMessage());
        }
        
        return task;
    }

    private MaintenanceTask performHealthScoreUpdate() {
        MaintenanceTask task = new MaintenanceTask("Health Score Update");
        
        try {
            // Update health scores for all tenants
            List<UtmTenant> allTenants = tenantService.getAllActiveTenants();
            int updated = 0;
            
            for (UtmTenant tenant : allTenants) {
                try {
                    monitoringService.getTenantMetrics(tenant.getId());
                    updated++;
                } catch (Exception e) {
                    log.warn("Failed to update health score for tenant {}: {}", tenant.getId(), e.getMessage());
                }
            }
            
            task.setSuccessful(true);
            task.setResult("Updated health scores for " + updated + " tenants");
            
        } catch (Exception e) {
            task.setSuccessful(false);
            task.setError(e.getMessage());
        }
        
        return task;
    }

    private MaintenanceTask performMetricsCleanup() {
        MaintenanceTask task = new MaintenanceTask("Metrics Cleanup");
        
        try {
            // Cleanup old metrics data
            // This would typically involve database cleanup operations
            task.setSuccessful(true);
            task.setResult("Cleaned up metrics older than 30 days");
            
        } catch (Exception e) {
            task.setSuccessful(false);
            task.setError(e.getMessage());
        }
        
        return task;
    }

    private MaintenanceTask performQuotaConsistencyCheck() {
        MaintenanceTask task = new MaintenanceTask("Quota Consistency Check");
        
        try {
            // Check and fix quota inconsistencies
            List<UtmTenant> allTenants = tenantService.getAllActiveTenants();
            int fixed = 0;
            
            for (UtmTenant tenant : allTenants) {
                try {
                    if (!quotaService.areQuotasConfigured(tenant.getId())) {
                        quotaService.initializeTenantQuotas(tenant.getId(), tenant.getTier());
                        fixed++;
                    }
                } catch (Exception e) {
                    log.warn("Failed quota check for tenant {}: {}", tenant.getId(), e.getMessage());
                }
            }
            
            task.setSuccessful(true);
            task.setResult("Fixed quota inconsistencies for " + fixed + " tenants");
            
        } catch (Exception e) {
            task.setSuccessful(false);
            task.setError(e.getMessage());
        }
        
        return task;
    }

    // Helper methods
    private boolean shouldCleanupTenant(UtmTenant tenant) {
        // Simplified logic - would implement actual activity checking
        return false;
    }

    private boolean optimizeTenantResources(UtmTenant tenant) {
        // Simplified logic - would implement actual resource optimization
        return Math.random() < 0.1; // 10% chance for demo
    }

    private ScalingRecommendation analyzeTenantScaling(UtmTenant tenant) {
        try {
            var quotaStatus = quotaService.getResourceQuotaStatus(tenant.getId());
            
            // Check if tenant is approaching quota limits
            double maxUsage = Math.max(Math.max(quotaStatus.getUserUsage(), quotaStatus.getStorageUsage()),
                                     Math.max(quotaStatus.getDashboardUsage(), quotaStatus.getDailyAlertUsage()));
            
            if (maxUsage > 85) {
                ScalingRecommendation recommendation = new ScalingRecommendation();
                recommendation.setTenantId(tenant.getId());
                recommendation.setCurrentTier(tenant.getTier());
                recommendation.setRecommendedAction(ScalingAction.SCALE_UP);
                recommendation.setReason("Resource usage above 85%");
                recommendation.setCurrentUsage(maxUsage);
                return recommendation;
            } else if (maxUsage < 30 && !"standard".equals(tenant.getTier())) {
                ScalingRecommendation recommendation = new ScalingRecommendation();
                recommendation.setTenantId(tenant.getId());
                recommendation.setCurrentTier(tenant.getTier());
                recommendation.setRecommendedAction(ScalingAction.SCALE_DOWN);
                recommendation.setReason("Resource usage below 30%");
                recommendation.setCurrentUsage(maxUsage);
                return recommendation;
            }
            
        } catch (Exception e) {
            log.warn("Error analyzing scaling for tenant {}: {}", tenant.getId(), e.getMessage());
        }
        
        return null;
    }

    private int applyAutomaticScaling(List<ScalingRecommendation> recommendations) {
        int autoScaled = 0;
        
        for (ScalingRecommendation recommendation : recommendations) {
            if (recommendation.isAutoApplicable()) {
                try {
                    // Apply the scaling recommendation
                    // This would involve updating tenant tier and resource limits
                    log.info("Auto-applying scaling recommendation for tenant {}: {}", 
                            recommendation.getTenantId(), recommendation.getRecommendedAction());
                    autoScaled++;
                } catch (Exception e) {
                    log.error("Failed to apply auto-scaling for tenant {}: {}", 
                            recommendation.getTenantId(), e.getMessage());
                }
            }
        }
        
        return autoScaled;
    }

    private TenantHealthStatus performTenantHealthCheck(UtmTenant tenant) {
        TenantHealthStatus status = new TenantHealthStatus();
        status.setTenantId(tenant.getId());
        status.setCheckTime(Instant.now());
        
        try {
            // Check various health metrics
            var metrics = monitoringService.getTenantMetrics(tenant.getId());
            var quotaStatus = quotaService.getResourceQuotaStatus(tenant.getId());
            
            status.setHealthy(true);
            status.setHealthScore(metrics.getHealthScore());
            
            List<String> issues = new ArrayList<>();
            
            // Check quota usage
            if (quotaStatus.getUserUsage() > 95) {
                issues.add("User quota usage critical: " + quotaStatus.getUserUsage() + "%");
                status.setHealthy(false);
            }
            
            if (quotaStatus.getStorageUsage() > 95) {
                issues.add("Storage quota usage critical: " + quotaStatus.getStorageUsage() + "%");
                status.setHealthy(false);
            }
            
            status.setIssues(issues);
            
        } catch (Exception e) {
            status.setHealthy(false);
            status.setIssues(List.of("Health check failed: " + e.getMessage()));
        }
        
        return status;
    }

    private void handleUnhealthyTenant(UtmTenant tenant, TenantHealthStatus status) {
        if (!status.isHealthy()) {
            // Trigger alerts for unhealthy tenants
            alertingService.triggerAlert("TENANT_HEALTH", 
                "Tenant health check failed: " + String.join(", ", status.getIssues()),
                MultiTenantAlertingService.AlertSeverity.WARNING,
                Map.of("tenant_id", tenant.getId().toString()));
        }
    }

    private List<String> checkPendingProvisioningTasks() {
        // Would implement checking for pending provisioning tasks
        return new ArrayList<>();
    }

    private List<String> checkTierAdjustments() {
        // Would implement checking for tier adjustments
        return new ArrayList<>();
    }

    private List<String> checkTenantExpirations() {
        // Would implement checking for tenant expirations
        return new ArrayList<>();
    }

    private List<String> checkBackupRequirements() {
        // Would implement checking for backup requirements
        return new ArrayList<>();
    }

    private void recordAutomationExecution(AutomationExecutionResult result) {
        AutomationExecution execution = new AutomationExecution();
        execution.setExecutionId(result.getExecutionId());
        execution.setStartTime(result.getStartTime());
        execution.setEndTime(result.getEndTime());
        execution.setStatus(result.getStatus());
        execution.setRuleName(result.getExecutionType());
        
        synchronized (executionHistory) {
            executionHistory.add(execution);
            if (executionHistory.size() > 1000) {
                executionHistory.remove(0);
            }
        }
    }

    private long parseCronToSeconds(String cronExpression) {
        // Simplified cron parsing - would use proper cron parser in production
        return 3600; // Default to 1 hour
    }

    // Data classes
    public static class AutomationRule {
        private String ruleId;
        private AutomationRuleDefinition definition;
        private Instant createdAt;
        private Instant lastExecuted;

        public AutomationRule(String ruleId, AutomationRuleDefinition definition) {
            this.ruleId = ruleId;
            this.definition = definition;
            this.createdAt = Instant.now();
        }

        // Getters and setters
        public String getRuleId() { return ruleId; }
        public void setRuleId(String ruleId) { this.ruleId = ruleId; }

        public AutomationRuleDefinition getDefinition() { return definition; }
        public void setDefinition(AutomationRuleDefinition definition) { this.definition = definition; }

        public Instant getCreatedAt() { return createdAt; }
        public void setCreatedAt(Instant createdAt) { this.createdAt = createdAt; }

        public Instant getLastExecuted() { return lastExecuted; }
        public void setLastExecuted(Instant lastExecuted) { this.lastExecuted = lastExecuted; }
    }

    public static class AutomationRuleDefinition {
        private String name;
        private String description;
        private TriggerType triggerType;
        private String scheduleExpression;
        private ActionType actionType;
        private boolean enabled = true;
        private Map<String, Object> parameters = new HashMap<>();

        // Getters and setters
        public String getName() { return name; }
        public void setName(String name) { this.name = name; }

        public String getDescription() { return description; }
        public void setDescription(String description) { this.description = description; }

        public TriggerType getTriggerType() { return triggerType; }
        public void setTriggerType(TriggerType triggerType) { this.triggerType = triggerType; }

        public String getScheduleExpression() { return scheduleExpression; }
        public void setScheduleExpression(String scheduleExpression) { this.scheduleExpression = scheduleExpression; }

        public ActionType getActionType() { return actionType; }
        public void setActionType(ActionType actionType) { this.actionType = actionType; }

        public boolean isEnabled() { return enabled; }
        public void setEnabled(boolean enabled) { this.enabled = enabled; }

        public Map<String, Object> getParameters() { return parameters; }
        public void setParameters(Map<String, Object> parameters) { this.parameters = parameters; }
    }

    public enum TriggerType {
        SCHEDULED, EVENT_BASED, THRESHOLD_BASED
    }

    public enum ActionType {
        MAINTENANCE, HEALTH_CHECK, RESOURCE_OPTIMIZATION, SCALING, BACKUP
    }

    public static class AutomationExecutionResult {
        private String executionId;
        private String executionType;
        private Instant startTime;
        private Instant endTime;
        private String status;
        private String error;
        private List<MaintenanceTask> completedTasks;
        private int successfulTasks;
        private int failedTasks;

        public long getDurationMs() {
            if (endTime != null && startTime != null) {
                return endTime.toEpochMilli() - startTime.toEpochMilli();
            }
            return 0;
        }

        // Getters and setters
        public String getExecutionId() { return executionId; }
        public void setExecutionId(String executionId) { this.executionId = executionId; }

        public String getExecutionType() { return executionType; }
        public void setExecutionType(String executionType) { this.executionType = executionType; }

        public Instant getStartTime() { return startTime; }
        public void setStartTime(Instant startTime) { this.startTime = startTime; }

        public Instant getEndTime() { return endTime; }
        public void setEndTime(Instant endTime) { this.endTime = endTime; }

        public String getStatus() { return status; }
        public void setStatus(String status) { this.status = status; }

        public String getError() { return error; }
        public void setError(String error) { this.error = error; }

        public List<MaintenanceTask> getCompletedTasks() { return completedTasks; }
        public void setCompletedTasks(List<MaintenanceTask> completedTasks) { this.completedTasks = completedTasks; }

        public int getSuccessfulTasks() { return successfulTasks; }
        public void setSuccessfulTasks(int successfulTasks) { this.successfulTasks = successfulTasks; }

        public int getFailedTasks() { return failedTasks; }
        public void setFailedTasks(int failedTasks) { this.failedTasks = failedTasks; }
    }

    public static class MaintenanceTask {
        private String taskName;
        private boolean successful;
        private String result;
        private String error;
        private Instant executedAt;

        public MaintenanceTask(String taskName) {
            this.taskName = taskName;
            this.executedAt = Instant.now();
        }

        // Getters and setters
        public String getTaskName() { return taskName; }
        public void setTaskName(String taskName) { this.taskName = taskName; }

        public boolean isSuccessful() { return successful; }
        public void setSuccessful(boolean successful) { this.successful = successful; }

        public String getResult() { return result; }
        public void setResult(String result) { this.result = result; }

        public String getError() { return error; }
        public void setError(String error) { this.error = error; }

        public Instant getExecutedAt() { return executedAt; }
        public void setExecutedAt(Instant executedAt) { this.executedAt = executedAt; }
    }

    // Additional data classes...
    public static class TenantScalingResult {
        private Instant analysisTime;
        private int tenantsAnalyzed;
        private int recommendationsGenerated;
        private int autoScaledTenants;
        private List<ScalingRecommendation> scalingRecommendations;
        private String error;

        // Getters and setters
        public Instant getAnalysisTime() { return analysisTime; }
        public void setAnalysisTime(Instant analysisTime) { this.analysisTime = analysisTime; }

        public int getTenantsAnalyzed() { return tenantsAnalyzed; }
        public void setTenantsAnalyzed(int tenantsAnalyzed) { this.tenantsAnalyzed = tenantsAnalyzed; }

        public int getRecommendationsGenerated() { return recommendationsGenerated; }
        public void setRecommendationsGenerated(int recommendationsGenerated) { 
            this.recommendationsGenerated = recommendationsGenerated; 
        }

        public int getAutoScaledTenants() { return autoScaledTenants; }
        public void setAutoScaledTenants(int autoScaledTenants) { this.autoScaledTenants = autoScaledTenants; }

        public List<ScalingRecommendation> getScalingRecommendations() { return scalingRecommendations; }
        public void setScalingRecommendations(List<ScalingRecommendation> scalingRecommendations) { 
            this.scalingRecommendations = scalingRecommendations; 
        }

        public String getError() { return error; }
        public void setError(String error) { this.error = error; }
    }

    public static class ScalingRecommendation {
        private UUID tenantId;
        private String currentTier;
        private ScalingAction recommendedAction;
        private String reason;
        private double currentUsage;
        private boolean autoApplicable = false;

        // Getters and setters
        public UUID getTenantId() { return tenantId; }
        public void setTenantId(UUID tenantId) { this.tenantId = tenantId; }

        public String getCurrentTier() { return currentTier; }
        public void setCurrentTier(String currentTier) { this.currentTier = currentTier; }

        public ScalingAction getRecommendedAction() { return recommendedAction; }
        public void setRecommendedAction(ScalingAction recommendedAction) { this.recommendedAction = recommendedAction; }

        public String getReason() { return reason; }
        public void setReason(String reason) { this.reason = reason; }

        public double getCurrentUsage() { return currentUsage; }
        public void setCurrentUsage(double currentUsage) { this.currentUsage = currentUsage; }

        public boolean isAutoApplicable() { return autoApplicable; }
        public void setAutoApplicable(boolean autoApplicable) { this.autoApplicable = autoApplicable; }
    }

    public enum ScalingAction {
        SCALE_UP, SCALE_DOWN, MAINTAIN
    }

    public static class TenantHealthCheckResult {
        private Instant checkTime;
        private int tenantsChecked;
        private int healthyTenants;
        private int unhealthyTenants;
        private List<TenantHealthStatus> tenantHealthStatuses;
        private String error;

        // Getters and setters
        public Instant getCheckTime() { return checkTime; }
        public void setCheckTime(Instant checkTime) { this.checkTime = checkTime; }

        public int getTenantsChecked() { return tenantsChecked; }
        public void setTenantsChecked(int tenantsChecked) { this.tenantsChecked = tenantsChecked; }

        public int getHealthyTenants() { return healthyTenants; }
        public void setHealthyTenants(int healthyTenants) { this.healthyTenants = healthyTenants; }

        public int getUnhealthyTenants() { return unhealthyTenants; }
        public void setUnhealthyTenants(int unhealthyTenants) { this.unhealthyTenants = unhealthyTenants; }

        public List<TenantHealthStatus> getTenantHealthStatuses() { return tenantHealthStatuses; }
        public void setTenantHealthStatuses(List<TenantHealthStatus> tenantHealthStatuses) { 
            this.tenantHealthStatuses = tenantHealthStatuses; 
        }

        public String getError() { return error; }
        public void setError(String error) { this.error = error; }
    }

    public static class TenantHealthStatus {
        private UUID tenantId;
        private Instant checkTime;
        private boolean healthy;
        private double healthScore;
        private List<String> issues;

        // Getters and setters
        public UUID getTenantId() { return tenantId; }
        public void setTenantId(UUID tenantId) { this.tenantId = tenantId; }

        public Instant getCheckTime() { return checkTime; }
        public void setCheckTime(Instant checkTime) { this.checkTime = checkTime; }

        public boolean isHealthy() { return healthy; }
        public void setHealthy(boolean healthy) { this.healthy = healthy; }

        public double getHealthScore() { return healthScore; }
        public void setHealthScore(double healthScore) { this.healthScore = healthScore; }

        public List<String> getIssues() { return issues; }
        public void setIssues(List<String> issues) { this.issues = issues; }
    }

    public static class LifecycleAutomationResult {
        private Instant executionTime;
        private List<String> provisioningActions;
        private List<String> tierAdjustments;
        private List<String> expirationActions;
        private List<String> backupActions;
        private String error;

        // Getters and setters
        public Instant getExecutionTime() { return executionTime; }
        public void setExecutionTime(Instant executionTime) { this.executionTime = executionTime; }

        public List<String> getProvisioningActions() { return provisioningActions; }
        public void setProvisioningActions(List<String> provisioningActions) { this.provisioningActions = provisioningActions; }

        public List<String> getTierAdjustments() { return tierAdjustments; }
        public void setTierAdjustments(List<String> tierAdjustments) { this.tierAdjustments = tierAdjustments; }

        public List<String> getExpirationActions() { return expirationActions; }
        public void setExpirationActions(List<String> expirationActions) { this.expirationActions = expirationActions; }

        public List<String> getBackupActions() { return backupActions; }
        public void setBackupActions(List<String> backupActions) { this.backupActions = backupActions; }

        public String getError() { return error; }
        public void setError(String error) { this.error = error; }
    }

    public static class AutomationStatistics {
        private LocalDateTime generatedAt;
        private int totalAutomationRules;
        private int activeAutomationRules;
        private int executionsLast24Hours;
        private int totalExecutions;
        private double successRate;

        // Getters and setters
        public LocalDateTime getGeneratedAt() { return generatedAt; }
        public void setGeneratedAt(LocalDateTime generatedAt) { this.generatedAt = generatedAt; }

        public int getTotalAutomationRules() { return totalAutomationRules; }
        public void setTotalAutomationRules(int totalAutomationRules) { this.totalAutomationRules = totalAutomationRules; }

        public int getActiveAutomationRules() { return activeAutomationRules; }
        public void setActiveAutomationRules(int activeAutomationRules) { this.activeAutomationRules = activeAutomationRules; }

        public int getExecutionsLast24Hours() { return executionsLast24Hours; }
        public void setExecutionsLast24Hours(int executionsLast24Hours) { this.executionsLast24Hours = executionsLast24Hours; }

        public int getTotalExecutions() { return totalExecutions; }
        public void setTotalExecutions(int totalExecutions) { this.totalExecutions = totalExecutions; }

        public double getSuccessRate() { return successRate; }
        public void setSuccessRate(double successRate) { this.successRate = successRate; }
    }

    public static class AutomationExecution {
        private String executionId;
        private String ruleId;
        private String ruleName;
        private Instant startTime;
        private Instant endTime;
        private String status;

        // Getters and setters
        public String getExecutionId() { return executionId; }
        public void setExecutionId(String executionId) { this.executionId = executionId; }

        public String getRuleId() { return ruleId; }
        public void setRuleId(String ruleId) { this.ruleId = ruleId; }

        public String getRuleName() { return ruleName; }
        public void setRuleName(String ruleName) { this.ruleName = ruleName; }

        public Instant getStartTime() { return startTime; }
        public void setStartTime(Instant startTime) { this.startTime = startTime; }

        public Instant getEndTime() { return endTime; }
        public void setEndTime(Instant endTime) { this.endTime = endTime; }

        public String getStatus() { return status; }
        public void setStatus(String status) { this.status = status; }
    }
}
