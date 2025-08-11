package com.park.utmstack.security;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.park.utmstack.domain.User;
import com.park.utmstack.domain.UtmTenant;
import com.park.utmstack.domain.UtmTenantRole;
import com.park.utmstack.repository.UserRepository;
import com.park.utmstack.repository.UtmTenantRepository;
import com.park.utmstack.repository.UtmTenantRoleRepository;
import com.park.utmstack.security.jwt.MultiTenantTokenProvider;
import com.park.utmstack.service.MultiTenantRBACService;
import com.park.utmstack.service.TenantProvisioningService;
import com.park.utmstack.service.TenantProvisioningService.TenantProvisioningRequest;
import com.park.utmstack.web.rest.vm.LoginVM;
import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import org.junit.jupiter.api.*;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureWebMvcSecurity;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.test.context.support.WithMockUser;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.context.WebApplicationContext;

import javax.crypto.SecretKey;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import static org.assertj.core.api.Assertions.*;
import static org.springframework.security.test.web.servlet.setup.SecurityMockMvcConfigurers.springSecurity;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/**
 * Comprehensive test suite for multi-tenant authentication and authorization.
 * Tests JWT token handling, RBAC permissions, and security isolation.
 */
@SpringBootTest
@AutoConfigureWebMvcSecurity
@ActiveProfiles("test")
@TestMethodOrder(MethodOrderer.OrderAnnotation.class)
public class MultiTenantAuthenticationTestSuite {

    private static final Logger log = LoggerFactory.getLogger(MultiTenantAuthenticationTestSuite.class);

    @Autowired private WebApplicationContext context;
    @Autowired private MultiTenantTokenProvider tokenProvider;
    @Autowired private MultiTenantRBACService rbacService;
    @Autowired private TenantProvisioningService tenantProvisioningService;
    @Autowired private UtmTenantRepository tenantRepository;
    @Autowired private UtmTenantRoleRepository tenantRoleRepository;
    @Autowired private UserRepository userRepository;
    @Autowired private ObjectMapper objectMapper;
    @Autowired private TenantContextFilter tenantContextFilter;

    @Value("${jhipster.security.authentication.jwt.base64-secret}")
    private String jwtSecret;

    private MockMvc mockMvc;
    private final List<UUID> testTenantIds = new ArrayList<>();
    private final List<String> testUserIds = new ArrayList<>();

    @BeforeEach
    void setUp() {
        mockMvc = MockMvcBuilders
            .webAppContextSetup(context)
            .apply(springSecurity())
            .build();
        TenantContext.clear();
    }

    @AfterEach
    void tearDown() {
        cleanup();
        TenantContext.clear();
        SecurityContextHolder.clearContext();
    }

    /**
     * Test 1: JWT Token with tenant claims
     */
    @Test
    @Order(1)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test JWT token creation with tenant claims")
    void testJWTTokenWithTenantClaims() throws Exception {
        log.info("Testing JWT token creation with tenant claims");

        // Create test tenant
        UUID tenantId = createTestTenant("JWT Test Tenant", "jwt-test");
        
        // Create test user with tenant context
        User user = createTestUser(tenantId, "jwt-test@example.com", "JWT", "Test", "USER");

        // Create authentication
        Collection<SimpleGrantedAuthority> authorities = List.of(
            new SimpleGrantedAuthority("ROLE_USER"),
            new SimpleGrantedAuthority("TENANT_USER")
        );
        Authentication authentication = new UsernamePasswordAuthenticationToken(
            user.getLogin(), null, authorities);

        // Set tenant context
        TenantContext.setTenantContext(tenantId.toString(), "jwt-test", "USER");

        // Generate token
        String token = tokenProvider.createToken(authentication, false);
        assertThat(token).isNotNull().isNotEmpty();

        // Validate token
        assertThat(tokenProvider.validateToken(token)).isTrue();

        // Extract and verify tenant claims
        Authentication authFromToken = tokenProvider.getAuthentication(token);
        assertThat(authFromToken).isNotNull();
        assertThat(authFromToken.getName()).isEqualTo(user.getLogin());

        // Decode JWT manually to verify tenant claims
        SecretKey key = Keys.hmacShaKeyFor(jwtSecret.getBytes(StandardCharsets.UTF_8));
        Claims claims = Jwts.parserBuilder()
            .setSigningKey(key)
            .build()
            .parseClaimsJws(token)
            .getBody();

        assertThat(claims.get("tenant_id")).isEqualTo(tenantId.toString());
        assertThat(claims.get("tenant_subdomain")).isEqualTo("jwt-test");
        assertThat(claims.get("tenant_role")).isEqualTo("USER");
    }

