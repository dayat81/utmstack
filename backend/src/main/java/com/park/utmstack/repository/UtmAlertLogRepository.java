package com.park.utmstack.repository;

import com.park.utmstack.domain.UtmAlertLog;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

@Repository
public interface UtmAlertLogRepository extends JpaRepository<UtmAlertLog, Long> {
}
