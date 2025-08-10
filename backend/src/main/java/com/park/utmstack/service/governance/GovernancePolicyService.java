package com.park.utmstack.service.governance;

import com.park.utmstack.domain.UtmTenant;
import com.park.utmstack.service.TenantService;
import com.park.utmstack.service.SecurityAuditService;
import com.park.utmstack.service.compliance.ComplianceFrameworkService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Service;

import javax.annotation.PostConstruct;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.temporal.ChronoUnit;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.stream.Collectors;

/**
 * Governance policy engine for multi-tenant SIEM platform.
 * Manages organizational policies, access controls, and compliance governance.
 */
@Service
public class GovernancePolicyService {

    private static final Logger log = LoggerFactory.getLogger(GovernancePolicyService.class);

    private final TenantService tenantService;
    private final SecurityAuditService securityAuditService;
    private final ComplianceFrameworkService complianceFrameworkService;
    private final ApplicationEventPublisher eventPublisher;
    private final ScheduledExecutorService scheduler = Executors.newScheduledThreadPool(2);

    // Governance data structures
    private final Map<String, GovernancePolicy> policies = new ConcurrentHashMap<>();
    private final Map<UUID, TenantGovernanceProfile> tenantProfiles = new ConcurrentHashMap<>();
    private final Map<String, PolicyViolation> policyViolations = new ConcurrentHashMap<>();
    private final Map<String, AccessControlRule> accessControlRules = new ConcurrentHashMap<>();

    public GovernancePolicyService(TenantService tenantService,
                                 SecurityAuditService securityAuditService,
                                 ComplianceFrameworkService complianceFrameworkService,
                                 ApplicationEventPublisher eventPublisher) {
        this.tenantService = tenantService;
        this.securityAuditService = securityAuditService;
        this.complianceFrameworkService = complianceFrameworkService;
        this.eventPublisher = eventPublisher;
    }

    @PostConstruct
    public void initializeGovernance() {
        log.info("Initializing governance policy engine");
        
        // Initialize default policies
        initializeDefaultPolicies();
        
        // Initialize access control rules
        initializeAccessControlRules();
        
        // Start governance monitoring
        startGovernanceMonitoring();
        
        log.info("Governance policy engine initialized with {} policies and {} access rules",
                policies.size(), accessControlRules.size());
    }

    /**
     * Create a new governance policy
     */
    public String createGovernancePolicy(GovernancePolicyDefinition definition) {
        String policyId = UUID.randomUUID().toString();
        
        GovernancePolicy policy = new GovernancePolicy();
        policy.setPolicyId(policyId);
        policy.setDefinition(definition);
        policy.setCreatedAt(LocalDateTime.now());
        policy.setUpdatedAt(LocalDateTime.now());
        policy.setActive(true);
        
        policies.put(policyId, policy);
        
        log.info("Created governance policy: {} ({})", definition.getName(), policyId);
        
        // Audit the policy creation
        securityAuditService.auditPolicyEvent(null, "POLICY_CREATED", 
            "Governance policy created: " + definition.getName(), policyId);
        
        return policyId;
    }

    /**
     * Update an existing governance policy
     */
    public void updateGovernancePolicy(String policyId, GovernancePolicyDefinition definition) {
        GovernancePolicy policy = policies.get(policyId);
        if (policy == null) {
            throw new IllegalArgumentException("Policy not found: " + policyId);
        }
        
        policy.setDefinition(definition);
        policy.setUpdatedAt(LocalDateTime.now());
        
        log.info("Updated governance policy: {} ({})", definition.getName(), policyId);
        
        // Audit the policy update
        securityAuditService.auditPolicyEvent(null, "POLICY_UPDATED", 
            "Governance policy updated: " + definition.getName(), policyId);
    }

    /**
     * Evaluate tenant against governance policies
     */
    public TenantGovernanceAssessment evaluateTenantGovernance(UUID tenantId) {
        TenantGovernanceAssessment assessment = new TenantGovernanceAssessment();
        assessment.setTenantId(tenantId);
        assessment.setEvaluatedAt(LocalDateTime.now());
        
        try {
            List<PolicyEvaluation> evaluations = new ArrayList<>();
            double totalScore = 0.0;
            int evaluatedPolicies = 0;
            
            // Evaluate each active policy against the tenant
            for (GovernancePolicy policy : policies.values()) {
                if (policy.isActive()) {
                    PolicyEvaluation evaluation = evaluatePolicy(policy, tenantId);
                    evaluations.add(evaluation);
                    totalScore += evaluation.getComplianceScore();
                    evaluatedPolicies++;
                }
            }
            
            assessment.setPolicyEvaluations(evaluations);
            assessment.setOverallGovernanceScore(evaluatedPolicies > 0 ? 
                totalScore / evaluatedPolicies : 0.0);
            assessment.setGovernanceLevel(calculateGovernanceLevel(assessment.getOverallGovernanceScore()));
            
            // Count violations
            long openViolations = policyViolations.values().stream()
                .filter(v -> v.getTenantId().equals(tenantId))
                .filter(v -> v.getStatus() == PolicyViolation.ViolationStatus.OPEN)
                .count();
            
            assessment.setOpenViolations((int) openViolations);
            
            // Generate recommendations
            assessment.setRecommendations(generateGovernanceRecommendations(evaluations));
            
        } catch (Exception e) {
            log.error("Error evaluating tenant governance for {}", tenantId, e);
            assessment.setErrorMessage("Error evaluating governance: " + e.getMessage());
        }
        
        return assessment;
    }

