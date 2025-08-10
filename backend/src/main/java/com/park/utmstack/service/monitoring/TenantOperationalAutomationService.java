package com.park.utmstack.service.monitoring;

import com.park.utmstack.domain.UtmTenant;
import com.park.utmstack.service.TenantService;
import com.park.utmstack.service.TenantResourceQuotaService;
import com.park.utmstack.service.TenantProvisioningService;
import com.park.utmstack.service.alerting.MultiTenantAlertingService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import javax.annotation.PostConstruct;
import javax.annotation.PreDestroy;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.temporal.ChronoUnit;
import java.util.*;
import java.util.concurrent.*;

/**
 * Automated operational workflows for multi-tenant environment.
 * Handles tenant lifecycle automation, resource optimization, and proactive maintenance.
 */
@Service
public class TenantOperationalAutomationService {

    private static final Logger log = LoggerFactory.getLogger(TenantOperationalAutomationService.class);

    private final TenantService tenantService;
    private final TenantResourceQuotaService quotaService;
    private final TenantProvisioningService provisioningService;
    private final MultiTenantAlertingService alertingService;
    private final MultiTenantMonitoringService monitoringService;
    private final ScheduledExecutorService scheduler = Executors.newScheduledThreadPool(3);

    // Automation configuration
    private final Map<String, AutomationRule> automationRules = new ConcurrentHashMap<>();
    private final Map<UUID, AutomationTask> activeTasks = new ConcurrentHashMap<>();

    public TenantOperationalAutomationService(TenantService tenantService,
                                            TenantResourceQuotaService quotaService,
                                            TenantProvisioningService provisioningService,
                                            MultiTenantAlertingService alertingService,
                                            MultiTenantMonitoringService monitoringService) {
        this.tenantService = tenantService;
        this.quotaService = quotaService;
        this.provisioningService = provisioningService;
        this.alertingService = alertingService;
        this.monitoringService = monitoringService;
    }

    @PostConstruct
    public void initializeAutomation() {
        log.info("Initializing tenant operational automation system");
        
        // Initialize automation rules
        initializeAutomationRules();
        
        // Start automation workflows
        startAutomationWorkflows();
        
        log.info("Tenant operational automation system initialized successfully");
    }

    @PreDestroy
    public void shutdown() {
        log.info("Shutting down tenant operational automation system");
        scheduler.shutdown();
        try {
            if (!scheduler.awaitTermination(60, TimeUnit.SECONDS)) {
                scheduler.shutdownNow();
            }
        } catch (InterruptedException e) {
            scheduler.shutdownNow();
            Thread.currentThread().interrupt();
        }
    }

    /**
     * Execute automated health checks and maintenance
     */
    public void performAutomatedHealthCheck() {
        log.info("Performing automated health check");
        
        try {
            List<UtmTenant> allTenants = tenantService.getAllActiveTenants();
            
            for (UtmTenant tenant : allTenants) {
                try {
                    // Check tenant health
                    MultiTenantMonitoringService.TenantMetrics metrics = 
                        monitoringService.getTenantMetrics(tenant.getId());
                    
                    // Execute health-based automation rules
                    executeHealthBasedRules(tenant, metrics);
                    
                } catch (Exception e) {
                    log.error("Error during health check for tenant {}: {}", tenant.getId(), e.getMessage());
                }
            }
            
        } catch (Exception e) {
            log.error("Error during automated health check", e);
        }
    }

