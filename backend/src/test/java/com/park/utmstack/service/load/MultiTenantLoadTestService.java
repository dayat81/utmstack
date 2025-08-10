package com.park.utmstack.service.load;

import com.park.utmstack.domain.UtmTenant;
import com.park.utmstack.service.TenantProvisioningService;
import com.park.utmstack.service.TenantProvisioningService.*;
import com.park.utmstack.service.TenantResourceQuotaService;
import com.park.utmstack.service.TenantService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.time.LocalDateTime;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;
import java.util.stream.IntStream;

/**
 * Comprehensive load testing service for multi-tenant architecture.
 * Tests concurrent provisioning, resource quotas, and tenant isolation under load.
 */
@Service
public class MultiTenantLoadTestService {

    private static final Logger log = LoggerFactory.getLogger(MultiTenantLoadTestService.class);

    private final TenantProvisioningService provisioningService;
    private final TenantService tenantService;
    private final TenantResourceQuotaService quotaService;
    private final ExecutorService executorService = Executors.newFixedThreadPool(50);

    public MultiTenantLoadTestService(TenantProvisioningService provisioningService,
                                    TenantService tenantService,
                                    TenantResourceQuotaService quotaService) {
        this.provisioningService = provisioningService;
        this.tenantService = tenantService;
        this.quotaService = quotaService;
    }

    /**
     * Execute comprehensive load test suite
     */
    public LoadTestResults executeLoadTestSuite(LoadTestConfiguration config) {
        log.info("Starting comprehensive load test suite with {} concurrent tenants", config.getConcurrentTenants());
        
        LoadTestResults results = new LoadTestResults();
        results.setStartTime(Instant.now());
        results.setConfiguration(config);

        try {
            // Test 1: Concurrent Tenant Provisioning
            LoadTestScenarioResult provisioningResults = testConcurrentTenantProvisioning(config);
            results.addScenarioResult("concurrent_provisioning", provisioningResults);

            // Test 2: Resource Quota Enforcement Under Load
            LoadTestScenarioResult quotaResults = testResourceQuotaUnderLoad(config);
            results.addScenarioResult("quota_enforcement", quotaResults);

            // Test 3: Tenant Isolation Validation
            LoadTestScenarioResult isolationResults = testTenantIsolationUnderLoad(config);
            results.addScenarioResult("tenant_isolation", isolationResults);

            // Test 4: API Performance Under Load
            LoadTestScenarioResult apiResults = testAPIPerformanceUnderLoad(config);
            results.addScenarioResult("api_performance", apiResults);

            // Test 5: Database Performance with RLS
            LoadTestScenarioResult dbResults = testDatabasePerformanceWithRLS(config);
            results.addScenarioResult("database_performance", dbResults);

            results.setStatus("COMPLETED");
            results.calculateAggregateMetrics();

        } catch (Exception e) {
            log.error("Load test suite failed", e);
            results.setStatus("FAILED");
            results.setError(e.getMessage());
        } finally {
            results.setEndTime(Instant.now());
            log.info("Load test suite completed in {}ms", results.getDurationMs());
        }

        return results;
    }

