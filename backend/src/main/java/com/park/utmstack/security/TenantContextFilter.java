package com.park.utmstack.security;

import com.park.utmstack.domain.UtmTenant;
import com.park.utmstack.repository.UtmTenantRepository;
import com.park.utmstack.security.jwt.MultiTenantTokenProvider;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;

import javax.servlet.*;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.Optional;
import java.util.UUID;

/**
 * Filter to extract and set tenant context from various sources.
 * Priority order: 1. JWT token, 2. Subdomain, 3. Header
 */
@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
public class TenantContextFilter implements Filter {

    private static final Logger log = LoggerFactory.getLogger(TenantContextFilter.class);

    private static final String TENANT_HEADER = "X-Tenant-ID";
    private static final String TENANT_SUBDOMAIN_HEADER = "X-Tenant-Subdomain";
    private static final String AUTHORIZATION_HEADER = "Authorization";
    private static final String BEARER_PREFIX = "Bearer ";

    private final MultiTenantTokenProvider tokenProvider;
    private final UtmTenantRepository tenantRepository;

    public TenantContextFilter(MultiTenantTokenProvider tokenProvider, UtmTenantRepository tenantRepository) {
        this.tokenProvider = tokenProvider;
        this.tenantRepository = tenantRepository;
    }

    @Override
    public void doFilter(ServletRequest request, ServletResponse response, FilterChain chain)
            throws IOException, ServletException {

        HttpServletRequest httpRequest = (HttpServletRequest) request;
        HttpServletResponse httpResponse = (HttpServletResponse) response;

        try {
            String tenantId = extractTenantId(httpRequest);
            
            if (tenantId != null) {
                // Validate tenant exists and is active
                if (!isValidTenant(tenantId)) {
                    log.warn("Invalid or inactive tenant: {}", tenantId);
                    httpResponse.sendError(HttpStatus.FORBIDDEN.value(), "Invalid or inactive tenant");
                    return;
                }

                // Set tenant context
                TenantContext.setCurrentTenant(tenantId);
                
                // Set additional tenant context if available
                String subdomain = extractTenantSubdomain(httpRequest);
                if (subdomain != null) {
                    TenantContext.setCurrentTenantSubdomain(subdomain);
                }

                String role = extractTenantRole(httpRequest);
                if (role != null) {
                    TenantContext.setCurrentTenantRole(role);
                }

                log.debug("Set tenant context for request: {}", TenantContext.getContextInfo());
            } else {
                // For system endpoints or pre-authentication requests, allow without tenant
                String requestPath = httpRequest.getRequestURI();
                if (!isSystemEndpoint(requestPath)) {
                    log.debug("No tenant context for non-system endpoint: {}", requestPath);
                }
            }

            // Proceed with the request
            chain.doFilter(request, response);

        } catch (Exception e) {
            log.error("Error processing tenant context filter", e);
            httpResponse.sendError(HttpStatus.INTERNAL_SERVER_ERROR.value(), "Internal server error");
        } finally {
            // Always clear tenant context after request
            TenantContext.clear();
        }
    }

    /**
     * Extract tenant ID from request with priority order:
     * 1. JWT token
     * 2. Subdomain
     * 3. X-Tenant-ID header
     */
    private String extractTenantId(HttpServletRequest request) {
        // Priority 1: Extract from JWT token
        String jwtTenant = extractFromJWT(request);
        if (jwtTenant != null) {
            log.debug("Tenant ID extracted from JWT: {}", jwtTenant);
            return jwtTenant;
        }

        // Priority 2: Extract from subdomain
        String subdomainTenant = extractFromSubdomain(request);
        if (subdomainTenant != null) {
            log.debug("Tenant ID extracted from subdomain: {}", subdomainTenant);
            return subdomainTenant;
        }

        // Priority 3: Extract from header
        String headerTenant = request.getHeader(TENANT_HEADER);
        if (StringUtils.hasText(headerTenant)) {
            log.debug("Tenant ID extracted from header: {}", headerTenant);
            return headerTenant;
        }

        return null;
    }