    /**
     * Automated resource optimization workflow
     */
    public void performResourceOptimization() {
        log.info("Performing automated resource optimization");
        
        try {
            List<UtmTenant> allTenants = tenantService.getAllActiveTenants();
            
            for (UtmTenant tenant : allTenants) {
                try {
                    var quotaStatus = quotaService.getResourceQuotaStatus(tenant.getId());
                    
                    // Check for resource optimization opportunities
                    if (quotaStatus.getUserUsage() < 30.0 && 
                        quotaStatus.getStorageUsage() < 30.0) {
                        
                        // Suggest tier downgrade
                        suggestTierOptimization(tenant, "DOWNGRADE", 
                            "Low resource utilization detected");
                    }
                    
                    if (quotaStatus.getUserUsage() > 90.0 || 
                        quotaStatus.getStorageUsage() > 90.0) {
                        
                        // Suggest tier upgrade
                        suggestTierOptimization(tenant, "UPGRADE", 
                            "High resource utilization detected");
                    }
                    
                } catch (Exception e) {
                    log.error("Error during resource optimization for tenant {}: {}", 
                            tenant.getId(), e.getMessage());
                }
            }
            
        } catch (Exception e) {
            log.error("Error during automated resource optimization", e);
        }
    }

    /**
     * Automated cleanup of inactive resources
     */
    public void performCleanupTasks() {
        log.info("Performing automated cleanup tasks");
        
        try {
            // Clean up old metrics data
            cleanupOldMetrics();
            
            // Clean up expired automation tasks
            cleanupExpiredTasks();
            
            // Clean up inactive tenant resources
            cleanupInactiveTenantResources();
            
        } catch (Exception e) {
            log.error("Error during automated cleanup", e);
        }
    }

    /**
     * Automated tenant tier management
     */
    public void performTierManagement() {
        log.info("Performing automated tier management");
        
        try {
            List<UtmTenant> allTenants = tenantService.getAllActiveTenants();
            
            for (UtmTenant tenant : allTenants) {
                try {
                    var usage = quotaService.getTenantResourceUsage(tenant.getId());
                    var quotaStatus = quotaService.getResourceQuotaStatus(tenant.getId());
                    
                    // Analyze usage patterns for tier optimization
                    TierRecommendation recommendation = analyzeTierRecommendation(tenant, usage, quotaStatus);
                    
                    if (recommendation.isActionRequired()) {
                        executeTierRecommendation(tenant, recommendation);
                    }
                    
                } catch (Exception e) {
                    log.error("Error during tier management for tenant {}: {}", 
                            tenant.getId(), e.getMessage());
                }
            }
            
        } catch (Exception e) {
            log.error("Error during automated tier management", e);
        }
    }

    /**
     * Create automation task
     */
    public AutomationTask createAutomationTask(UUID tenantId, String taskType, String description) {
        AutomationTask task = new AutomationTask(tenantId, taskType, description);
        activeTasks.put(task.getTaskId(), task);
        
        log.info("Created automation task: {}", task.getTaskId());
        return task;
    }

    /**
     * Get automation task status
     */
    public Optional<AutomationTask> getAutomationTask(UUID taskId) {
        return Optional.ofNullable(activeTasks.get(taskId));
    }

    /**
     * Get all active automation tasks for a tenant
     */
    public List<AutomationTask> getActiveTasks(UUID tenantId) {
        return activeTasks.values().stream()
            .filter(task -> task.getTenantId().equals(tenantId))
            .filter(task -> task.getStatus() == AutomationTask.TaskStatus.RUNNING)
            .toList();
    }

    /**
     * Get automation statistics
     */
    public AutomationStatistics getAutomationStatistics() {
        AutomationStatistics stats = new AutomationStatistics();
        stats.setTimestamp(Instant.now());
        
        // Calculate task statistics
        long totalTasks = activeTasks.size();
        long runningTasks = activeTasks.values().stream()
            .filter(task -> task.getStatus() == AutomationTask.TaskStatus.RUNNING)
            .count();
        long completedTasks = activeTasks.values().stream()
            .filter(task -> task.getStatus() == AutomationTask.TaskStatus.COMPLETED)
            .count();
        long failedTasks = activeTasks.values().stream()
            .filter(task -> task.getStatus() == AutomationTask.TaskStatus.FAILED)
            .count();
        
        stats.setTotalTasks(totalTasks);
        stats.setRunningTasks(runningTasks);
        stats.setCompletedTasks(completedTasks);
        stats.setFailedTasks(failedTasks);
        
        // Calculate rule statistics
        stats.setActiveRules(automationRules.size());
        
        // Calculate average task duration
        double avgDuration = activeTasks.values().stream()
            .filter(task -> task.getStatus() == AutomationTask.TaskStatus.COMPLETED)
            .mapToLong(task -> ChronoUnit.MILLIS.between(task.getStartTime(), task.getEndTime()))
            .average()
            .orElse(0.0);
        stats.setAverageTaskDuration(avgDuration);
        
        return stats;
    }