    /**
     * Create tenant governance profile
     */
    public void createTenantGovernanceProfile(UUID tenantId, TenantGovernanceProfileDefinition definition) {
        TenantGovernanceProfile profile = new TenantGovernanceProfile();
        profile.setTenantId(tenantId);
        profile.setDefinition(definition);
        profile.setCreatedAt(LocalDateTime.now());
        profile.setUpdatedAt(LocalDateTime.now());
        
        tenantProfiles.put(tenantId, profile);
        
        log.info("Created governance profile for tenant: {}", tenantId);
        
        // Audit profile creation
        securityAuditService.auditTenantEvent(tenantId, "GOVERNANCE_PROFILE_CREATED", 
            "Tenant governance profile created");
    }

    /**
     * Validate access request against governance rules
     */
    public AccessDecision validateAccess(UUID tenantId, String userId, String resource, String action) {
        AccessDecision decision = new AccessDecision();
        decision.setTenantId(tenantId);
        decision.setUserId(userId);
        decision.setResource(resource);
        decision.setAction(action);
        decision.setEvaluatedAt(Instant.now());
        
        try {
            TenantGovernanceProfile profile = tenantProfiles.get(tenantId);
            if (profile == null) {
                decision.setDecision("DENY");
                decision.setReason("No governance profile found for tenant");
                return decision;
            }
            
            // Evaluate access control rules
            boolean accessGranted = true;
            List<String> reasons = new ArrayList<>();
            
            for (AccessControlRule rule : accessControlRules.values()) {
                if (rule.isActive() && rule.appliesToTenant(tenantId)) {
                    RuleEvaluation evaluation = evaluateAccessRule(rule, tenantId, userId, resource, action);
                    
                    if (!evaluation.isAllowed()) {
                        accessGranted = false;
                        reasons.add(evaluation.getReason());
                        
                        // Record potential policy violation
                        if (evaluation.isCritical()) {
                            recordPolicyViolation(tenantId, rule.getRuleId(), 
                                "ACCESS_DENIED", evaluation.getReason(), "HIGH");
                        }
                    }
                }
            }
            
            decision.setDecision(accessGranted ? "ALLOW" : "DENY");
            decision.setReason(accessGranted ? "Access granted by governance policies" : 
                String.join("; ", reasons));
            
            // Audit access decision
            securityAuditService.auditAccessEvent(tenantId, userId, resource, action, 
                decision.getDecision(), decision.getReason());
            
        } catch (Exception e) {
            log.error("Error validating access for tenant {} user {} resource {} action {}", 
                    tenantId, userId, resource, action, e);
            decision.setDecision("DENY");
            decision.setReason("Error during access evaluation: " + e.getMessage());
        }
        
        return decision;
    }

    /**
     * Record a policy violation
     */
    public void recordPolicyViolation(UUID tenantId, String policyId, String violationType, 
                                    String description, String severity) {
        String violationId = UUID.randomUUID().toString();
        
        PolicyViolation violation = new PolicyViolation();
        violation.setViolationId(violationId);
        violation.setTenantId(tenantId);
        violation.setPolicyId(policyId);
        violation.setViolationType(violationType);
        violation.setDescription(description);
        violation.setSeverity(PolicyViolation.ViolationSeverity.valueOf(severity.toUpperCase()));
        violation.setDetectedAt(Instant.now());
        violation.setStatus(PolicyViolation.ViolationStatus.OPEN);
        
        policyViolations.put(violationId, violation);
        
        log.warn("Policy violation recorded: {} for tenant {} (policy: {}, severity: {})",
                violationType, tenantId, policyId, severity);
        
        // Record compliance violation as well
        complianceFrameworkService.recordComplianceViolation(tenantId, policyId, 
            violationType, description, severity);
        
        // Publish violation event
        eventPublisher.publishEvent(new PolicyViolationEvent(violation));
    }

