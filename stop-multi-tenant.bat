@echo off
REM UTMStack Multi-Tenant Stop Script for Windows
REM This script stops all multi-tenant services and optionally removes data

setlocal enabledelayedexpansion

echo.
echo ====================================================================
echo              UTMStack Multi-Tenant Stop Script
echo ====================================================================
echo.

REM Check if Docker is running
docker info >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: Docker is not running
    echo Please start Docker Desktop first
    pause
    exit /b 1
)

REM Show current status
echo Current running UTMStack containers:
docker ps --filter "name=utmstack-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo.

REM Ask user what they want to do
echo What would you like to do?
echo   1. Stop services (keep data)
echo   2. Stop services and remove all data (complete cleanup)
echo   3. Just show status and exit
echo.
set /p choice="Enter your choice (1-3): "

if "%choice%"=="1" goto :stop_only
if "%choice%"=="2" goto :stop_and_clean
if "%choice%"=="3" goto :show_status
echo Invalid choice. Exiting...
pause
exit /b 1

:stop_only
echo.
echo [1/2] Stopping UTMStack multi-tenant services...
docker-compose -f docker-compose.infrastructure.yml down
if %errorlevel% neq 0 (
    echo ERROR: Failed to stop services
    pause
    exit /b 1
)
echo ✓ All services stopped successfully

echo.
echo [2/2] Verification...
set running_containers=0
for /f %%i in ('docker ps --filter "name=utmstack-" -q ^| find /c /v ""') do set running_containers=%%i

if !running_containers! equ 0 (
    echo ✓ All UTMStack containers have been stopped
    echo ✓ Data volumes are preserved
    echo.
    echo To restart: run deploy-multi-tenant.bat
) else (
    echo ⚠ Some containers may still be running
    docker ps --filter "name=utmstack-"
)
goto :end

:stop_and_clean
echo.
echo ⚠ WARNING: This will permanently delete all data!
echo   - Database data (all tenants, users, dashboards, alerts)
echo   - Elasticsearch indices (all logs)
echo   - Redis cache data
echo.
set /p confirm="Are you sure? Type 'yes' to confirm: "
if not "%confirm%"=="yes" (
    echo Operation cancelled.
    goto :end
)

echo.
echo [1/3] Stopping UTMStack multi-tenant services...
docker-compose -f docker-compose.infrastructure.yml down
echo ✓ Services stopped

echo.
echo [2/3] Removing data volumes...
docker-compose -f docker-compose.infrastructure.yml down -v
if %errorlevel% neq 0 (
    echo ERROR: Failed to remove volumes
    pause
    exit /b 1
)
echo ✓ Data volumes removed

echo.
echo [3/3] Cleaning up images (optional)...
set /p clean_images="Remove UTMStack Docker images? (y/n): "
if /i "%clean_images%"=="y" (
    docker rmi postgres:15-alpine >nul 2>&1
    docker rmi docker.elastic.co/elasticsearch/elasticsearch:8.11.0 >nul 2>&1
    docker rmi redis:7.2-alpine >nul 2>&1
    docker rmi adminer:4.8.1-standalone >nul 2>&1
    echo ✓ Docker images removed
)

echo.
echo ====================================================================
echo                    CLEANUP COMPLETED!
echo ====================================================================
echo.
echo All UTMStack multi-tenant services and data have been removed.
echo To redeploy: run deploy-multi-tenant.bat
echo.
goto :end

:show_status
echo.
echo ====================================================================
echo                  UTMStack Multi-Tenant Status
echo ====================================================================
echo.

REM Check running containers
set running_containers=0
for /f %%i in ('docker ps --filter "name=utmstack-" -q ^| find /c /v ""') do set running_containers=%%i

if !running_containers! equ 0 (
    echo Status: ❌ No UTMStack containers running
    echo.
    echo To start: run deploy-multi-tenant.bat
) else (
    echo Status: ✅ UTMStack containers running
    echo.
    echo Running containers:
    docker ps --filter "name=utmstack-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    
    echo.
    echo 🌐 Access Points:
    echo   • Database Admin: http://localhost:8081
    echo   • Elasticsearch: http://localhost:9200
    echo.
    
    REM Test service health
    echo 🔍 Quick Health Check:
    
    docker exec utmstack-postgres-mt pg_isready -U utmstack_prod -d utmstack_production >nul 2>&1
    if !errorlevel! equ 0 (
        echo   • PostgreSQL: ✅ Healthy
    ) else (
        echo   • PostgreSQL: ❌ Not responding
    )
    
    curl -s http://localhost:9200/_cluster/health >nul 2>&1
    if !errorlevel! equ 0 (
        echo   • Elasticsearch: ✅ Healthy
    ) else (
        echo   • Elasticsearch: ❌ Not responding
    )
    
    docker exec utmstack-redis-mt redis-cli -a "RedisUTM2025!Cache" ping >nul 2>&1
    if !errorlevel! equ 0 (
        echo   • Redis: ✅ Healthy
    ) else (
        echo   • Redis: ❌ Not responding
    )
)

REM Show volume information
echo.
echo 📦 Data Volumes:
for /f "tokens=*" %%i in ('docker volume ls --filter "name=utmstack_" --format "{{.Name}}"') do (
    echo   • %%i
)

echo.
echo ====================================================================

:end
echo.
pause
endlocal