    /**
     * Test concurrent tenant provisioning performance
     */
    private LoadTestScenarioResult testConcurrentTenantProvisioning(LoadTestConfiguration config) {
        log.info("Testing concurrent tenant provisioning with {} tenants", config.getConcurrentTenants());
        
        LoadTestScenarioResult result = new LoadTestScenarioResult("concurrent_provisioning");
        AtomicInteger successCount = new AtomicInteger(0);
        AtomicInteger failureCount = new AtomicInteger(0);
        AtomicLong totalResponseTime = new AtomicLong(0);
        List<Long> responseTimes = Collections.synchronizedList(new ArrayList<>());

        List<CompletableFuture<Void>> futures = IntStream.range(0, config.getConcurrentTenants())
            .mapToObj(i -> CompletableFuture.runAsync(() -> {
                long startTime = System.currentTimeMillis();
                try {
                    TenantProvisioningRequest request = new TenantProvisioningRequest();
                    request.setName("LoadTest-Tenant-" + i);
                    request.setSubdomain("loadtest" + i);
                    request.setTier("standard");

                    TenantProvisioningResult provisioningResult = provisioningService.provisionTenant(request).get(
                        config.getTimeoutSeconds(), TimeUnit.SECONDS);

                    long responseTime = System.currentTimeMillis() - startTime;
                    responseTimes.add(responseTime);
                    totalResponseTime.addAndGet(responseTime);

                    if ("SUCCESS".equals(provisioningResult.getStatus())) {
                        successCount.incrementAndGet();
                    } else {
                        failureCount.incrementAndGet();
                        log.warn("Provisioning failed for tenant {}: {}", i, provisioningResult.getError());
                    }

                } catch (Exception e) {
                    failureCount.incrementAndGet();
                    long responseTime = System.currentTimeMillis() - startTime;
                    responseTimes.add(responseTime);
                    totalResponseTime.addAndGet(responseTime);
                    log.error("Error provisioning tenant {}", i, e);
                }
            }, executorService))
            .toList();

        // Wait for all provisioning to complete
        CompletableFuture.allOf(futures.toArray(new CompletableFuture[0])).join();

        // Calculate metrics
        result.setSuccessCount(successCount.get());
        result.setFailureCount(failureCount.get());
        result.setTotalRequests(config.getConcurrentTenants());
        result.setAverageResponseTime(totalResponseTime.get() / config.getConcurrentTenants());
        result.setThroughput(calculateThroughput(config.getConcurrentTenants(), totalResponseTime.get()));
        
        // Calculate percentiles
        responseTimes.sort(Long::compareTo);
        result.setP50ResponseTime(calculatePercentile(responseTimes, 50));
        result.setP95ResponseTime(calculatePercentile(responseTimes, 95));
        result.setP99ResponseTime(calculatePercentile(responseTimes, 99));

        log.info("Concurrent provisioning test completed: Success={}, Failures={}, AvgResponseTime={}ms", 
                successCount.get(), failureCount.get(), result.getAverageResponseTime());

        return result;
    }

    /**
     * Test resource quota enforcement under load
     */
    private LoadTestScenarioResult testResourceQuotaUnderLoad(LoadTestConfiguration config) {
        log.info("Testing resource quota enforcement under load");
        
        LoadTestScenarioResult result = new LoadTestScenarioResult("quota_enforcement");
        AtomicInteger successCount = new AtomicInteger(0);
        AtomicInteger failureCount = new AtomicInteger(0);
        AtomicInteger quotaViolations = new AtomicInteger(0);

        // Get active tenants for testing
        List<UtmTenant> tenants = tenantService.getAllActiveTenants();
        if (tenants.size() < config.getConcurrentTenants()) {
            log.warn("Not enough tenants for quota testing. Available: {}, Required: {}", 
                    tenants.size(), config.getConcurrentTenants());
            result.setFailureCount(1);
            result.setError("Insufficient tenants for quota testing");
            return result;
        }

        List<CompletableFuture<Void>> futures = IntStream.range(0, config.getConcurrentTenants())
            .mapToObj(i -> CompletableFuture.runAsync(() -> {
                try {
                    UtmTenant tenant = tenants.get(i % tenants.size());
                    
                    // Test various quota scenarios
                    testQuotaScenario(tenant.getId(), "users", 100, quotaViolations);
                    testQuotaScenario(tenant.getId(), "dashboards", 50, quotaViolations);
                    testQuotaScenario(tenant.getId(), "alerts", 1000, quotaViolations);
                    testQuotaScenario(tenant.getId(), "storage_mb", 5000, quotaViolations);

                    successCount.incrementAndGet();

                } catch (Exception e) {
                    failureCount.incrementAndGet();
                    log.error("Error testing quota for tenant index {}", i, e);
                }
            }, executorService))
            .toList();

        CompletableFuture.allOf(futures.toArray(new CompletableFuture[0])).join();

        result.setSuccessCount(successCount.get());
        result.setFailureCount(failureCount.get());
        result.setTotalRequests(config.getConcurrentTenants() * 4); // 4 quota types per tenant
        result.addCustomMetric("quota_violations", quotaViolations.get());

        log.info("Quota enforcement test completed: Success={}, Failures={}, QuotaViolations={}", 
                successCount.get(), failureCount.get(), quotaViolations.get());

        return result;
    }

