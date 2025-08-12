package com.park.utmstack.service.compliance;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.util.*;

@Service
public class GovernancePolicyService {

    private static final Logger log = LoggerFactory.getLogger(GovernancePolicyService.class);
    
    public static class GovernancePolicy {
        private String id;
        private UUID tenantId;
        private String name;
        private Map<String, Object> rules;
        private String status;
        private Instant createdAt;
        
        public GovernancePolicy() {
            this.id = UUID.randomUUID().toString();
            this.createdAt = Instant.now();
            this.status = "ACTIVE";
            this.rules = new HashMap<>();
        }
        
        public String getId() { return id; }
        public void setId(String id) { this.id = id; }
        public UUID getTenantId() { return tenantId; }
        public void setTenantId(UUID tenantId) { this.tenantId = tenantId; }
        public String getName() { return name; }
        public void setName(String name) { this.name = name; }
        public Map<String, Object> getRules() { return rules; }
        public void setRules(Map<String, Object> rules) { this.rules = rules; }
        public String getStatus() { return status; }
        public void setStatus(String status) { this.status = status; }
        public Instant getCreatedAt() { return createdAt; }
        public void setCreatedAt(Instant createdAt) { this.createdAt = createdAt; }
    }
    
    public static class PolicyEvaluationResult {
        private String policyId;
        private boolean allowed;
        private String decision;
        private List<String> appliedRules;
        private Map<String, Object> context;
        
        public PolicyEvaluationResult() {
            this.appliedRules = new ArrayList<>();
            this.context = new HashMap<>();
        }
        
        public String getPolicyId() { return policyId; }
        public void setPolicyId(String policyId) { this.policyId = policyId; }
        public boolean isAllowed() { return allowed; }
        public void setAllowed(boolean allowed) { this.allowed = allowed; }
        public String getDecision() { return decision; }
        public void setDecision(String decision) { this.decision = decision; }
        public List<String> getAppliedRules() { return appliedRules; }
        public void setAppliedRules(List<String> appliedRules) { this.appliedRules = appliedRules; }
        public Map<String, Object> getContext() { return context; }
        public void setContext(Map<String, Object> context) { this.context = context; }
    }
    
    public static class DataClassificationResult {
        private String classification;
        private String sensitivity;
        private List<String> tags;
        private Map<String, Object> metadata;
        
        public DataClassificationResult() {
            this.tags = new ArrayList<>();
            this.metadata = new HashMap<>();
        }
        
        public String getClassification() { return classification; }
        public void setClassification(String classification) { this.classification = classification; }
        public String getSensitivity() { return sensitivity; }
        public void setSensitivity(String sensitivity) { this.sensitivity = sensitivity; }
        public List<String> getTags() { return tags; }
        public void setTags(List<String> tags) { this.tags = tags; }
        public Map<String, Object> getMetadata() { return metadata; }
        public void setMetadata(Map<String, Object> metadata) { this.metadata = metadata; }
    }
    
    private final Map<String, GovernancePolicy> policies = new HashMap<>();
    private final List<Map<String, Object>> policyViolations = new ArrayList<>();

    public GovernancePolicy createPolicy(UUID tenantId, Map<String, Object> policyDefinition) {
        try {
            GovernancePolicy policy = new GovernancePolicy();
            policy.setTenantId(tenantId);
            policy.setName((String) policyDefinition.getOrDefault("name", "Unnamed Policy"));
            policy.setRules((Map<String, Object>) policyDefinition.getOrDefault("rules", new HashMap<>()));
            
            policies.put(policy.getId(), policy);
            
            log.info("Created governance policy {} for tenant {}: {}", policy.getId(), tenantId, policy.getName());
            return policy;
        } catch (Exception e) {
            log.error("Failed to create governance policy for tenant: {}", tenantId, e);
            throw new RuntimeException("Failed to create policy", e);
        }
    }

    public PolicyEvaluationResult evaluatePolicy(UUID tenantId, String policyId, Map<String, Object> context) {
        try {
            PolicyEvaluationResult result = new PolicyEvaluationResult();
            result.setPolicyId(policyId);
            result.setContext(context);
            
            GovernancePolicy policy = policies.get(policyId);
            if (policy == null || !policy.getTenantId().equals(tenantId)) {
                result.setAllowed(false);
                result.setDecision("POLICY_NOT_FOUND");
                return result;
            }
            
            // Simple policy evaluation logic
            boolean allowed = evaluatePolicyRules(policy.getRules(), context);
            result.setAllowed(allowed);
            result.setDecision(allowed ? "ALLOW" : "DENY");
            result.getAppliedRules().add("tenant_isolation_rule");
            
            return result;
        } catch (Exception e) {
            log.error("Failed to evaluate policy {} for tenant {}", policyId, tenantId, e);
            PolicyEvaluationResult result = new PolicyEvaluationResult();
            result.setPolicyId(policyId);
            result.setAllowed(false);
            result.setDecision("ERROR");
            return result;
        }
    }

