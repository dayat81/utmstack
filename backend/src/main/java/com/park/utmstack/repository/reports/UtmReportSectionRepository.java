package com.park.utmstack.repository.reports;

import com.park.utmstack.domain.reports.UtmReportSection;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

@Repository
public interface UtmReportSectionRepository extends JpaRepository<UtmReportSection, Long> {
}