    /**
     * Test 2: Tenant context extraction from JWT
     */
    @Test
    @Order(2)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test tenant context extraction from JWT")
    void testTenantContextExtractionFromJWT() throws Exception {
        log.info("Testing tenant context extraction from JWT");

        UUID tenantId = createTestTenant("Context Test", "context-test");
        User user = createTestUser(tenantId, "context@example.com", "Context", "User", "ADMIN");

        // Set tenant context and create token
        TenantContext.setTenantContext(tenantId.toString(), "context-test", "ADMIN");
        
        Collection<SimpleGrantedAuthority> authorities = List.of(
            new SimpleGrantedAuthority("ROLE_USER"),
            new SimpleGrantedAuthority("TENANT_ADMIN")
        );
        Authentication auth = new UsernamePasswordAuthenticationToken(user.getLogin(), null, authorities);
        String token = tokenProvider.createToken(auth, false);

        // Clear context
        TenantContext.clear();
        assertThat(TenantContext.getCurrentTenant()).isNull();

        // Test context extraction via filter
        MockHttpServletRequest request = new MockHttpServletRequest();
        MockHttpServletResponse response = new MockHttpServletResponse();
        request.addHeader("Authorization", "Bearer " + token);

        tenantContextFilter.doFilter(request, response, (req, res) -> {
            // Verify context was extracted correctly
            assertThat(TenantContext.getCurrentTenant()).isEqualTo(tenantId.toString());
            assertThat(TenantContext.getCurrentTenantSubdomain()).isEqualTo("context-test");
            assertThat(TenantContext.getCurrentTenantRole()).isEqualTo("ADMIN");
        });
    }