    /**
     * Get governance dashboard
     */
    public GovernanceDashboard getGovernanceDashboard() {
        GovernanceDashboard dashboard = new GovernanceDashboard();
        dashboard.setGeneratedAt(LocalDateTime.now());
        
        try {
            List<UtmTenant> allTenants = tenantService.getAllActiveTenants();
            
            // Overall governance statistics
            double totalGovernanceScore = 0.0;
            int wellGovernedTenants = 0;
            int poorlyGovernedTenants = 0;
            
            for (UtmTenant tenant : allTenants) {
                TenantGovernanceAssessment assessment = evaluateTenantGovernance(tenant.getId());
                totalGovernanceScore += assessment.getOverallGovernanceScore();
                
                if (assessment.getOverallGovernanceScore() >= 80.0) {
                    wellGovernedTenants++;
                } else {
                    poorlyGovernedTenants++;
                }
            }
            
            dashboard.setTotalTenants(allTenants.size());
            dashboard.setWellGovernedTenants(wellGovernedTenants);
            dashboard.setPoorlyGovernedTenants(poorlyGovernedTenants);
            dashboard.setAverageGovernanceScore(allTenants.size() > 0 ? 
                totalGovernanceScore / allTenants.size() : 0.0);
            
            // Policy statistics
            dashboard.setActivePolicies((int) policies.values().stream()
                .filter(GovernancePolicy::isActive).count());
            dashboard.setTotalPolicies(policies.size());
            
            // Violation statistics
            long openViolations = policyViolations.values().stream()
                .filter(v -> v.getStatus() == PolicyViolation.ViolationStatus.OPEN)
                .count();
            
            long criticalViolations = policyViolations.values().stream()
                .filter(v -> v.getStatus() == PolicyViolation.ViolationStatus.OPEN)
                .filter(v -> v.getSeverity() == PolicyViolation.ViolationSeverity.CRITICAL)
                .count();
            
            dashboard.setOpenViolations((int) openViolations);
            dashboard.setCriticalViolations((int) criticalViolations);
            
            // Recent activities
            dashboard.setRecentViolations(getRecentViolations(7));
            
        } catch (Exception e) {
            log.error("Error generating governance dashboard", e);
            dashboard.setErrorMessage("Error generating dashboard: " + e.getMessage());
        }
        
        return dashboard;
    }

    /**
     * Get policy effectiveness report
     */
    public PolicyEffectivenessReport getPolicyEffectivenessReport() {
        PolicyEffectivenessReport report = new PolicyEffectivenessReport();
        report.setGeneratedAt(LocalDateTime.now());
        
        try {
            List<PolicyEffectiveness> effectiveness = new ArrayList<>();
            
            for (GovernancePolicy policy : policies.values()) {
                if (policy.isActive()) {
                    PolicyEffectiveness eff = calculatePolicyEffectiveness(policy);
                    effectiveness.add(eff);
                }
            }
            
            report.setPolicyEffectiveness(effectiveness);
            
            // Calculate overall effectiveness
            double avgEffectiveness = effectiveness.stream()
                .mapToDouble(PolicyEffectiveness::getEffectivenessScore)
                .average()
                .orElse(0.0);
            
            report.setOverallEffectiveness(avgEffectiveness);
            
        } catch (Exception e) {
            log.error("Error generating policy effectiveness report", e);
            report.setErrorMessage("Error generating report: " + e.getMessage());
        }
        
        return report;
    }

    private void initializeDefaultPolicies() {
        // Data Classification Policy
        GovernancePolicyDefinition dataClassification = new GovernancePolicyDefinition();
        dataClassification.setName("Data Classification Policy");
        dataClassification.setDescription("Mandatory data classification and handling requirements");
        dataClassification.setCategory("DATA_GOVERNANCE");
        dataClassification.setRiskLevel("HIGH");
        dataClassification.setMandatory(true);
        dataClassification.setCriteria(Arrays.asList(
            "All sensitive data must be classified",
            "Data handling procedures must be documented",
            "Regular data classification reviews required"
        ));
        createGovernancePolicy(dataClassification);
        
        // Access Control Policy
        GovernancePolicyDefinition accessControl = new GovernancePolicyDefinition();
        accessControl.setName("Multi-Factor Authentication Policy");
        accessControl.setDescription("Mandatory MFA for all user accounts");
        accessControl.setCategory("ACCESS_CONTROL");
        accessControl.setRiskLevel("CRITICAL");
        accessControl.setMandatory(true);
        accessControl.setCriteria(Arrays.asList(
            "MFA required for all user accounts",
            "Regular access reviews required",
            "Privileged access requires additional approval"
        ));
        createGovernancePolicy(accessControl);
        
        // Incident Response Policy
        GovernancePolicyDefinition incidentResponse = new GovernancePolicyDefinition();
        incidentResponse.setName("Security Incident Response Policy");
        incidentResponse.setDescription("Requirements for security incident handling");
        incidentResponse.setCategory("INCIDENT_MANAGEMENT");
        incidentResponse.setRiskLevel("HIGH");
        incidentResponse.setMandatory(true);
        incidentResponse.setCriteria(Arrays.asList(
            "Incident response plan documented",
            "Response team roles defined",
            "Regular incident response testing"
        ));
        createGovernancePolicy(incidentResponse);
        
        // Data Retention Policy
        GovernancePolicyDefinition dataRetention = new GovernancePolicyDefinition();
        dataRetention.setName("Data Retention and Disposal Policy");
        dataRetention.setDescription("Automated data retention and secure disposal");
        dataRetention.setCategory("DATA_LIFECYCLE");
        dataRetention.setRiskLevel("MEDIUM");
        dataRetention.setMandatory(true);
        dataRetention.setCriteria(Arrays.asList(
            "Data retention schedules defined",
            "Automated disposal processes",
            "Retention compliance monitoring"
        ));
        createGovernancePolicy(dataRetention);
    }

