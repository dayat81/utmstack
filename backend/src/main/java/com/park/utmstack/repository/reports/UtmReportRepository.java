package com.park.utmstack.repository.reports;

import com.park.utmstack.domain.reports.UtmReport;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

@Repository
public interface UtmReportRepository extends JpaRepository<UtmReport, Long> {
}