    /**
     * Test 3: RBAC permission validation
     */
    @Test
    @Order(3)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test RBAC permission validation")
    void testRBACPermissionValidation() throws Exception {
        log.info("Testing RBAC permission validation");

        UUID tenantId = createTestTenant("RBAC Test", "rbac-test");

        // Create different roles with different permissions
        UtmTenantRole adminRole = createTenantRole(tenantId, "TENANT_ADMIN", Set.of(
            MultiTenantRBACService.Permissions.USER_MANAGEMENT,
            MultiTenantRBACService.Permissions.DASHBOARD_MANAGEMENT,
            MultiTenantRBACService.Permissions.ALERT_MANAGEMENT,
            MultiTenantRBACService.Permissions.TENANT_ADMIN
        ));

        UtmTenantRole userRole = createTenantRole(tenantId, "USER", Set.of(
            MultiTenantRBACService.Permissions.DASHBOARD_VIEW,
            MultiTenantRBACService.Permissions.ALERT_VIEW
        ));

        UtmTenantRole analystRole = createTenantRole(tenantId, "ANALYST", Set.of(
            MultiTenantRBACService.Permissions.DASHBOARD_VIEW,
            MultiTenantRBACService.Permissions.DASHBOARD_CREATE,
            MultiTenantRBACService.Permissions.ALERT_VIEW,
            MultiTenantRBACService.Permissions.ALERT_CREATE,
            MultiTenantRBACService.Permissions.INCIDENT_MANAGEMENT
        ));

        // Test admin permissions
        TenantContext.setTenantContext(tenantId.toString(), "rbac-test", "TENANT_ADMIN");
        assertThat(rbacService.hasPermission(MultiTenantRBACService.Permissions.USER_MANAGEMENT)).isTrue();
        assertThat(rbacService.hasPermission(MultiTenantRBACService.Permissions.DASHBOARD_MANAGEMENT)).isTrue();
        assertThat(rbacService.hasPermission(MultiTenantRBACService.Permissions.TENANT_ADMIN)).isTrue();
        assertThat(rbacService.isTenantAdmin()).isTrue();

        // Test user permissions (limited)
        TenantContext.setTenantContext(tenantId.toString(), "rbac-test", "USER");
        assertThat(rbacService.hasPermission(MultiTenantRBACService.Permissions.DASHBOARD_VIEW)).isTrue();
        assertThat(rbacService.hasPermission(MultiTenantRBACService.Permissions.DASHBOARD_CREATE)).isFalse();
        assertThat(rbacService.hasPermission(MultiTenantRBACService.Permissions.USER_MANAGEMENT)).isFalse();
        assertThat(rbacService.isTenantAdmin()).isFalse();

        // Test analyst permissions (intermediate)
        TenantContext.setTenantContext(tenantId.toString(), "rbac-test", "ANALYST");
        assertThat(rbacService.hasPermission(MultiTenantRBACService.Permissions.DASHBOARD_VIEW)).isTrue();
        assertThat(rbacService.hasPermission(MultiTenantRBACService.Permissions.DASHBOARD_CREATE)).isTrue();
        assertThat(rbacService.hasPermission(MultiTenantRBACService.Permissions.INCIDENT_MANAGEMENT)).isTrue();
        assertThat(rbacService.hasPermission(MultiTenantRBACService.Permissions.USER_MANAGEMENT)).isFalse();

        // Test hasAnyPermission and hasAllPermissions
        TenantContext.setTenantContext(tenantId.toString(), "rbac-test", "ANALYST");
        assertThat(rbacService.hasAnyPermission(
            MultiTenantRBACService.Permissions.DASHBOARD_CREATE,
            MultiTenantRBACService.Permissions.USER_MANAGEMENT
        )).isTrue();
        
        assertThat(rbacService.hasAllPermissions(
            MultiTenantRBACService.Permissions.DASHBOARD_VIEW,
            MultiTenantRBACService.Permissions.ALERT_VIEW
        )).isTrue();
        
        assertThat(rbacService.hasAllPermissions(
            MultiTenantRBACService.Permissions.DASHBOARD_VIEW,
            MultiTenantRBACService.Permissions.USER_MANAGEMENT
        )).isFalse();
    }

    /**
     * Test 4: Cross-tenant permission isolation
     */
    @Test
    @Order(4)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test cross-tenant permission isolation")
    void testCrossTenantPermissionIsolation() throws Exception {
        log.info("Testing cross-tenant permission isolation");

        UUID tenantA = createTestTenant("Permission Test A", "perm-test-a");
        UUID tenantB = createTestTenant("Permission Test B", "perm-test-b");

        // Create admin role in both tenants
        createTenantRole(tenantA, "ADMIN", Set.of(
            MultiTenantRBACService.Permissions.USER_MANAGEMENT,
            MultiTenantRBACService.Permissions.TENANT_ADMIN
        ));

        createTenantRole(tenantB, "USER", Set.of(
            MultiTenantRBACService.Permissions.DASHBOARD_VIEW
        ));

        // Test that admin in tenant A cannot access tenant B permissions
        TenantContext.setTenantContext(tenantA.toString(), "perm-test-a", "ADMIN");
        assertThat(rbacService.hasPermission(MultiTenantRBACService.Permissions.USER_MANAGEMENT)).isTrue();

        // Verify permissions are tenant-scoped
        assertThat(rbacService.hasPermission(tenantA, "ADMIN", MultiTenantRBACService.Permissions.USER_MANAGEMENT)).isTrue();
        assertThat(rbacService.hasPermission(tenantB, "ADMIN", MultiTenantRBACService.Permissions.USER_MANAGEMENT)).isFalse();

        // Switch to tenant B context
        TenantContext.setTenantContext(tenantB.toString(), "perm-test-b", "USER");
        assertThat(rbacService.hasPermission(MultiTenantRBACService.Permissions.USER_MANAGEMENT)).isFalse();
        assertThat(rbacService.hasPermission(MultiTenantRBACService.Permissions.DASHBOARD_VIEW)).isTrue();
    }

