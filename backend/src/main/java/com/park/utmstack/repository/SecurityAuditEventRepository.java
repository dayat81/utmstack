package com.park.utmstack.repository;

import com.park.utmstack.domain.SecurityAuditEvent;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

@Repository
public interface SecurityAuditEventRepository extends JpaRepository<SecurityAuditEvent, Long> {

    List<SecurityAuditEvent> findByTenantIdAndTimestampBetween(UUID tenantId, Instant fromDate, Instant toDate);

    List<SecurityAuditEvent> findByTenantIdAndSeverityInAndTimestampGreaterThan(UUID tenantId, List<String> severities, Instant fromDate);

    long countByTenantIdAndEventTypeAndTimestampGreaterThan(UUID tenantId, String eventType, Instant fromDate);

    List<SecurityAuditEvent> findByTenantIdAndEventTypeInAndTimestampGreaterThan(UUID tenantId, List<String> eventTypes, Instant fromDate);

    @Modifying
    @Transactional
    @Query("DELETE FROM SecurityAuditEvent s WHERE s.timestamp < :cutoffDate")
    void deleteByTimestampBefore(@Param("cutoffDate") Instant cutoffDate);

    List<SecurityAuditEvent> findByTenantIdOrderByTimestampDesc(UUID tenantId);

    List<SecurityAuditEvent> findByTenantIdAndUserIdOrderByTimestampDesc(UUID tenantId, String userId);

    List<SecurityAuditEvent> findByTenantIdAndEventTypeOrderByTimestampDesc(UUID tenantId, String eventType);

    @Query("SELECT COUNT(s) FROM SecurityAuditEvent s WHERE s.tenantId = :tenantId AND s.severity IN :severities AND s.timestamp > :fromDate")
    long countBySeverityAndTimeframe(@Param("tenantId") UUID tenantId, @Param("severities") List<String> severities, @Param("fromDate") Instant fromDate);
}
