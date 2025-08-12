package com.park.utmstack.service.elasticsearch;

import com.park.utmstack.security.TenantContext;
import org.elasticsearch.action.search.SearchResponse;
import org.elasticsearch.search.SearchHit;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.util.*;

@Service
public class SearchIsolationValidator {

    private static final Logger log = LoggerFactory.getLogger(SearchIsolationValidator.class);

    @Autowired
    private MultiTenantElasticsearchService elasticsearchService;

    public static class IsolationViolation {
        private String index;
        private String documentId;
        private UUID documentTenantId;
        private UUID currentTenantId;
        private String violationType;

        public IsolationViolation(String index, String documentId, UUID documentTenantId, UUID currentTenantId, String violationType) {
            this.index = index;
            this.documentId = documentId;
            this.documentTenantId = documentTenantId;
            this.currentTenantId = currentTenantId;
            this.violationType = violationType;
        }

        public String getIndex() { return index; }
        public String getDocumentId() { return documentId; }
        public UUID getDocumentTenantId() { return documentTenantId; }
        public UUID getCurrentTenantId() { return currentTenantId; }
        public String getViolationType() { return violationType; }
    }

    public static class ValidationResult {
        private boolean isolated;
        private List<IsolationViolation> violations;
        private int totalDocuments;
        private int validatedDocuments;

        public ValidationResult() {
            this.violations = new ArrayList<>();
        }

        public boolean isIsolated() { return isolated; }
        public void setIsolated(boolean isolated) { this.isolated = isolated; }
        public List<IsolationViolation> getViolations() { return violations; }
        public void setViolations(List<IsolationViolation> violations) { this.violations = violations; }
        public int getTotalDocuments() { return totalDocuments; }
        public void setTotalDocuments(int totalDocuments) { this.totalDocuments = totalDocuments; }
        public int getValidatedDocuments() { return validatedDocuments; }
        public void setValidatedDocuments(int validatedDocuments) { this.validatedDocuments = validatedDocuments; }
    }

    public ValidationResult validateSearchIsolation(SearchResponse searchResponse) {
        ValidationResult result = new ValidationResult();
        UUID currentTenantId = TenantContext.getCurrentTenantId();
        
        if (currentTenantId == null) {
            log.warn("No tenant context available for validation");
            result.setIsolated(false);
            return result;
        }

        SearchHit[] hits = searchResponse.getHits().getHits();
        result.setTotalDocuments(hits.length);
        
        int validated = 0;
        boolean allIsolated = true;

        for (SearchHit hit : hits) {
            try {
                Map<String, Object> source = hit.getSourceAsMap();
                String docTenantIdStr = (String) source.get("tenant_id");
                
                if (docTenantIdStr == null) {
                    // Document missing tenant_id field
                    IsolationViolation violation = new IsolationViolation(
                        hit.getIndex(), hit.getId(), null, currentTenantId, "MISSING_TENANT_ID"
                    );
                    result.getViolations().add(violation);
                    allIsolated = false;
                    log.warn("Document {} in index {} missing tenant_id field", hit.getId(), hit.getIndex());
                } else {
                    UUID docTenantId = UUID.fromString(docTenantIdStr);
                    
                    if (!currentTenantId.equals(docTenantId)) {
                        // Cross-tenant access violation
                        IsolationViolation violation = new IsolationViolation(
                            hit.getIndex(), hit.getId(), docTenantId, currentTenantId, "CROSS_TENANT_ACCESS"
                        );
                        result.getViolations().add(violation);
                        allIsolated = false;
                        log.warn("Cross-tenant access violation: doc tenant {} != current tenant {} for document {} in index {}", 
                            docTenantId, currentTenantId, hit.getId(), hit.getIndex());
                    }
                }
                validated++;
            } catch (Exception e) {
                log.error("Failed to validate isolation for document {} in index {}: {}", 
                    hit.getId(), hit.getIndex(), e.getMessage());
                allIsolated = false;
            }
        }

        result.setValidatedDocuments(validated);
        result.setIsolated(allIsolated && result.getViolations().isEmpty());
        
        return result;
    }

    public ValidationResult validateTenantIndexIsolation(String type) {
        ValidationResult result = new ValidationResult();
        UUID currentTenantId = TenantContext.getCurrentTenantId();
        
        try {
            // Search for all documents in tenant indices
            SearchResponse response = elasticsearchService.search(type, 
                org.elasticsearch.index.query.QueryBuilders.matchAllQuery(), 0, 1000);
            
            return validateSearchIsolation(response);
            
        } catch (Exception e) {
            log.error("Failed to validate tenant index isolation for type {}: {}", type, e.getMessage());
            result.setIsolated(false);
            return result;
        }
    }

    public Map<String, ValidationResult> validateAllTenantIndices(List<String> types) {
        Map<String, ValidationResult> results = new HashMap<>();
        
        for (String type : types) {
            ValidationResult result = validateTenantIndexIsolation(type);
            results.put(type, result);
        }
        
        return results;
    }

    public boolean isDocumentAccessible(String type, String documentId) {
        try {
            return elasticsearchService.validateTenantIsolation(type, documentId);
        } catch (Exception e) {
            log.error("Failed to check document accessibility for {} in type {}: {}", 
                documentId, type, e.getMessage());
            return false;
        }
    }

    public ValidationResult performComprehensiveValidation(List<String> types) {
        ValidationResult overallResult = new ValidationResult();
        List<IsolationViolation> allViolations = new ArrayList<>();
        int totalDocs = 0;
        int totalValidated = 0;
        boolean allIsolated = true;

        for (String type : types) {
            ValidationResult typeResult = validateTenantIndexIsolation(type);
            
            allViolations.addAll(typeResult.getViolations());
            totalDocs += typeResult.getTotalDocuments();
            totalValidated += typeResult.getValidatedDocuments();
            
            if (!typeResult.isIsolated()) {
                allIsolated = false;
            }
        }

        overallResult.setViolations(allViolations);
        overallResult.setTotalDocuments(totalDocs);
        overallResult.setValidatedDocuments(totalValidated);
        overallResult.setIsolated(allIsolated);

        log.info("Comprehensive validation completed: {} types, {} documents, {} violations, isolated: {}", 
            types.size(), totalDocs, allViolations.size(), allIsolated);

        return overallResult;
    }
}