    public DataClassificationResult classifyData(UUID tenantId, String policyId, String data) {
        try {
            DataClassificationResult result = new DataClassificationResult();
            
            GovernancePolicy policy = policies.get(policyId);
            if (policy == null || !policy.getTenantId().equals(tenantId)) {
                result.setClassification("UNCLASSIFIED");
                result.setSensitivity("LOW");
                return result;
            }
            
            // Simple data classification logic
            if (data.toLowerCase().contains("password") || data.toLowerCase().contains("ssn")) {
                result.setClassification("CONFIDENTIAL");
                result.setSensitivity("HIGH");
                result.getTags().add("PII");
                result.getTags().add("SENSITIVE");
            } else if (data.toLowerCase().contains("email") || data.toLowerCase().contains("phone")) {
                result.setClassification("INTERNAL");
                result.setSensitivity("MEDIUM");
                result.getTags().add("PII");
            } else {
                result.setClassification("PUBLIC");
                result.setSensitivity("LOW");
            }
            
            log.debug("Classified data for tenant {} using policy {}: {}", tenantId, policyId, result.getClassification());
            return result;
        } catch (Exception e) {
            log.error("Failed to classify data for tenant {} policy {}", tenantId, policyId, e);
            DataClassificationResult result = new DataClassificationResult();
            result.setClassification("UNCLASSIFIED");
            result.setSensitivity("LOW");
            return result;
        }
    }

    public Map<String, Object> getGovernanceDashboard(UUID tenantId) {
        try {
            Map<String, Object> dashboard = new HashMap<>();
            
            long tenantPolicies = policies.values().stream()
                .filter(p -> p.getTenantId().equals(tenantId))
                .count();
            
            long violations = policyViolations.stream()
                .filter(v -> tenantId.equals(v.get("tenant_id")))
                .count();
            
            dashboard.put("tenant_id", tenantId.toString());
            dashboard.put("total_policies", tenantPolicies);
            dashboard.put("active_policies", tenantPolicies);
            dashboard.put("policy_violations", violations);
            dashboard.put("governance_score", violations == 0 ? "EXCELLENT" : "NEEDS_ATTENTION");
            dashboard.put("last_updated", Instant.now());
            
            return dashboard;
        } catch (Exception e) {
            log.error("Failed to get governance dashboard for tenant: {}", tenantId, e);
            Map<String, Object> errorDashboard = new HashMap<>();
            errorDashboard.put("status", "ERROR");
            errorDashboard.put("error", e.getMessage());
            return errorDashboard;
        }
    }

    public void recordPolicyViolation(UUID tenantId, String policyId, String description) {
        try {
            Map<String, Object> violation = new HashMap<>();
            violation.put("tenant_id", tenantId);
            violation.put("policy_id", policyId);
            violation.put("description", description);
            violation.put("timestamp", Instant.now());
            violation.put("severity", "MEDIUM");
            
            policyViolations.add(violation);
            
            log.warn("Policy violation recorded for tenant {} policy {}: {}", tenantId, policyId, description);
        } catch (Exception e) {
            log.error("Failed to record policy violation for tenant {} policy {}", tenantId, policyId, e);
        }
    }

    public Map<String, Object> getPolicyEffectiveness(UUID tenantId, String policyId) {
        try {
            Map<String, Object> effectiveness = new HashMap<>();
            
            GovernancePolicy policy = policies.get(policyId);
            if (policy == null || !policy.getTenantId().equals(tenantId)) {
                effectiveness.put("status", "POLICY_NOT_FOUND");
                return effectiveness;
            }
            
            long violations = policyViolations.stream()
                .filter(v -> tenantId.equals(v.get("tenant_id")) && policyId.equals(v.get("policy_id")))
                .count();
            
            effectiveness.put("policy_id", policyId);
            effectiveness.put("total_evaluations", 100); // Mock data
            effectiveness.put("violations", violations);
            effectiveness.put("effectiveness_score", violations == 0 ? "HIGH" : "MEDIUM");
            effectiveness.put("last_evaluated", Instant.now());
            
            return effectiveness;
        } catch (Exception e) {
            log.error("Failed to get policy effectiveness for tenant {} policy {}", tenantId, policyId, e);
            Map<String, Object> errorResult = new HashMap<>();
            errorResult.put("status", "ERROR");
            errorResult.put("error", e.getMessage());
            return errorResult;
        }
    }

    public GovernancePolicy updatePolicy(UUID tenantId, String policyId, Map<String, Object> updatedRules) {
        try {
            GovernancePolicy policy = policies.get(policyId);
            if (policy == null || !policy.getTenantId().equals(tenantId)) {
                throw new RuntimeException("Policy not found: " + policyId);
            }
            
            policy.setRules(updatedRules);
            
            log.info("Updated governance policy {} for tenant {}", policyId, tenantId);
            return policy;
        } catch (Exception e) {
            log.error("Failed to update policy {} for tenant {}", policyId, tenantId, e);
            throw new RuntimeException("Failed to update policy", e);
        }
    }

    public GovernancePolicy getPolicy(UUID tenantId, String policyId) {
        try {
            GovernancePolicy policy = policies.get(policyId);
            if (policy != null && policy.getTenantId().equals(tenantId)) {
                return policy;
            }
            return null;
        } catch (Exception e) {
            log.error("Failed to get policy {} for tenant {}", policyId, tenantId, e);
            return null;
        }
    }

    private boolean evaluatePolicyRules(Map<String, Object> rules, Map<String, Object> context) {
        // Simple rule evaluation - in real implementation this would be more sophisticated
        return true; // Default to allow for testing
    }
}