    private void initializeAccessControlRules() {
        // Admin access restriction
        AccessControlRule adminRule = new AccessControlRule();
        adminRule.setRuleId("ADMIN_ACCESS_RESTRICTION");
        adminRule.setRuleName("Administrative Access Restriction");
        adminRule.setDescription("Restrict administrative access to business hours");
        adminRule.setRuleType("TIME_BASED");
        adminRule.setActive(true);
        adminRule.setConditions(Map.of(
            "roles", Arrays.asList("ADMIN", "SUPER_ADMIN"),
            "allowed_hours", "08:00-18:00",
            "allowed_days", "MONDAY-FRIDAY"
        ));
        accessControlRules.put(adminRule.getRuleId(), adminRule);
        
        // Sensitive data access
        AccessControlRule dataRule = new AccessControlRule();
        dataRule.setRuleId("SENSITIVE_DATA_ACCESS");
        dataRule.setRuleName("Sensitive Data Access Control");
        dataRule.setDescription("Additional controls for sensitive data access");
        dataRule.setRuleType("DATA_CLASSIFICATION");
        dataRule.setActive(true);
        dataRule.setConditions(Map.of(
            "data_classifications", Arrays.asList("CONFIDENTIAL", "SECRET"),
            "require_justification", true,
            "max_session_duration", "2h"
        ));
        accessControlRules.put(dataRule.getRuleId(), dataRule);
        
        // Cross-tenant access prevention
        AccessControlRule crossTenantRule = new AccessControlRule();
        crossTenantRule.setRuleId("CROSS_TENANT_PREVENTION");
        crossTenantRule.setRuleName("Cross-Tenant Access Prevention");
        crossTenantRule.setDescription("Prevent cross-tenant data access");
        crossTenantRule.setRuleType("TENANT_ISOLATION");
        crossTenantRule.setActive(true);
        crossTenantRule.setConditions(Map.of(
            "enforce_tenant_isolation", true,
            "block_cross_tenant_queries", true
        ));
        accessControlRules.put(crossTenantRule.getRuleId(), crossTenantRule);
    }

    private void startGovernanceMonitoring() {
        // Run governance checks every 4 hours
        scheduler.scheduleAtFixedRate(this::performGovernanceChecks, 0, 4, TimeUnit.HOURS);
        
        // Update governance profiles every 2 hours
        scheduler.scheduleAtFixedRate(this::updateGovernanceProfiles, 0, 2, TimeUnit.HOURS);
        
        log.info("Started governance monitoring tasks");
    }

    private void performGovernanceChecks() {
        try {
            log.debug("Performing scheduled governance checks");
            
            List<UtmTenant> allTenants = tenantService.getAllActiveTenants();
            
            for (UtmTenant tenant : allTenants) {
                try {
                    TenantGovernanceAssessment assessment = evaluateTenantGovernance(tenant.getId());
                    
                    // Check for governance violations
                    if (assessment.getOverallGovernanceScore() < 70.0) {
                        recordPolicyViolation(tenant.getId(), "GOVERNANCE_SCORE", 
                            "LOW_GOVERNANCE_SCORE", 
                            String.format("Governance score below threshold: %.1f%%", 
                                        assessment.getOverallGovernanceScore()),
                            "MEDIUM");
                    }
                } catch (Exception e) {
                    log.error("Error checking governance for tenant {}", tenant.getId(), e);
                }
            }
            
        } catch (Exception e) {
            log.error("Error during governance checks", e);
        }
    }

    private void updateGovernanceProfiles() {
        try {
            log.debug("Updating governance profiles");
            
            // This would update tenant governance profiles based on recent activities
            // and compliance requirements
            
        } catch (Exception e) {
            log.error("Error updating governance profiles", e);
        }
    }

    private PolicyEvaluation evaluatePolicy(GovernancePolicy policy, UUID tenantId) {
        PolicyEvaluation evaluation = new PolicyEvaluation();
        evaluation.setPolicyId(policy.getPolicyId());
        evaluation.setPolicyName(policy.getDefinition().getName());
        evaluation.setEvaluatedAt(LocalDateTime.now());
        
        try {
            // Simulate policy evaluation based on policy category
            double score = evaluatePolicyImplementation(policy.getDefinition().getCategory(), tenantId);
            evaluation.setComplianceScore(score);
            evaluation.setStatus(score >= 80.0 ? "COMPLIANT" : "NON_COMPLIANT");
            evaluation.setFindings(generatePolicyFindings(policy.getDefinition().getCategory(), score));
            
        } catch (Exception e) {
            log.error("Error evaluating policy {} for tenant {}", policy.getPolicyId(), tenantId, e);
            evaluation.setComplianceScore(0.0);
            evaluation.setStatus("ERROR");
            evaluation.setFindings(Arrays.asList("Error during evaluation: " + e.getMessage()));
        }
        
        return evaluation;
    }