    /**
     * Test 5: Role hierarchy and inheritance
     */
    @Test
    @Order(5)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test role hierarchy and permission inheritance")
    void testRoleHierarchyAndInheritance() throws Exception {
        log.info("Testing role hierarchy and permission inheritance");

        UUID tenantId = createTestTenant("Hierarchy Test", "hierarchy-test");

        // Create base role
        UtmTenantRole baseRole = createTenantRole(tenantId, "BASE_USER", Set.of(
            MultiTenantRBACService.Permissions.DASHBOARD_VIEW,
            MultiTenantRBACService.Permissions.ALERT_VIEW
        ));

        // Create derived role that inherits from base
        UtmTenantRole analystRole = createTenantRole(tenantId, "ANALYST", Set.of(
            MultiTenantRBACService.Permissions.DASHBOARD_CREATE,
            MultiTenantRBACService.Permissions.ALERT_CREATE
        ), baseRole.getId());

        // Create admin role that inherits from analyst
        UtmTenantRole adminRole = createTenantRole(tenantId, "ADMIN", Set.of(
            MultiTenantRBACService.Permissions.USER_MANAGEMENT,
            MultiTenantRBACService.Permissions.TENANT_ADMIN
        ), analystRole.getId());

        // Test that admin has all permissions from hierarchy
        Set<String> adminPermissions = rbacService.getEffectivePermissions(tenantId, "ADMIN");
        assertThat(adminPermissions).contains(
            // Own permissions
            MultiTenantRBACService.Permissions.USER_MANAGEMENT,
            MultiTenantRBACService.Permissions.TENANT_ADMIN,
            // Inherited from analyst
            MultiTenantRBACService.Permissions.DASHBOARD_CREATE,
            MultiTenantRBACService.Permissions.ALERT_CREATE,
            // Inherited from base user
            MultiTenantRBACService.Permissions.DASHBOARD_VIEW,
            MultiTenantRBACService.Permissions.ALERT_VIEW
        );

        // Test that analyst has its own + base permissions
        Set<String> analystPermissions = rbacService.getEffectivePermissions(tenantId, "ANALYST");
        assertThat(analystPermissions).contains(
            MultiTenantRBACService.Permissions.DASHBOARD_CREATE,
            MultiTenantRBACService.Permissions.ALERT_CREATE,
            MultiTenantRBACService.Permissions.DASHBOARD_VIEW,
            MultiTenantRBACService.Permissions.ALERT_VIEW
        );
        assertThat(analystPermissions).doesNotContain(
            MultiTenantRBACService.Permissions.USER_MANAGEMENT
        );

        // Test context-based permission checking
        TenantContext.setTenantContext(tenantId.toString(), "hierarchy-test", "ADMIN");
        assertThat(rbacService.hasPermission(MultiTenantRBACService.Permissions.DASHBOARD_VIEW)).isTrue();
        assertThat(rbacService.hasPermission(MultiTenantRBACService.Permissions.DASHBOARD_CREATE)).isTrue();
        assertThat(rbacService.hasPermission(MultiTenantRBACService.Permissions.USER_MANAGEMENT)).isTrue();
    }