    private void initializeAutomationRules() {
        // Health-based automation rules
        automationRules.put("LOW_HEALTH_ALERT", new AutomationRule(
            "LOW_HEALTH_ALERT", 
            "Create alert when tenant health drops below threshold",
            tenant -> {
                MultiTenantMonitoringService.TenantMetrics metrics = 
                    monitoringService.getTenantMetrics(tenant.getId());
                return metrics.getHealthScore() < 70.0;
            },
            this::createLowHealthAlert
        ));
        
        // Resource quota automation rules
        automationRules.put("QUOTA_WARNING", new AutomationRule(
            "QUOTA_WARNING",
            "Send warning when tenant approaches quota limits",
            tenant -> {
                var quotaStatus = quotaService.getResourceQuotaStatus(tenant.getId());
                return quotaStatus.getUserUsage() > 85.0 || 
                       quotaStatus.getStorageUsage() > 85.0;
            },
            this::createQuotaWarning
        ));
        
        // Proactive maintenance rules
        automationRules.put("MAINTENANCE_REQUIRED", new AutomationRule(
            "MAINTENANCE_REQUIRED",
            "Schedule maintenance when tenant shows performance degradation",
            tenant -> {
                MultiTenantMonitoringService.TenantMetrics metrics = 
                    monitoringService.getTenantMetrics(tenant.getId());
                return metrics.getHealthScore() < 80.0 && 
                       metrics.getQuotaUtilization() > 90.0;
            },
            this::scheduleProactiveMaintenance
        ));
        
        log.info("Initialized {} automation rules", automationRules.size());
    }

    private void startAutomationWorkflows() {
        // Health monitoring workflow - every 5 minutes
        scheduler.scheduleAtFixedRate(this::performAutomatedHealthCheck, 0, 5, TimeUnit.MINUTES);
        
        // Resource optimization workflow - every 30 minutes
        scheduler.scheduleAtFixedRate(this::performResourceOptimization, 0, 30, TimeUnit.MINUTES);
        
        // Cleanup workflow - every hour
        scheduler.scheduleAtFixedRate(this::performCleanupTasks, 0, 1, TimeUnit.HOURS);
        
        // Tier management workflow - every 6 hours
        scheduler.scheduleAtFixedRate(this::performTierManagement, 0, 6, TimeUnit.HOURS);
        
        log.info("Started automation workflows");
    }

    private void executeHealthBasedRules(UtmTenant tenant, MultiTenantMonitoringService.TenantMetrics metrics) {
        for (AutomationRule rule : automationRules.values()) {
            try {
                if (rule.getCondition().test(tenant)) {
                    AutomationTask task = createAutomationTask(tenant.getId(), rule.getRuleName(), 
                        "Triggered by: " + rule.getDescription());
                    
                    // Execute the rule action
                    rule.getAction().accept(tenant);
                    
                    task.markCompleted("Rule executed successfully");
                }
            } catch (Exception e) {
                log.error("Error executing rule {} for tenant {}: {}", 
                        rule.getRuleName(), tenant.getId(), e.getMessage());
            }
        }
    }

    private void suggestTierOptimization(UtmTenant tenant, String action, String reason) {
        log.info("Suggesting tier {} for tenant {}: {}", action, tenant.getId(), reason);
        
        // Create optimization alert
        alertingService.createAlert(tenant.getId(), "TIER_OPTIMIZATION", 
            "INFO", reason + " - Consider tier " + action.toLowerCase());
    }