    private double evaluatePolicyImplementation(String category, UUID tenantId) {
        // Simplified policy evaluation logic
        switch (category) {
            case "DATA_GOVERNANCE":
                return 85.0; // Data classification implemented
            case "ACCESS_CONTROL":
                return 92.0; // Strong access controls in place
            case "INCIDENT_MANAGEMENT":
                return 88.0; // Incident response procedures documented
            case "DATA_LIFECYCLE":
                return 90.0; // Data retention policies automated
            default:
                return 75.0; // Default score
        }
    }

    private List<String> generatePolicyFindings(String category, double score) {
        List<String> findings = new ArrayList<>();
        
        if (score >= 90.0) {
            findings.add("Policy implementation excellent");
        } else if (score >= 80.0) {
            findings.add("Policy implementation satisfactory");
        } else if (score >= 70.0) {
            findings.add("Policy implementation needs improvement");
        } else {
            findings.add("Policy implementation inadequate");
        }
        
        return findings;
    }

    private String calculateGovernanceLevel(double score) {
        if (score >= 90.0) return "EXCELLENT";
        if (score >= 80.0) return "GOOD";
        if (score >= 70.0) return "ADEQUATE";
        return "POOR";
    }

    private List<String> generateGovernanceRecommendations(List<PolicyEvaluation> evaluations) {
        List<String> recommendations = new ArrayList<>();
        
        for (PolicyEvaluation evaluation : evaluations) {
            if (evaluation.getComplianceScore() < 80.0) {
                recommendations.add(String.format("Improve %s implementation (current score: %.1f%%)",
                    evaluation.getPolicyName(), evaluation.getComplianceScore()));
            }
        }
        
        if (recommendations.isEmpty()) {
            recommendations.add("Continue maintaining current governance standards");
        }
        
        return recommendations;
    }

    private RuleEvaluation evaluateAccessRule(AccessControlRule rule, UUID tenantId, 
                                            String userId, String resource, String action) {
        RuleEvaluation evaluation = new RuleEvaluation();
        evaluation.setRuleId(rule.getRuleId());
        evaluation.setAllowed(true); // Default allow
        evaluation.setCritical(false);
        
        try {
            // Evaluate based on rule type
            switch (rule.getRuleType()) {
                case "TIME_BASED":
                    evaluation = evaluateTimeBasedRule(rule, userId);
                    break;
                case "DATA_CLASSIFICATION":
                    evaluation = evaluateDataClassificationRule(rule, resource);
                    break;
                case "TENANT_ISOLATION":
                    evaluation = evaluateTenantIsolationRule(rule, tenantId, resource);
                    break;
                default:
                    evaluation.setReason("Unknown rule type");
            }
        } catch (Exception e) {
            log.error("Error evaluating access rule {}", rule.getRuleId(), e);
            evaluation.setAllowed(false);
            evaluation.setReason("Error during rule evaluation");
        }
        
        return evaluation;
    }

    private RuleEvaluation evaluateTimeBasedRule(AccessControlRule rule, String userId) {
        RuleEvaluation evaluation = new RuleEvaluation();
        evaluation.setRuleId(rule.getRuleId());
        
        // Simplified time-based evaluation
        // In production, this would check actual time against allowed hours
        evaluation.setAllowed(true);
        evaluation.setReason("Time-based access allowed");
        
        return evaluation;
    }

    private RuleEvaluation evaluateDataClassificationRule(AccessControlRule rule, String resource) {
        RuleEvaluation evaluation = new RuleEvaluation();
        evaluation.setRuleId(rule.getRuleId());
        
        // Simplified data classification evaluation
        evaluation.setAllowed(true);
        evaluation.setReason("Data classification access allowed");
        
        return evaluation;
    }

    private RuleEvaluation evaluateTenantIsolationRule(AccessControlRule rule, UUID tenantId, String resource) {
        RuleEvaluation evaluation = new RuleEvaluation();
        evaluation.setRuleId(rule.getRuleId());
        
        // Simplified tenant isolation evaluation
        evaluation.setAllowed(true);
        evaluation.setReason("Tenant isolation verified");
        
        return evaluation;
    }

    private PolicyEffectiveness calculatePolicyEffectiveness(GovernancePolicy policy) {
        PolicyEffectiveness effectiveness = new PolicyEffectiveness();
        effectiveness.setPolicyId(policy.getPolicyId());
        effectiveness.setPolicyName(policy.getDefinition().getName());
        
        try {
            // Calculate effectiveness based on violations and compliance
            long totalViolations = policyViolations.values().stream()
                .filter(v -> v.getPolicyId().equals(policy.getPolicyId()))
                .count();
            
            long recentViolations = policyViolations.values().stream()
                .filter(v -> v.getPolicyId().equals(policy.getPolicyId()))
                .filter(v -> v.getDetectedAt().isAfter(Instant.now().minus(30, ChronoUnit.DAYS)))
                .count();
            
            // Effectiveness score based on violation trend
            double effectivenessScore = Math.max(0, 100 - (recentViolations * 10));
            effectiveness.setEffectivenessScore(effectivenessScore);
            effectiveness.setTotalViolations((int) totalViolations);
            effectiveness.setRecentViolations((int) recentViolations);
            
        } catch (Exception e) {
            log.error("Error calculating policy effectiveness for {}", policy.getPolicyId(), e);
            effectiveness.setEffectivenessScore(0.0);
        }
        
        return effectiveness;
    }