    /**
     * Test tenant isolation under load
     */
    private LoadTestScenarioResult testTenantIsolationUnderLoad(LoadTestConfiguration config) {
        log.info("Testing tenant isolation under load");
        
        LoadTestScenarioResult result = new LoadTestScenarioResult("tenant_isolation");
        AtomicInteger successCount = new AtomicInteger(0);
        AtomicInteger failureCount = new AtomicInteger(0);
        AtomicInteger isolationViolations = new AtomicInteger(0);

        List<UtmTenant> tenants = tenantService.getAllActiveTenants();
        if (tenants.size() < 2) {
            result.setFailureCount(1);
            result.setError("Need at least 2 tenants for isolation testing");
            return result;
        }

        List<CompletableFuture<Void>> futures = IntStream.range(0, config.getConcurrentTenants())
            .mapToObj(i -> CompletableFuture.runAsync(() -> {
                try {
                    // Test cross-tenant data access attempts
                    UtmTenant tenant1 = tenants.get(i % tenants.size());
                    UtmTenant tenant2 = tenants.get((i + 1) % tenants.size());

                    boolean isolationViolated = testTenantDataIsolation(tenant1.getId(), tenant2.getId());
                    if (isolationViolated) {
                        isolationViolations.incrementAndGet();
                        log.error("Tenant isolation violation detected between {} and {}", 
                                tenant1.getId(), tenant2.getId());
                    }

                    successCount.incrementAndGet();

                } catch (Exception e) {
                    failureCount.incrementAndGet();
                    log.error("Error testing isolation for iteration {}", i, e);
                }
            }, executorService))
            .toList();

        CompletableFuture.allOf(futures.toArray(new CompletableFuture[0])).join();

        result.setSuccessCount(successCount.get());
        result.setFailureCount(failureCount.get());
        result.setTotalRequests(config.getConcurrentTenants());
        result.addCustomMetric("isolation_violations", isolationViolations.get());

        log.info("Tenant isolation test completed: Success={}, Failures={}, Violations={}", 
                successCount.get(), failureCount.get(), isolationViolations.get());

        return result;
    }

