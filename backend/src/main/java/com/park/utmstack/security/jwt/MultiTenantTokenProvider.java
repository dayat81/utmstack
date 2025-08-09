package com.park.utmstack.security.jwt;

import com.park.utmstack.domain.User;
import com.park.utmstack.security.AuthoritiesConstants;
import com.park.utmstack.util.CipherUtil;
import io.jsonwebtoken.*;
import io.jsonwebtoken.io.Decoders;
import io.jsonwebtoken.security.Keys;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.stereotype.Component;
import tech.jhipster.config.JHipsterProperties;

import java.security.Key;
import java.util.Arrays;
import java.util.Collection;
import java.util.Date;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * Enhanced JWT Token Provider with multi-tenant support.
 * Extends the original TokenProvider to include tenant context in JWT tokens.
 */
@Component
public class MultiTenantTokenProvider {

    private static final String CLASSNAME = "MultiTenantTokenProvider";
    private final Logger log = LoggerFactory.getLogger(MultiTenantTokenProvider.class);

    private static final String AUTHORITIES_KEY = "auth";
    private static final String AUTHENTICATED = "authenticated";
    private static final String TENANT_ID_KEY = "tenant_id";
    private static final String TENANT_ROLE_KEY = "tenant_role";
    private static final String TENANT_SUBDOMAIN_KEY = "tenant_subdomain";
    private static final String SECRET = CipherUtil.generateSafeToken();
    public static final long TEMP_TOKEN_VALIDITY_IN_MILLIS = 300000;

    private final Key key;
    private final JwtParser jwtParser;
    private final long tokenValidityInMilliseconds;
    private final long tokenValidityInMillisecondsForRememberMe;

    public MultiTenantTokenProvider(JHipsterProperties jHipsterProperties) {
        this.key = Keys.hmacShaKeyFor(Decoders.BASE64.decode(SECRET));
        jwtParser = Jwts.parserBuilder().setSigningKey(key).build();
        this.tokenValidityInMilliseconds =
            1000 * jHipsterProperties.getSecurity().getAuthentication().getJwt().getTokenValidityInSeconds();
        this.tokenValidityInMillisecondsForRememberMe =
            1000 * jHipsterProperties.getSecurity().getAuthentication().getJwt()
                .getTokenValidityInSecondsForRememberMe();
    }

    /**
     * Create JWT token with tenant context
     */
    public String createToken(Authentication authentication, String tenantId, boolean rememberMe, boolean authenticated) {
        final String ctx = CLASSNAME + ".createToken";

        try {
            String authorities = !authenticated ? AuthoritiesConstants.PRE_VERIFICATION_USER : 
                authentication.getAuthorities().stream()
                    .map(GrantedAuthority::getAuthority)
                    .collect(Collectors.joining(","));

            long now = (new Date()).getTime();
            Date validity;

            if (!authenticated) {
                validity = new Date(now + TEMP_TOKEN_VALIDITY_IN_MILLIS);
            } else {
                if (rememberMe) {
                    validity = new Date(now + this.tokenValidityInMillisecondsForRememberMe);
                } else {
                    validity = new Date(now + this.tokenValidityInMilliseconds);
                }
            }

            JwtBuilder jwtBuilder = Jwts.builder()
                .setSubject(authentication.getName())
                .claim(AUTHORITIES_KEY, authorities)
                .claim(AUTHENTICATED, authenticated)
                .signWith(key, SignatureAlgorithm.HS512)
                .setExpiration(validity);

            // Add tenant context if provided
            if (tenantId != null && !tenantId.isEmpty()) {
                jwtBuilder.claim(TENANT_ID_KEY, tenantId);
                
                // Extract tenant role from user if available
                String tenantRole = extractTenantRole(authentication, tenantId);
                if (tenantRole != null) {
                    jwtBuilder.claim(TENANT_ROLE_KEY, tenantRole);
                }
            }

            return jwtBuilder.compact();
        } catch (Exception e) {
            log.error(ctx + ": Failed to create JWT token", e);
            throw new RuntimeException(ctx + ": " + e.getMessage());
        }
    }

    /**
     * Create JWT token with tenant context - overloaded method
     */
    public String createToken(Authentication authentication, String tenantId, String tenantSubdomain, boolean rememberMe, boolean authenticated) {
        final String ctx = CLASSNAME + ".createToken";

        try {
            String authorities = !authenticated ? AuthoritiesConstants.PRE_VERIFICATION_USER : 
                authentication.getAuthorities().stream()
                    .map(GrantedAuthority::getAuthority)
                    .collect(Collectors.joining(","));

            long now = (new Date()).getTime();
            Date validity;

            if (!authenticated) {
                validity = new Date(now + TEMP_TOKEN_VALIDITY_IN_MILLIS);
            } else {
                if (rememberMe) {
                    validity = new Date(now + this.tokenValidityInMillisecondsForRememberMe);
                } else {
                    validity = new Date(now + this.tokenValidityInMilliseconds);
                }
            }

            JwtBuilder jwtBuilder = Jwts.builder()
                .setSubject(authentication.getName())
                .claim(AUTHORITIES_KEY, authorities)
                .claim(AUTHENTICATED, authenticated)
                .signWith(key, SignatureAlgorithm.HS512)
                .setExpiration(validity);

            // Add tenant context
            if (tenantId != null && !tenantId.isEmpty()) {
                jwtBuilder.claim(TENANT_ID_KEY, tenantId);
                
                String tenantRole = extractTenantRole(authentication, tenantId);
                if (tenantRole != null) {
                    jwtBuilder.claim(TENANT_ROLE_KEY, tenantRole);
                }
            }

            if (tenantSubdomain != null && !tenantSubdomain.isEmpty()) {
                jwtBuilder.claim(TENANT_SUBDOMAIN_KEY, tenantSubdomain);
            }

            return jwtBuilder.compact();
        } catch (Exception e) {
            log.error(ctx + ": Failed to create JWT token with subdomain", e);
            throw new RuntimeException(ctx + ": " + e.getMessage());
        }
    }