    private List<PolicyViolation> getRecentViolations(int days) {
        Instant cutoff = Instant.now().minus(days, ChronoUnit.DAYS);
        
        return policyViolations.values().stream()
            .filter(v -> v.getDetectedAt().isAfter(cutoff))
            .sorted((v1, v2) -> v2.getDetectedAt().compareTo(v1.getDetectedAt()))
            .limit(20)
            .collect(Collectors.toList());
    }

    // Data classes would be implemented here (similar structure to ComplianceFrameworkService)
    // Including GovernancePolicy, PolicyEvaluation, TenantGovernanceProfile, etc.
    
    // Event class for policy violations
    public static class PolicyViolationEvent {
        private final PolicyViolation violation;

        public PolicyViolationEvent(PolicyViolation violation) {
            this.violation = violation;
        }

        public PolicyViolation getViolation() {
            return violation;
        }
    }

    // Placeholder data classes (implement similar to ComplianceFrameworkService)
    public static class GovernancePolicy {
        private String policyId;
        private GovernancePolicyDefinition definition;
        private LocalDateTime createdAt;
        private LocalDateTime updatedAt;
        private boolean active;

        // Getters and setters
        public String getPolicyId() { return policyId; }
        public void setPolicyId(String policyId) { this.policyId = policyId; }
        public GovernancePolicyDefinition getDefinition() { return definition; }
        public void setDefinition(GovernancePolicyDefinition definition) { this.definition = definition; }
        public LocalDateTime getCreatedAt() { return createdAt; }
        public void setCreatedAt(LocalDateTime createdAt) { this.createdAt = createdAt; }
        public LocalDateTime getUpdatedAt() { return updatedAt; }
        public void setUpdatedAt(LocalDateTime updatedAt) { this.updatedAt = updatedAt; }
        public boolean isActive() { return active; }
        public void setActive(boolean active) { this.active = active; }
    }

    public static class GovernancePolicyDefinition {
        private String name;
        private String description;
        private String category;
        private String riskLevel;
        private boolean mandatory;
        private List<String> criteria;

        // Getters and setters
        public String getName() { return name; }
        public void setName(String name) { this.name = name; }
        public String getDescription() { return description; }
        public void setDescription(String description) { this.description = description; }
        public String getCategory() { return category; }
        public void setCategory(String category) { this.category = category; }
        public String getRiskLevel() { return riskLevel; }
        public void setRiskLevel(String riskLevel) { this.riskLevel = riskLevel; }
        public boolean isMandatory() { return mandatory; }
        public void setMandatory(boolean mandatory) { this.mandatory = mandatory; }
        public List<String> getCriteria() { return criteria; }
        public void setCriteria(List<String> criteria) { this.criteria = criteria; }
    }

    public static class TenantGovernanceProfile {
        private UUID tenantId;
        private TenantGovernanceProfileDefinition definition;
        private LocalDateTime createdAt;
        private LocalDateTime updatedAt;

        // Getters and setters
        public UUID getTenantId() { return tenantId; }
        public void setTenantId(UUID tenantId) { this.tenantId = tenantId; }
        public TenantGovernanceProfileDefinition getDefinition() { return definition; }
        public void setDefinition(TenantGovernanceProfileDefinition definition) { this.definition = definition; }
        public LocalDateTime getCreatedAt() { return createdAt; }
        public void setCreatedAt(LocalDateTime createdAt) { this.createdAt = createdAt; }
        public LocalDateTime getUpdatedAt() { return updatedAt; }
        public void setUpdatedAt(LocalDateTime updatedAt) { this.updatedAt = updatedAt; }
    }

    public static class TenantGovernanceProfileDefinition {
        private String organizationType;
        private String riskProfile;
        private List<String> complianceRequirements;
        private Map<String, String> customPolicies;

        // Getters and setters
        public String getOrganizationType() { return organizationType; }
        public void setOrganizationType(String organizationType) { this.organizationType = organizationType; }
        public String getRiskProfile() { return riskProfile; }
        public void setRiskProfile(String riskProfile) { this.riskProfile = riskProfile; }
        public List<String> getComplianceRequirements() { return complianceRequirements; }
        public void setComplianceRequirements(List<String> complianceRequirements) { this.complianceRequirements = complianceRequirements; }
        public Map<String, String> getCustomPolicies() { return customPolicies; }
        public void setCustomPolicies(Map<String, String> customPolicies) { this.customPolicies = customPolicies; }
    }

    public static class TenantGovernanceAssessment {
        private UUID tenantId;
        private LocalDateTime evaluatedAt;
        private double overallGovernanceScore;
        private String governanceLevel;
        private List<PolicyEvaluation> policyEvaluations;
        private int openViolations;
        private List<String> recommendations;
        private String errorMessage;