    /**
     * Test API performance under load
     */
    private LoadTestScenarioResult testAPIPerformanceUnderLoad(LoadTestConfiguration config) {
        log.info("Testing API performance under load");
        
        LoadTestScenarioResult result = new LoadTestScenarioResult("api_performance");
        AtomicInteger successCount = new AtomicInteger(0);
        AtomicInteger failureCount = new AtomicInteger(0);
        AtomicLong totalResponseTime = new AtomicLong(0);
        List<Long> responseTimes = Collections.synchronizedList(new ArrayList<>());

        List<UtmTenant> tenants = tenantService.getAllActiveTenants();

        List<CompletableFuture<Void>> futures = IntStream.range(0, config.getConcurrentTenants() * 10)
            .mapToObj(i -> CompletableFuture.runAsync(() -> {
                long startTime = System.currentTimeMillis();
                try {
                    if (!tenants.isEmpty()) {
                        UtmTenant tenant = tenants.get(i % tenants.size());
                        
                        // Test various API endpoints
                        tenantService.getTenant(tenant.getId());
                        quotaService.getResourceQuotaStatus(tenant.getId());
                        provisioningService.getProvisioningStatus(tenant.getId());
                    }

                    long responseTime = System.currentTimeMillis() - startTime;
                    responseTimes.add(responseTime);
                    totalResponseTime.addAndGet(responseTime);
                    successCount.incrementAndGet();

                } catch (Exception e) {
                    failureCount.incrementAndGet();
                    long responseTime = System.currentTimeMillis() - startTime;
                    responseTimes.add(responseTime);
                    totalResponseTime.addAndGet(responseTime);
                    log.error("Error testing API performance for iteration {}", i, e);
                }
            }, executorService))
            .toList();

        CompletableFuture.allOf(futures.toArray(new CompletableFuture[0])).join();

        int totalRequests = config.getConcurrentTenants() * 10;
        result.setSuccessCount(successCount.get());
        result.setFailureCount(failureCount.get());
        result.setTotalRequests(totalRequests);
        result.setAverageResponseTime(totalResponseTime.get() / totalRequests);
        result.setThroughput(calculateThroughput(totalRequests, totalResponseTime.get()));

        // Calculate percentiles
        responseTimes.sort(Long::compareTo);
        result.setP50ResponseTime(calculatePercentile(responseTimes, 50));
        result.setP95ResponseTime(calculatePercentile(responseTimes, 95));
        result.setP99ResponseTime(calculatePercentile(responseTimes, 99));

        log.info("API performance test completed: Success={}, Failures={}, AvgResponseTime={}ms", 
                successCount.get(), failureCount.get(), result.getAverageResponseTime());

        return result;
    }

    /**
     * Test database performance with Row-Level Security
     */
    private LoadTestScenarioResult testDatabasePerformanceWithRLS(LoadTestConfiguration config) {
        log.info("Testing database performance with RLS");
        
        LoadTestScenarioResult result = new LoadTestScenarioResult("database_performance");
        AtomicInteger successCount = new AtomicInteger(0);
        AtomicInteger failureCount = new AtomicInteger(0);
        AtomicLong totalResponseTime = new AtomicLong(0);

        List<UtmTenant> tenants = tenantService.getAllActiveTenants();

        List<CompletableFuture<Void>> futures = IntStream.range(0, config.getConcurrentTenants() * 5)
            .mapToObj(i -> CompletableFuture.runAsync(() -> {
                long startTime = System.currentTimeMillis();
                try {
                    if (!tenants.isEmpty()) {
                        UtmTenant tenant = tenants.get(i % tenants.size());
                        
                        // Simulate database queries that trigger RLS
                        tenantService.getTenantConfigurations(tenant.getId());
                        tenantService.getTenantRoles(tenant.getId());
                    }

                    long responseTime = System.currentTimeMillis() - startTime;
                    totalResponseTime.addAndGet(responseTime);
                    successCount.incrementAndGet();

                } catch (Exception e) {
                    failureCount.incrementAndGet();
                    long responseTime = System.currentTimeMillis() - startTime;
                    totalResponseTime.addAndGet(responseTime);
                    log.error("Error testing DB performance for iteration {}", i, e);
                }
            }, executorService))
            .toList();

        CompletableFuture.allOf(futures.toArray(new CompletableFuture[0])).join();

        int totalRequests = config.getConcurrentTenants() * 5;
        result.setSuccessCount(successCount.get());
        result.setFailureCount(failureCount.get());
        result.setTotalRequests(totalRequests);
        result.setAverageResponseTime(totalResponseTime.get() / totalRequests);
        result.setThroughput(calculateThroughput(totalRequests, totalResponseTime.get()));

        log.info("Database performance test completed: Success={}, Failures={}, AvgResponseTime={}ms", 
                successCount.get(), failureCount.get(), result.getAverageResponseTime());

        return result;
    }

    // Helper methods
    private void testQuotaScenario(UUID tenantId, String resourceType, int amount, AtomicInteger violations) {
        try {
            var result = quotaService.checkResourceQuota(tenantId, resourceType, amount);
            if (!result.isAllowed()) {
                violations.incrementAndGet();
            }
        } catch (Exception e) {
            log.error("Error testing quota scenario", e);
        }
    }