    /**
     * Test 6: JWT token tampering detection
     */
    @Test
    @Order(6)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test JWT token tampering detection")
    void testJWTTokenTamperingDetection() throws Exception {
        log.info("Testing JWT token tampering detection");

        UUID tenantId = createTestTenant("Security Test", "security-test");
        User user = createTestUser(tenantId, "security@example.com", "Security", "User", "USER");

        TenantContext.setTenantContext(tenantId.toString(), "security-test", "USER");
        
        Collection<SimpleGrantedAuthority> authorities = List.of(
            new SimpleGrantedAuthority("ROLE_USER")
        );
        Authentication auth = new UsernamePasswordAuthenticationToken(user.getLogin(), null, authorities);
        String validToken = tokenProvider.createToken(auth, false);

        // Test valid token
        assertThat(tokenProvider.validateToken(validToken)).isTrue();

        // Test token tampering scenarios
        String[] tamperedTokens = {
            validToken + "extra",  // Appended data
            "invalid" + validToken,  // Prepended data
            validToken.substring(0, validToken.length() - 5) + "12345",  // Modified signature
            validToken.replace('.', '_'),  // Invalid format
            "",  // Empty token
            "Bearer " + validToken,  // Wrong format (Bearer should be stripped)
            validToken.substring(0, validToken.indexOf('.'))  // Header only
        };

        for (String tamperedToken : tamperedTokens) {
            assertThat(tokenProvider.validateToken(tamperedToken))
                .as("Tampered token should be invalid: " + tamperedToken.substring(0, Math.min(20, tamperedToken.length())))
                .isFalse();
        }

        // Test expired token simulation (if tokenProvider supports it)
        // This would require creating a token with past expiration
    }