    /**
     * Extract tenant ID from JWT token
     */
    private String extractFromJWT(HttpServletRequest request) {
        String bearerToken = request.getHeader(AUTHORIZATION_HEADER);
        if (StringUtils.hasText(bearerToken) && bearerToken.startsWith(BEARER_PREFIX)) {
            String token = bearerToken.substring(BEARER_PREFIX.length());
            try {
                if (tokenProvider.validateToken(token)) {
                    return tokenProvider.getTenantIdFromToken(token);
                }
            } catch (Exception e) {
                log.debug("Failed to extract tenant from JWT token", e);
            }
        }
        return null;
    }

    /**
     * Extract tenant subdomain from request
     */
    private String extractTenantSubdomain(HttpServletRequest request) {
        // Priority 1: From JWT token
        String bearerToken = request.getHeader(AUTHORIZATION_HEADER);
        if (StringUtils.hasText(bearerToken) && bearerToken.startsWith(BEARER_PREFIX)) {
            String token = bearerToken.substring(BEARER_PREFIX.length());
            try {
                if (tokenProvider.validateToken(token)) {
                    String subdomain = tokenProvider.getTenantSubdomainFromToken(token);
                    if (subdomain != null) {
                        return subdomain;
                    }
                }
            } catch (Exception e) {
                log.debug("Failed to extract tenant subdomain from JWT token", e);
            }
        }

        // Priority 2: From subdomain
        return extractFromSubdomain(request);
    }

    /**
     * Extract tenant role from request
     */
    private String extractTenantRole(HttpServletRequest request) {
        String bearerToken = request.getHeader(AUTHORIZATION_HEADER);
        if (StringUtils.hasText(bearerToken) && bearerToken.startsWith(BEARER_PREFIX)) {
            String token = bearerToken.substring(BEARER_PREFIX.length());
            try {
                if (tokenProvider.validateToken(token)) {
                    return tokenProvider.getTenantRoleFromToken(token);
                }
            } catch (Exception e) {
                log.debug("Failed to extract tenant role from JWT token", e);
            }
        }
        return null;
    }

    /**
     * Extract tenant from subdomain
     * Supports patterns: tenant.utmstack.com -> tenant
     */
    private String extractFromSubdomain(HttpServletRequest request) {
        String serverName = request.getServerName();
        if (serverName != null) {
            String[] parts = serverName.split("\\.");
            
            // For pattern: tenant.utmstack.com
            if (parts.length >= 3) {
                String subdomain = parts[0];
                if (!"www".equals(subdomain) && !"api".equals(subdomain)) {
                    // Look up tenant by subdomain
                    Optional<UtmTenant> tenant = tenantRepository.findBySubdomain(subdomain);
                    if (tenant.isPresent()) {
                        return tenant.get().getId().toString();
                    }
                }
            }
        }
        return null;
    }

    /**
     * Check if tenant exists and is active
     */
    private boolean isValidTenant(String tenantId) {
        try {
            UUID tenantUUID = UUID.fromString(tenantId);
            Optional<UtmTenant> tenant = tenantRepository.findById(tenantUUID);
            return tenant.isPresent() && "active".equals(tenant.get().getStatus());
        } catch (IllegalArgumentException e) {
            log.warn("Invalid tenant ID format: {}", tenantId);
            return false;
        } catch (Exception e) {
            log.error("Error validating tenant: {}", tenantId, e);
            return false;
        }
    }

    /**
     * Check if the request path is a system endpoint that doesn't require tenant context
     */
    private boolean isSystemEndpoint(String requestPath) {
        return requestPath != null && (
            requestPath.startsWith("/api/authenticate") ||
            requestPath.startsWith("/api/account/reset-password") ||
            requestPath.startsWith("/api/register") ||
            requestPath.startsWith("/management/") ||
            requestPath.startsWith("/api/admin/tenants") ||  // Tenant management endpoints
            requestPath.startsWith("/v2/api-docs") ||
            requestPath.startsWith("/swagger-") ||
            requestPath.equals("/") ||
            requestPath.startsWith("/static/") ||
            requestPath.startsWith("/assets/")
        );
    }

    @Override
    public void init(FilterConfig filterConfig) throws ServletException {
        log.info("Initialized TenantContextFilter");
    }

    @Override
    public void destroy() {
        log.info("Destroyed TenantContextFilter");
    }
}