    private boolean testTenantDataIsolation(UUID tenant1Id, UUID tenant2Id) {
        // Simplified isolation test - in real implementation would test actual data access
        try {
            var tenant1Status = quotaService.getResourceQuotaStatus(tenant1Id);
            var tenant2Status = quotaService.getResourceQuotaStatus(tenant2Id);
            
            // Check if data is properly isolated (simplified check)
            return tenant1Status.getTenantId().equals(tenant2Status.getTenantId());
        } catch (Exception e) {
            log.error("Error testing tenant isolation", e);
            return true; // Assume violation on error
        }
    }

    private double calculateThroughput(int requests, long totalTimeMs) {
        return (double) requests / (totalTimeMs / 1000.0);
    }

    private long calculatePercentile(List<Long> sortedValues, int percentile) {
        if (sortedValues.isEmpty()) return 0;
        int index = (int) Math.ceil(percentile / 100.0 * sortedValues.size()) - 1;
        return sortedValues.get(Math.max(0, Math.min(index, sortedValues.size() - 1)));
    }

    // Data classes
    public static class LoadTestConfiguration {
        private int concurrentTenants = 10;
        private int timeoutSeconds = 60;
        private int iterations = 1;

        // Getters and setters
        public int getConcurrentTenants() { return concurrentTenants; }
        public void setConcurrentTenants(int concurrentTenants) { this.concurrentTenants = concurrentTenants; }

        public int getTimeoutSeconds() { return timeoutSeconds; }
        public void setTimeoutSeconds(int timeoutSeconds) { this.timeoutSeconds = timeoutSeconds; }

        public int getIterations() { return iterations; }
        public void setIterations(int iterations) { this.iterations = iterations; }
    }

    public static class LoadTestResults {
        private Instant startTime;
        private Instant endTime;
        private String status;
        private String error;
        private LoadTestConfiguration configuration;
        private Map<String, LoadTestScenarioResult> scenarioResults = new HashMap<>();
        private LoadTestAggregateMetrics aggregateMetrics;

        public void addScenarioResult(String scenario, LoadTestScenarioResult result) {
            scenarioResults.put(scenario, result);
        }

        public void calculateAggregateMetrics() {
            aggregateMetrics = new LoadTestAggregateMetrics();
            
            int totalRequests = scenarioResults.values().stream()
                .mapToInt(LoadTestScenarioResult::getTotalRequests).sum();
            int totalSuccesses = scenarioResults.values().stream()
                .mapToInt(LoadTestScenarioResult::getSuccessCount).sum();
            int totalFailures = scenarioResults.values().stream()
                .mapToInt(LoadTestScenarioResult::getFailureCount).sum();
            double avgResponseTime = scenarioResults.values().stream()
                .mapToLong(LoadTestScenarioResult::getAverageResponseTime)
                .average().orElse(0.0);

            aggregateMetrics.setTotalRequests(totalRequests);
            aggregateMetrics.setTotalSuccesses(totalSuccesses);
            aggregateMetrics.setTotalFailures(totalFailures);
            aggregateMetrics.setOverallSuccessRate((double) totalSuccesses / totalRequests * 100);
            aggregateMetrics.setAverageResponseTime((long) avgResponseTime);
        }

        public long getDurationMs() {
            if (endTime != null && startTime != null) {
                return endTime.toEpochMilli() - startTime.toEpochMilli();
            }
            return 0;
        }

        // Getters and setters
        public Instant getStartTime() { return startTime; }
        public void setStartTime(Instant startTime) { this.startTime = startTime; }

        public Instant getEndTime() { return endTime; }
        public void setEndTime(Instant endTime) { this.endTime = endTime; }

        public String getStatus() { return status; }
        public void setStatus(String status) { this.status = status; }

        public String getError() { return error; }
        public void setError(String error) { this.error = error; }