    private TierRecommendation analyzeTierRecommendation(UtmTenant tenant, 
            TenantResourceQuotaService.TenantResourceUsage usage,
            TenantResourceQuotaService.ResourceQuotaStatus quotaStatus) {
        
        TierRecommendation recommendation = new TierRecommendation(tenant.getId());
        
        // Calculate overall utilization
        double avgUtilization = (quotaStatus.getUserUsage() + 
                               quotaStatus.getStorageUsage() + 
                               quotaStatus.getDashboardUsage()) / 3.0;
        
        if (avgUtilization < 25.0 && !"basic".equals(tenant.getTier())) {
            recommendation.setRecommendedAction("DOWNGRADE");
            recommendation.setRecommendedTier("basic");
            recommendation.setReason("Consistently low resource utilization");
            recommendation.setActionRequired(true);
        } else if (avgUtilization > 90.0 && !"enterprise".equals(tenant.getTier())) {
            recommendation.setRecommendedAction("UPGRADE");
            recommendation.setRecommendedTier("enterprise");
            recommendation.setReason("High resource utilization requiring more capacity");
            recommendation.setActionRequired(true);
        }
        
        return recommendation;
    }

    private void executeTierRecommendation(UtmTenant tenant, TierRecommendation recommendation) {
        log.info("Executing tier recommendation for tenant {}: {} to {}", 
                tenant.getId(), recommendation.getRecommendedAction(), recommendation.getRecommendedTier());
        
        // Create alert for manual review
        alertingService.createAlert(tenant.getId(), "TIER_RECOMMENDATION", "INFO",
            String.format("Recommended tier %s to %s: %s", 
                recommendation.getRecommendedAction().toLowerCase(),
                recommendation.getRecommendedTier(),
                recommendation.getReason()));
    }

    private void cleanupOldMetrics() {
        log.debug("Cleaning up old automation metrics");
        
        Instant cutoff = Instant.now().minusSeconds(86400 * 7); // 7 days
        
        activeTasks.entrySet().removeIf(entry -> {
            AutomationTask task = entry.getValue();
            return task.getStatus() == AutomationTask.TaskStatus.COMPLETED &&
                   task.getEndTime() != null &&
                   task.getEndTime().isBefore(cutoff);
        });
    }

    private void cleanupExpiredTasks() {
        log.debug("Cleaning up expired automation tasks");
        
        Instant cutoff = Instant.now().minusSeconds(3600 * 24); // 24 hours
        
        activeTasks.entrySet().removeIf(entry -> {
            AutomationTask task = entry.getValue();
            return task.getStatus() == AutomationTask.TaskStatus.RUNNING &&
                   task.getStartTime().isBefore(cutoff);
        });
    }

    private void cleanupInactiveTenantResources() {
        log.debug("Cleaning up inactive tenant resources");
        
        // Implementation would clean up resources for inactive tenants
        // This is a placeholder for actual cleanup logic
    }

    // Automation rule action methods
    private void createLowHealthAlert(UtmTenant tenant) {
        log.warn("Creating low health alert for tenant: {}", tenant.getId());
        alertingService.createAlert(tenant.getId(), "LOW_HEALTH", "WARNING",
            "Tenant health score below acceptable threshold");
    }

    private void createQuotaWarning(UtmTenant tenant) {
        log.warn("Creating quota warning for tenant: {}", tenant.getId());
        alertingService.createAlert(tenant.getId(), "QUOTA_WARNING", "WARNING",
            "Tenant approaching resource quota limits");
    }

    private void scheduleProactiveMaintenance(UtmTenant tenant) {
        log.info("Scheduling proactive maintenance for tenant: {}", tenant.getId());
        alertingService.createAlert(tenant.getId(), "MAINTENANCE_SCHEDULED", "INFO",
            "Proactive maintenance scheduled due to performance indicators");
    }

    // Data classes
    public static class AutomationRule {
        private final String ruleName;
        private final String description;
        private final java.util.function.Predicate<UtmTenant> condition;
        private final java.util.function.Consumer<UtmTenant> action;