    /**
     * Test 7: Authentication API endpoints
     */
    @Test
    @Order(7)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test authentication API endpoints")
    void testAuthenticationAPIEndpoints() throws Exception {
        log.info("Testing authentication API endpoints");

        UUID tenantId = createTestTenant("API Auth Test", "api-auth-test");
        User user = createTestUser(tenantId, "apitest@example.com", "API", "Test", "USER");
        user.setPassword("$2a$10$VEjxo0jq2YG8oWmCU6tL5.OCGp9dLVOhqyE5vRSJdgKWfR5p1kQy.");  // "password"
        userRepository.save(user);

        LoginVM loginVM = new LoginVM();
        loginVM.setUsername("apitest@example.com");
        loginVM.setPassword("password");
        loginVM.setRememberMe(false);

        // Test login endpoint
        MvcResult result = mockMvc.perform(post("/api/authenticate")
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(loginVM)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id_token").exists())
                .andReturn();

        // Extract token and validate
        String responseJson = result.getResponse().getContentAsString();
        Map<String, Object> response = objectMapper.readValue(responseJson, Map.class);
        String token = (String) response.get("id_token");

        assertThat(tokenProvider.validateToken(token)).isTrue();
        
        // Verify tenant context is in token
        Authentication authFromToken = tokenProvider.getAuthentication(token);
        assertThat(authFromToken).isNotNull();
    }

    /**
     * Test 8: Concurrent authentication with different tenants
     */
    @Test
    @Order(8)
    @WithMockUser(authorities = "SUPER_ADMIN")
    @DisplayName("Test concurrent authentication with different tenants")
    void testConcurrentAuthentication() throws Exception {
        log.info("Testing concurrent authentication with different tenants");

        UUID tenantA = createTestTenant("Concurrent Auth A", "concurrent-auth-a");
        UUID tenantB = createTestTenant("Concurrent Auth B", "concurrent-auth-b");
        UUID tenantC = createTestTenant("Concurrent Auth C", "concurrent-auth-c");

        ExecutorService executor = Executors.newFixedThreadPool(10);
        List<CompletableFuture<Void>> futures = new ArrayList<>();

        // Create concurrent authentication operations
        for (int i = 0; i < 15; i++) {
            UUID tenant = switch (i % 3) {
                case 0 -> tenantA;
                case 1 -> tenantB;
                default -> tenantC;
            };
            
            int userIndex = i;
            futures.add(CompletableFuture.runAsync(() -> {
                try {
                    String subdomain = switch (tenant.equals(tenantA) ? 0 : tenant.equals(tenantB) ? 1 : 2) {
                        case 0 -> "concurrent-auth-a";
                        case 1 -> "concurrent-auth-b";
                        default -> "concurrent-auth-c";
                    };

                    User user = createTestUser(tenant, "user" + userIndex + "@test.com", "User", "Test" + userIndex, "USER");
                    
                    TenantContext.setTenantContext(tenant.toString(), subdomain, "USER");
                    
                    Collection<SimpleGrantedAuthority> authorities = List.of(
                        new SimpleGrantedAuthority("ROLE_USER")
                    );
                    Authentication auth = new UsernamePasswordAuthenticationToken(user.getLogin(), null, authorities);
                    String token = tokenProvider.createToken(auth, false);
                    
                    // Validate token
                    assertThat(tokenProvider.validateToken(token)).isTrue();
                    
                    // Verify tenant context in token
                    Authentication authFromToken = tokenProvider.getAuthentication(token);
                    assertThat(authFromToken).isNotNull();
                    
                } catch (Exception e) {
                    log.error("Concurrent authentication failed", e);
                    fail("Concurrent authentication failed", e);
                } finally {
                    TenantContext.clear();
                }
            }, executor));
        }

        // Wait for all operations to complete
        CompletableFuture.allOf(futures.toArray(new CompletableFuture[0])).join();
        executor.shutdown();
    }

    // Helper methods

    private UUID createTestTenant(String name, String subdomain) throws Exception {
        TenantProvisioningRequest request = new TenantProvisioningRequest();
        request.setName(name);
        request.setSubdomain(subdomain);
        request.setTier("standard");

        var result = tenantProvisioningService.provisionTenant(request).get();
        UUID tenantId = result.getTenantId();
        testTenantIds.add(tenantId);
        return tenantId;
    }

    private User createTestUser(UUID tenantId, String email, String firstName, String lastName, String role) {
        TenantContext.setCurrentTenant(tenantId);
        
        User user = new User();
        user.setEmail(email);
        user.setLogin(email);
        user.setFirstName(firstName);
        user.setLastName(lastName);
        user.setTenantId(tenantId);
        user.setActivated(true);
        
        User savedUser = userRepository.save(user);
        testUserIds.add(savedUser.getId());
        return savedUser;
    }

    private UtmTenantRole createTenantRole(UUID tenantId, String roleName, Set<String> permissions) {
        return createTenantRole(tenantId, roleName, permissions, null);
    }

    private UtmTenantRole createTenantRole(UUID tenantId, String roleName, Set<String> permissions, UUID parentRoleId) {
        return rbacService.createRole(tenantId, roleName, permissions, parentRoleId);
    }

    private void cleanup() {
        try {
            TenantContext.clear();
            // Cleanup users first (due to foreign key constraints)
            for (String userId : testUserIds) {
                try {
                    userRepository.deleteById(userId);
                } catch (Exception e) {
                    log.warn("Failed to cleanup user: {}", userId, e);
                }
            }
            testUserIds.clear();

            // Cleanup tenants
            for (UUID tenantId : testTenantIds) {
                try {
                    tenantRepository.deleteById(tenantId);
                } catch (Exception e) {
                    log.warn("Failed to cleanup tenant: {}", tenantId, e);
                }
            }
            testTenantIds.clear();
        } catch (Exception e) {
            log.error("Error during cleanup", e);
        }
    }

    // Mock classes for testing
    private static class MockHttpServletRequest extends org.springframework.mock.web.MockHttpServletRequest {
        // Extends MockHttpServletRequest with any needed customizations
    }

    private static class MockHttpServletResponse extends org.springframework.mock.web.MockHttpServletResponse {
        // Extends MockHttpServletResponse with any needed customizations
    }
}