        // Getters and setters
        public UUID getTenantId() { return tenantId; }
        public void setTenantId(UUID tenantId) { this.tenantId = tenantId; }
        public LocalDateTime getEvaluatedAt() { return evaluatedAt; }
        public void setEvaluatedAt(LocalDateTime evaluatedAt) { this.evaluatedAt = evaluatedAt; }
        public double getOverallGovernanceScore() { return overallGovernanceScore; }
        public void setOverallGovernanceScore(double overallGovernanceScore) { this.overallGovernanceScore = overallGovernanceScore; }
        public String getGovernanceLevel() { return governanceLevel; }
        public void setGovernanceLevel(String governanceLevel) { this.governanceLevel = governanceLevel; }
        public List<PolicyEvaluation> getPolicyEvaluations() { return policyEvaluations; }
        public void setPolicyEvaluations(List<PolicyEvaluation> policyEvaluations) { this.policyEvaluations = policyEvaluations; }
        public int getOpenViolations() { return openViolations; }
        public void setOpenViolations(int openViolations) { this.openViolations = openViolations; }
        public List<String> getRecommendations() { return recommendations; }
        public void setRecommendations(List<String> recommendations) { this.recommendations = recommendations; }
        public String getErrorMessage() { return errorMessage; }
        public void setErrorMessage(String errorMessage) { this.errorMessage = errorMessage; }
    }

    public static class PolicyEvaluation {
        private String policyId;
        private String policyName;
        private LocalDateTime evaluatedAt;
        private double complianceScore;
        private String status;
        private List<String> findings;

        // Getters and setters
        public String getPolicyId() { return policyId; }
        public void setPolicyId(String policyId) { this.policyId = policyId; }
        public String getPolicyName() { return policyName; }
        public void setPolicyName(String policyName) { this.policyName = policyName; }
        public LocalDateTime getEvaluatedAt() { return evaluatedAt; }
        public void setEvaluatedAt(LocalDateTime evaluatedAt) { this.evaluatedAt = evaluatedAt; }
        public double getComplianceScore() { return complianceScore; }
        public void setComplianceScore(double complianceScore) { this.complianceScore = complianceScore; }
        public String getStatus() { return status; }
        public void setStatus(String status) { this.status = status; }
        public List<String> getFindings() { return findings; }
        public void setFindings(List<String> findings) { this.findings = findings; }
    }

    public static class PolicyViolation {
        public enum ViolationSeverity { LOW, MEDIUM, HIGH, CRITICAL }
        public enum ViolationStatus { OPEN, IN_PROGRESS, RESOLVED }

        private String violationId;
        private UUID tenantId;
        private String policyId;
        private String violationType;
        private String description;
        private ViolationSeverity severity;
        private ViolationStatus status;
        private Instant detectedAt;

        // Getters and setters
        public String getViolationId() { return violationId; }
        public void setViolationId(String violationId) { this.violationId = violationId; }
        public UUID getTenantId() { return tenantId; }
        public void setTenantId(UUID tenantId) { this.tenantId = tenantId; }
        public String getPolicyId() { return policyId; }
        public void setPolicyId(String policyId) { this.policyId = policyId; }
        public String getViolationType() { return violationType; }
        public void setViolationType(String violationType) { this.violationType = violationType; }
        public String getDescription() { return description; }
        public void setDescription(String description) { this.description = description; }
        public ViolationSeverity getSeverity() { return severity; }
        public void setSeverity(ViolationSeverity severity) { this.severity = severity; }
        public ViolationStatus getStatus() { return status; }
        public void setStatus(ViolationStatus status) { this.status = status; }
        public Instant getDetectedAt() { return detectedAt; }
        public void setDetectedAt(Instant detectedAt) { this.detectedAt = detectedAt; }
    }

    public static class AccessControlRule {
        private String ruleId;
        private String ruleName;
        private String description;
        private String ruleType;
        private boolean active;
        private Map<String, Object> conditions;

        public boolean appliesToTenant(UUID tenantId) {
            return true; // Simplified - would check tenant-specific conditions
        }

        // Getters and setters
        public String getRuleId() { return ruleId; }
        public void setRuleId(String ruleId) { this.ruleId = ruleId; }
        public String getRuleName() { return ruleName; }
        public void setRuleName(String ruleName) { this.ruleName = ruleName; }
        public String getDescription() { return description; }
        public void setDescription(String description) { this.description = description; }
        public String getRuleType() { return ruleType; }
        public void setRuleType(String ruleType) { this.ruleType = ruleType; }
        public boolean isActive() { return active; }
        public void setActive(boolean active) { this.active = active; }
        public Map<String, Object> getConditions() { return conditions; }
        public void setConditions(Map<String, Object> conditions) { this.conditions = conditions; }
    }

    public static class AccessDecision {
        private UUID tenantId;
        private String userId;
        private String resource;
        private String action;
        private Instant evaluatedAt;
        private String decision;
        private String reason;

        // Getters and setters
        public UUID getTenantId() { return tenantId; }
        public void setTenantId(UUID tenantId) { this.tenantId = tenantId; }
        public String getUserId() { return userId; }
        public void setUserId(String userId) { this.userId = userId; }
        public String getResource() { return resource; }
        public void setResource(String resource) { this.resource = resource; }
        public String getAction() { return action; }
        public void setAction(String action) { this.action = action; }
        public Instant getEvaluatedAt() { return evaluatedAt; }
        public void setEvaluatedAt(Instant evaluatedAt) { this.evaluatedAt = evaluatedAt; }
        public String getDecision() { return decision; }
        public void setDecision(String decision) { this.decision = decision; }
        public String getReason() { return reason; }
        public void setReason(String reason) { this.reason = reason; }
    }

