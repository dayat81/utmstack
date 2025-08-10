@echo off
REM UTMStack Multi-Tenant Status Script for Windows
REM This script shows the current status of all multi-tenant services

setlocal enabledelayedexpansion

echo.
echo ====================================================================
echo              UTMStack Multi-Tenant Status Monitor
echo ====================================================================
echo Current Time: %date% %time%
echo.

REM Check if Docker is running
docker info >nul 2>&1
if %errorlevel% neq 0 (
    echo Status: ❌ Docker is not running
    echo Please start Docker Desktop first
    pause
    exit /b 1
)

REM Check running containers
echo 📋 CONTAINER STATUS:
echo.
set running_containers=0
for /f %%i in ('docker ps --filter "name=utmstack-" -q ^| find /c /v ""') do set running_containers=%%i

if !running_containers! equ 0 (
    echo Status: ❌ No UTMStack containers running
    echo.
    echo To start deployment: run deploy-multi-tenant.bat
    goto :end
)

docker ps --filter "name=utmstack-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}\t{{.Image}}"
echo.

REM Health checks
echo 🔍 HEALTH CHECKS:
echo.

REM PostgreSQL Health
echo Checking PostgreSQL...
docker exec utmstack-postgres-mt pg_isready -U utmstack_prod -d utmstack_production >nul 2>&1
if !errorlevel! equ 0 (
    echo ✅ PostgreSQL: Healthy
    
    REM Get PostgreSQL details
    for /f "tokens=*" %%i in ('docker exec utmstack-postgres-mt psql -U utmstack_prod -d utmstack_production -t -c "SELECT COUNT(*) FROM utm_tenant;" 2^>nul') do (
        set tenant_count=%%i
    )
    set tenant_count=!tenant_count: =!
    if "!tenant_count!" neq "" (
        echo    • Tenants configured: !tenant_count!
    )
    
    for /f "tokens=*" %%i in ('docker exec utmstack-postgres-mt psql -U utmstack_prod -d utmstack_production -t -c "SELECT COUNT(*) FROM jhi_user;" 2^>nul') do (
        set user_count=%%i
    )
    set user_count=!user_count: =!
    if "!user_count!" neq "" (
        echo    • Total users: !user_count!
    )
) else (
    echo ❌ PostgreSQL: Not responding
)

REM Elasticsearch Health
echo.
echo Checking Elasticsearch...
curl -s http://localhost:9200/_cluster/health >temp_es_health.json 2>nul
if !errorlevel! equ 0 (
    echo ✅ Elasticsearch: Healthy
    
    REM Parse Elasticsearch status
    for /f "tokens=*" %%i in ('curl -s "http://localhost:9200/_cat/indices?h=index" 2^>nul ^| find "utmstack-" ^| find /c /v ""') do (
        set index_count=%%i
    )
    if "!index_count!" neq "" (
        echo    • UTMStack indices: !index_count!
    )
    
    for /f "tokens=*" %%i in ('curl -s "http://localhost:9200/_cluster/health" 2^>nul ^| find "status" ^| findstr /o "green\|yellow\|red"') do (
        set es_status=%%i
    )
    if "!es_status!" neq "" (
        echo    • Cluster status: !es_status!
    )
) else (
    echo ❌ Elasticsearch: Not responding
)
if exist temp_es_health.json del temp_es_health.json

REM Redis Health
echo.
echo Checking Redis...
docker exec utmstack-redis-mt redis-cli -a "RedisUTM2025!Cache" ping >nul 2>&1
if !errorlevel! equ 0 (
    echo ✅ Redis: Healthy
    
    REM Get Redis info
    for /f "tokens=*" %%i in ('docker exec utmstack-redis-mt redis-cli -a "RedisUTM2025!Cache" info memory 2^>nul ^| find "used_memory_human" ^| cut -d: -f2 2^>nul') do (
        set redis_memory=%%i
    )
    if "!redis_memory!" neq "" (
        echo    • Memory usage: !redis_memory!
    )
) else (
    echo ❌ Redis: Not responding
)

REM Adminer Health
echo.
echo Checking Adminer...
curl -s http://localhost:8081 >nul 2>&1
if !errorlevel! equ 0 (
    echo ✅ Adminer: Accessible at http://localhost:8081
) else (
    echo ❌ Adminer: Not responding
)

REM Resource usage
echo.
echo 📊 RESOURCE USAGE:
echo.
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" --filter "name=utmstack-" 2>nul

REM Volume information
echo.
echo 📦 DATA VOLUMES:
echo.
for /f "tokens=*" %%i in ('docker volume ls --filter "name=utmstack_" --format "{{.Name}}" 2^>nul') do (
    echo • %%i
    for /f "tokens=*" %%j in ('docker volume inspect %%i --format "{{.Mountpoint}}" 2^>nul') do (
        echo    Location: %%j
    )
)

REM Network information
echo.
echo 🌐 NETWORK INFORMATION:
echo.
for /f "tokens=*" %%i in ('docker network ls --filter "name=utmstack" --format "{{.Name}}" 2^>nul') do (
    echo • Network: %%i
    docker network inspect %%i --format "  Subnet: {{range .IPAM.Config}}{{.Subnet}}{{end}}" 2>nul
)

REM Access information
echo.
echo 🔗 ACCESS POINTS:
echo.
echo • Database Admin (Adminer): http://localhost:8081
echo • Elasticsearch API: http://localhost:9200
echo • Elasticsearch Health: http://localhost:9200/_cluster/health
echo • Elasticsearch Indices: http://localhost:9200/_cat/indices?v
echo.
echo 🔐 CREDENTIALS:
echo • Database: utmstack_prod / UTMStack2025!Secure
echo • Redis: RedisUTM2025!Cache
echo • Admin Users: admin / secret
echo.

REM Show recent logs
echo 📝 RECENT LOGS (last 10 lines):
echo.
for %%c in (utmstack-postgres-mt utmstack-elasticsearch-mt utmstack-redis-mt utmstack-adminer-mt) do (
    echo [%%c]:
    docker logs --tail 3 %%c 2>nul | findstr /v "^$"
    echo.
)

echo ====================================================================
echo Status check completed at %date% %time%
echo.
echo 🔄 Auto-refresh? (y/n) 
set /p refresh="Press Y to refresh status or any other key to exit: "
if /i "%refresh%"=="y" (
    cls
    goto :start
)

:start
goto :top

:top
cls
goto :0

:end
echo.
pause
endlocal