    /**
     * Extract authentication with tenant context
     */
    public UsernamePasswordAuthenticationToken getAuthentication(String token) {
        Claims claims = jwtParser.parseClaimsJws(token).getBody();
        
        Collection<? extends GrantedAuthority> authorities = Arrays
            .stream(claims.get(AUTHORITIES_KEY).toString().split(","))
            .filter(auth -> !auth.trim().isEmpty())
            .map(SimpleGrantedAuthority::new)
            .collect(Collectors.toList());

        // Create enhanced user principal with tenant context
        MultiTenantUserPrincipal principal = new MultiTenantUserPrincipal(
            claims.getSubject(),
            "",
            authorities,
            getTenantIdFromToken(token),
            getTenantSubdomainFromToken(token),
            getTenantRoleFromToken(token)
        );

        return new UsernamePasswordAuthenticationToken(principal, token, authorities);
    }

    /**
     * Extract tenant ID from JWT token
     */
    public String getTenantIdFromToken(String token) {
        try {
            Claims claims = jwtParser.parseClaimsJws(token).getBody();
            return claims.get(TENANT_ID_KEY, String.class);
        } catch (Exception e) {
            log.debug("Failed to extract tenant ID from token", e);
            return null;
        }
    }

    /**
     * Extract tenant subdomain from JWT token
     */
    public String getTenantSubdomainFromToken(String token) {
        try {
            Claims claims = jwtParser.parseClaimsJws(token).getBody();
            return claims.get(TENANT_SUBDOMAIN_KEY, String.class);
        } catch (Exception e) {
            log.debug("Failed to extract tenant subdomain from token", e);
            return null;
        }
    }

    /**
     * Extract tenant role from JWT token
     */
    public String getTenantRoleFromToken(String token) {
        try {
            Claims claims = jwtParser.parseClaimsJws(token).getBody();
            return claims.get(TENANT_ROLE_KEY, String.class);
        } catch (Exception e) {
            log.debug("Failed to extract tenant role from token", e);
            return null;
        }
    }

    /**
     * Check if token is authenticated
     */
    public Boolean isAuthenticated(String token) {
        try {
            Claims claims = jwtParser.parseClaimsJws(token).getBody();
            return claims.get(AUTHENTICATED, Boolean.class);
        } catch (Exception e) {
            log.debug("Failed to check authentication status", e);
            return false;
        }
    }

    /**
     * Extract user login from token
     */
    public String getUserLoginFromToken(String token) {
        try {
            Claims claims = jwtParser.parseClaimsJws(token).getBody();
            return claims.getSubject();
        } catch (Exception e) {
            log.debug("Failed to extract user login from token", e);
            return null;
        }
    }

    /**
     * Validate JWT token
     */
    public boolean validateToken(String authToken) {
        try {
            jwtParser.parseClaimsJws(authToken);
            return true;
        } catch (JwtException | IllegalArgumentException e) {
            log.info("Invalid JWT token: {}", e.getMessage());
            log.trace("Invalid JWT token trace.", e);
        }
        return false;
    }

    /**
     * Check if token belongs to a specific tenant
     */
    public boolean isTokenForTenant(String token, String tenantId) {
        String tokenTenantId = getTenantIdFromToken(token);
        return tokenTenantId != null && tokenTenantId.equals(tenantId);
    }

    /**
     * Validate token for specific tenant
     */
    public boolean validateTokenForTenant(String token, String tenantId) {
        return validateToken(token) && isTokenForTenant(token, tenantId);
    }

    /**
     * Extract tenant role from authentication (placeholder for implementation)
     * This would typically query the database for user's role within the tenant
     */
    private String extractTenantRole(Authentication authentication, String tenantId) {
        // TODO: Implement tenant role extraction logic
        // This should query utm_tenant_role table based on user and tenant
        // For now, return a default role
        if (authentication.getAuthorities().stream()
                .anyMatch(auth -> auth.getAuthority().equals(AuthoritiesConstants.ADMIN))) {
            return "TENANT_ADMIN";
        }
        return "TENANT_USER";
    }

    /**
     * Enhanced User Principal with tenant context
     */
    public static class MultiTenantUserPrincipal extends org.springframework.security.core.userdetails.User {
        
        private final String tenantId;
        private final String tenantSubdomain;
        private final String tenantRole;

        public MultiTenantUserPrincipal(String username, String password, 
                                       Collection<? extends GrantedAuthority> authorities,
                                       String tenantId, String tenantSubdomain, String tenantRole) {
            super(username, password, authorities);
            this.tenantId = tenantId;
            this.tenantSubdomain = tenantSubdomain;
            this.tenantRole = tenantRole;
        }

        public String getTenantId() {
            return tenantId;
        }

        public String getTenantSubdomain() {
            return tenantSubdomain;
        }

        public String getTenantRole() {
            return tenantRole;
        }

        public UUID getTenantIdAsUUID() {
            try {
                return tenantId != null ? UUID.fromString(tenantId) : null;
            } catch (IllegalArgumentException e) {
                return null;
            }
        }
    }
}