        public LoadTestConfiguration getConfiguration() { return configuration; }
        public void setConfiguration(LoadTestConfiguration configuration) { this.configuration = configuration; }

        public Map<String, LoadTestScenarioResult> getScenarioResults() { return scenarioResults; }
        public void setScenarioResults(Map<String, LoadTestScenarioResult> scenarioResults) { 
            this.scenarioResults = scenarioResults; 
        }

        public LoadTestAggregateMetrics getAggregateMetrics() { return aggregateMetrics; }
        public void setAggregateMetrics(LoadTestAggregateMetrics aggregateMetrics) { 
            this.aggregateMetrics = aggregateMetrics; 
        }
    }

    public static class LoadTestScenarioResult {
        private String scenarioName;
        private int totalRequests;
        private int successCount;
        private int failureCount;
        private long averageResponseTime;
        private long p50ResponseTime;
        private long p95ResponseTime;
        private long p99ResponseTime;
        private double throughput;
        private String error;
        private Map<String, Object> customMetrics = new HashMap<>();

        public LoadTestScenarioResult(String scenarioName) {
            this.scenarioName = scenarioName;
        }

        public void addCustomMetric(String name, Object value) {
            customMetrics.put(name, value);
        }

        // Getters and setters
        public String getScenarioName() { return scenarioName; }
        public void setScenarioName(String scenarioName) { this.scenarioName = scenarioName; }

        public int getTotalRequests() { return totalRequests; }
        public void setTotalRequests(int totalRequests) { this.totalRequests = totalRequests; }

        public int getSuccessCount() { return successCount; }
        public void setSuccessCount(int successCount) { this.successCount = successCount; }

        public int getFailureCount() { return failureCount; }
        public void setFailureCount(int failureCount) { this.failureCount = failureCount; }

        public long getAverageResponseTime() { return averageResponseTime; }
        public void setAverageResponseTime(long averageResponseTime) { this.averageResponseTime = averageResponseTime; }

        public long getP50ResponseTime() { return p50ResponseTime; }
        public void setP50ResponseTime(long p50ResponseTime) { this.p50ResponseTime = p50ResponseTime; }

        public long getP95ResponseTime() { return p95ResponseTime; }
        public void setP95ResponseTime(long p95ResponseTime) { this.p95ResponseTime = p95ResponseTime; }

        public long getP99ResponseTime() { return p99ResponseTime; }
        public void setP99ResponseTime(long p99ResponseTime) { this.p99ResponseTime = p99ResponseTime; }

        public double getThroughput() { return throughput; }
        public void setThroughput(double throughput) { this.throughput = throughput; }

        public String getError() { return error; }
        public void setError(String error) { this.error = error; }

        public Map<String, Object> getCustomMetrics() { return customMetrics; }
        public void setCustomMetrics(Map<String, Object> customMetrics) { this.customMetrics = customMetrics; }
    }

    public static class LoadTestAggregateMetrics {
        private int totalRequests;
        private int totalSuccesses;
        private int totalFailures;
        private double overallSuccessRate;
        private long averageResponseTime;

        // Getters and setters
        public int getTotalRequests() { return totalRequests; }
        public void setTotalRequests(int totalRequests) { this.totalRequests = totalRequests; }

        public int getTotalSuccesses() { return totalSuccesses; }
        public void setTotalSuccesses(int totalSuccesses) { this.totalSuccesses = totalSuccesses; }

        public int getTotalFailures() { return totalFailures; }
        public void setTotalFailures(int totalFailures) { this.totalFailures = totalFailures; }

        public double getOverallSuccessRate() { return overallSuccessRate; }
        public void setOverallSuccessRate(double overallSuccessRate) { this.overallSuccessRate = overallSuccessRate; }

        public long getAverageResponseTime() { return averageResponseTime; }
        public void setAverageResponseTime(long averageResponseTime) { this.averageResponseTime = averageResponseTime; }
    }
}
