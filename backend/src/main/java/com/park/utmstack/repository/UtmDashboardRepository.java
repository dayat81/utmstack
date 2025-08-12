package com.park.utmstack.repository;

import com.park.utmstack.domain.UtmDashboard;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

@Repository
public interface UtmDashboardRepository extends JpaRepository<UtmDashboard, Long> {
}