    public static class RuleEvaluation {
        private String ruleId;
        private boolean allowed;
        private boolean critical;
        private String reason;

        // Getters and setters
        public String getRuleId() { return ruleId; }
        public void setRuleId(String ruleId) { this.ruleId = ruleId; }
        public boolean isAllowed() { return allowed; }
        public void setAllowed(boolean allowed) { this.allowed = allowed; }
        public boolean isCritical() { return critical; }
        public void setCritical(boolean critical) { this.critical = critical; }
        public String getReason() { return reason; }
        public void setReason(String reason) { this.reason = reason; }
    }

    public static class GovernanceDashboard {
        private LocalDateTime generatedAt;
        private int totalTenants;
        private int wellGovernedTenants;
        private int poorlyGovernedTenants;
        private double averageGovernanceScore;
        private int activePolicies;
        private int totalPolicies;
        private int openViolations;
        private int criticalViolations;
        private List<PolicyViolation> recentViolations;
        private String errorMessage;

        // Getters and setters
        public LocalDateTime getGeneratedAt() { return generatedAt; }
        public void setGeneratedAt(LocalDateTime generatedAt) { this.generatedAt = generatedAt; }
        public int getTotalTenants() { return totalTenants; }
        public void setTotalTenants(int totalTenants) { this.totalTenants = totalTenants; }
        public int getWellGovernedTenants() { return wellGovernedTenants; }
        public void setWellGovernedTenants(int wellGovernedTenants) { this.wellGovernedTenants = wellGovernedTenants; }
        public int getPoorlyGovernedTenants() { return poorlyGovernedTenants; }
        public void setPoorlyGovernedTenants(int poorlyGovernedTenants) { this.poorlyGovernedTenants = poorlyGovernedTenants; }
        public double getAverageGovernanceScore() { return averageGovernanceScore; }
        public void setAverageGovernanceScore(double averageGovernanceScore) { this.averageGovernanceScore = averageGovernanceScore; }
        public int getActivePolicies() { return activePolicies; }
        public void setActivePolicies(int activePolicies) { this.activePolicies = activePolicies; }
        public int getTotalPolicies() { return totalPolicies; }
        public void setTotalPolicies(int totalPolicies) { this.totalPolicies = totalPolicies; }
        public int getOpenViolations() { return openViolations; }
        public void setOpenViolations(int openViolations) { this.openViolations = openViolations; }
        public int getCriticalViolations() { return criticalViolations; }
        public void setCriticalViolations(int criticalViolations) { this.criticalViolations = criticalViolations; }
        public List<PolicyViolation> getRecentViolations() { return recentViolations; }
        public void setRecentViolations(List<PolicyViolation> recentViolations) { this.recentViolations = recentViolations; }
        public String getErrorMessage() { return errorMessage; }
        public void setErrorMessage(String errorMessage) { this.errorMessage = errorMessage; }
    }

    public static class PolicyEffectivenessReport {
        private LocalDateTime generatedAt;
        private List<PolicyEffectiveness> policyEffectiveness;
        private double overallEffectiveness;
        private String errorMessage;

        // Getters and setters
        public LocalDateTime getGeneratedAt() { return generatedAt; }
        public void setGeneratedAt(LocalDateTime generatedAt) { this.generatedAt = generatedAt; }
        public List<PolicyEffectiveness> getPolicyEffectiveness() { return policyEffectiveness; }
        public void setPolicyEffectiveness(List<PolicyEffectiveness> policyEffectiveness) { this.policyEffectiveness = policyEffectiveness; }
        public double getOverallEffectiveness() { return overallEffectiveness; }
        public void setOverallEffectiveness(double overallEffectiveness) { this.overallEffectiveness = overallEffectiveness; }
        public String getErrorMessage() { return errorMessage; }
        public void setErrorMessage(String errorMessage) { this.errorMessage = errorMessage; }
    }

    public static class PolicyEffectiveness {
        private String policyId;
        private String policyName;
        private double effectivenessScore;
        private int totalViolations;
        private int recentViolations;

        // Getters and setters
        public String getPolicyId() { return policyId; }
        public void setPolicyId(String policyId) { this.policyId = policyId; }
        public String getPolicyName() { return policyName; }
        public void setPolicyName(String policyName) { this.policyName = policyName; }
        public double getEffectivenessScore() { return effectivenessScore; }
        public void setEffectivenessScore(double effectivenessScore) { this.effectivenessScore = effectivenessScore; }
        public int getTotalViolations() { return totalViolations; }
        public void setTotalViolations(int totalViolations) { this.totalViolations = totalViolations; }
        public int getRecentViolations() { return recentViolations; }
        public void setRecentViolations(int recentViolations) { this.recentViolations = recentViolations; }
    }
}