        public AutomationRule(String ruleName, String description,
                             java.util.function.Predicate<UtmTenant> condition,
                             java.util.function.Consumer<UtmTenant> action) {
            this.ruleName = ruleName;
            this.description = description;
            this.condition = condition;
            this.action = action;
        }

        public String getRuleName() { return ruleName; }
        public String getDescription() { return description; }
        public java.util.function.Predicate<UtmTenant> getCondition() { return condition; }
        public java.util.function.Consumer<UtmTenant> getAction() { return action; }
    }

    public static class AutomationTask {
        public enum TaskStatus {
            RUNNING, COMPLETED, FAILED, CANCELLED
        }

        private final UUID taskId;
        private final UUID tenantId;
        private final String taskType;
        private final String description;
        private final Instant startTime;
        private Instant endTime;
        private TaskStatus status;
        private String result;

        public AutomationTask(UUID tenantId, String taskType, String description) {
            this.taskId = UUID.randomUUID();
            this.tenantId = tenantId;
            this.taskType = taskType;
            this.description = description;
            this.startTime = Instant.now();
            this.status = TaskStatus.RUNNING;
        }

        public void markCompleted(String result) {
            this.status = TaskStatus.COMPLETED;
            this.endTime = Instant.now();
            this.result = result;
        }

        public void markFailed(String error) {
            this.status = TaskStatus.FAILED;
            this.endTime = Instant.now();
            this.result = error;
        }

        // Getters
        public UUID getTaskId() { return taskId; }
        public UUID getTenantId() { return tenantId; }
        public String getTaskType() { return taskType; }
        public String getDescription() { return description; }
        public Instant getStartTime() { return startTime; }
        public Instant getEndTime() { return endTime; }
        public TaskStatus getStatus() { return status; }
        public String getResult() { return result; }
    }

    public static class TierRecommendation {
        private final UUID tenantId;
        private String recommendedAction;
        private String recommendedTier;
        private String reason;
        private boolean actionRequired;

        public TierRecommendation(UUID tenantId) {
            this.tenantId = tenantId;
            this.actionRequired = false;
        }

        // Getters and setters
        public UUID getTenantId() { return tenantId; }
        public String getRecommendedAction() { return recommendedAction; }
        public void setRecommendedAction(String recommendedAction) { this.recommendedAction = recommendedAction; }
        public String getRecommendedTier() { return recommendedTier; }
        public void setRecommendedTier(String recommendedTier) { this.recommendedTier = recommendedTier; }
        public String getReason() { return reason; }
        public void setReason(String reason) { this.reason = reason; }
        public boolean isActionRequired() { return actionRequired; }
        public void setActionRequired(boolean actionRequired) { this.actionRequired = actionRequired; }
    }

    public static class AutomationStatistics {
        private Instant timestamp;
        private long totalTasks;
        private long runningTasks;
        private long completedTasks;
        private long failedTasks;
        private long activeRules;
        private double averageTaskDuration;

        // Getters and setters
        public Instant getTimestamp() { return timestamp; }
        public void setTimestamp(Instant timestamp) { this.timestamp = timestamp; }
        public long getTotalTasks() { return totalTasks; }
        public void setTotalTasks(long totalTasks) { this.totalTasks = totalTasks; }
        public long getRunningTasks() { return runningTasks; }
        public void setRunningTasks(long runningTasks) { this.runningTasks = runningTasks; }
        public long getCompletedTasks() { return completedTasks; }
        public void setCompletedTasks(long completedTasks) { this.completedTasks = completedTasks; }
        public long getFailedTasks() { return failedTasks; }
        public void setFailedTasks(long failedTasks) { this.failedTasks = failedTasks; }
        public long getActiveRules() { return activeRules; }
        public void setActiveRules(long activeRules) { this.activeRules = activeRules; }
        public double getAverageTaskDuration() { return averageTaskDuration; }
        public void setAverageTaskDuration(double averageTaskDuration) { this.averageTaskDuration = averageTaskDuration; }
    }
}
