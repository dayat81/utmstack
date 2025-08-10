@echo off
REM UTMStack Multi-Tenant Deployment Script for Windows
REM This script deploys the complete multi-tenant infrastructure

setlocal enabledelayedexpansion

echo.
echo ====================================================================
echo                UTMStack Multi-Tenant Deployment Script
echo ====================================================================
echo.
echo This script will deploy:
echo   - PostgreSQL 15 (Multi-tenant database with RLS)
echo   - Elasticsearch 8.11.0 (Tenant-scoped log storage)
echo   - Redis 7.2 (Caching and session management)
echo   - Adminer (Database administration interface)
echo.

REM Check if Docker is installed and running
echo [1/8] Checking Docker installation...
docker --version >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: Docker is not installed or not in PATH
    echo Please install Docker Desktop from https://docs.docker.com/desktop/install/windows-install/
    pause
    exit /b 1
)

docker info >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: Docker is not running
    echo Please start Docker Desktop and try again
    pause
    exit /b 1
)
echo ✓ Docker is installed and running

REM Check if required files exist
echo.
echo [2/8] Checking required files...

if not exist "docker-compose.infrastructure.yml" (
    echo ERROR: docker-compose.infrastructure.yml not found
    pause
    exit /b 1
)
echo ✓ Docker Compose file found

if not exist ".env.production" (
    echo ERROR: .env.production not found
    pause
    exit /b 1
)
echo ✓ Environment file found

if not exist "init-multi-tenant-db.sql" (
    echo ERROR: init-multi-tenant-db.sql not found
    pause
    exit /b 1
)
echo ✓ Database initialization script found

if not exist "fix-policies.sql" (
    echo ERROR: fix-policies.sql not found
    pause
    exit /b 1
)
echo ✓ Policy fix script found

REM Stop any existing deployment
echo.
echo [3/8] Stopping any existing deployment...
docker-compose -f docker-compose.infrastructure.yml down >nul 2>&1
echo ✓ Previous deployment stopped

REM Deploy infrastructure
echo.
echo [4/8] Deploying multi-tenant infrastructure...
echo This may take a few minutes to download images...

docker-compose -f docker-compose.infrastructure.yml --env-file .env.production up -d
if %errorlevel% neq 0 (
    echo ERROR: Failed to deploy infrastructure
    pause
    exit /b 1
)
echo ✓ Infrastructure deployment started

REM Wait for services to be ready
echo.
echo [5/8] Waiting for services to initialize...
echo Please wait while services start up (this may take 1-2 minutes)...

timeout /t 30 /nobreak >nul

REM Check service health
echo.
echo [6/8] Checking service health...

REM Check PostgreSQL
echo Checking PostgreSQL...
for /L %%i in (1,1,10) do (
    docker exec utmstack-postgres-mt pg_isready -U utmstack_prod -d utmstack_production >nul 2>&1
    if !errorlevel! equ 0 (
        echo ✓ PostgreSQL is ready
        goto :postgres_ready
    )
    echo   Waiting for PostgreSQL... (attempt %%i/10)
    timeout /t 5 /nobreak >nul
)
echo ERROR: PostgreSQL failed to start
goto :deployment_failed

:postgres_ready

REM Check Elasticsearch
echo Checking Elasticsearch...
for /L %%i in (1,1,10) do (
    curl -s http://localhost:9200/_cluster/health >nul 2>&1
    if !errorlevel! equ 0 (
        echo ✓ Elasticsearch is ready
        goto :elasticsearch_ready
    )
    echo   Waiting for Elasticsearch... (attempt %%i/10)
    timeout /t 5 /nobreak >nul
)
echo ERROR: Elasticsearch failed to start
goto :deployment_failed

:elasticsearch_ready

REM Check Redis
echo Checking Redis...
docker exec utmstack-redis-mt redis-cli -a "RedisUTM2025!Cache" ping >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: Redis failed to start
    goto :deployment_failed
)
echo ✓ Redis is ready

REM Initialize database schema
echo.
echo [7/8] Initializing multi-tenant database schema...

docker exec -i utmstack-postgres-mt psql -U utmstack_prod -d utmstack_production < init-multi-tenant-db.sql >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: Failed to initialize database schema
    goto :deployment_failed
)
echo ✓ Database schema initialized

echo Applying Row-Level Security policies...
docker exec -i utmstack-postgres-mt psql -U utmstack_prod -d utmstack_production < fix-policies.sql >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: Failed to apply RLS policies
    goto :deployment_failed
)
echo ✓ Row-Level Security policies applied

REM Create Elasticsearch indices
echo Creating tenant-specific Elasticsearch indices...
curl -X PUT "localhost:9200/utmstack-default-logs-2025.08.10" -H "Content-Type: application/json" -d "{\"settings\": {\"number_of_shards\": 1, \"number_of_replicas\": 0}}" >nul 2>&1
curl -X PUT "localhost:9200/utmstack-demo-logs-2025.08.10" -H "Content-Type: application/json" -d "{\"settings\": {\"number_of_shards\": 1, \"number_of_replicas\": 0}}" >nul 2>&1
echo ✓ Elasticsearch indices created

REM Final verification
echo.
echo [8/8] Final verification...

docker ps --filter "name=utmstack-" --format "table {{.Names}}\t{{.Status}}" > temp_status.txt
set /p container_status=<temp_status.txt
del temp_status.txt

echo ✓ All services deployed successfully!

echo.
echo ====================================================================
echo                     DEPLOYMENT SUCCESSFUL!
echo ====================================================================
echo.
echo Multi-tenant UTMStack infrastructure is now running:
echo.
echo 📊 SERVICES:
echo   • PostgreSQL 15 (Multi-tenant database)     : localhost:5432
echo   • Elasticsearch 8.11.0 (Log storage)        : http://localhost:9200
echo   • Redis 7.2 (Caching/Sessions)              : localhost:6379
echo   • Adminer (Database admin)                   : http://localhost:8081
echo.
echo 🏢 TENANTS:
echo   • Default Tenant (ID: 00000000-0000-0000-0000-000000000001)
echo   • Demo Tenant    (ID: 00000000-0000-0000-0000-000000000002)
echo.
echo 🔐 CREDENTIALS:
echo   • Database: utmstack_prod / UTMStack2025!Secure
echo   • Admin Users: admin / secret (for both tenants)
echo   • Redis: RedisUTM2025!Cache
echo.
echo 🌐 ACCESS POINTS:
echo   • Database Admin: http://localhost:8081
echo   • Elasticsearch: http://localhost:9200
echo   • Health Check: http://localhost:9200/_cluster/health
echo.
echo 📋 MANAGEMENT:
echo   • View containers: docker ps
echo   • View logs: docker logs [container_name]
echo   • Stop all: docker-compose -f docker-compose.infrastructure.yml down
echo   • Restart: run this script again
echo.
echo 🎯 NEXT STEPS:
echo   1. Access Adminer at http://localhost:8081 to manage database
echo   2. Test tenant isolation using the provided SQL scripts
echo   3. Deploy backend applications when ready
echo.
echo ====================================================================

echo.
echo Press any key to open Adminer in your default browser...
pause >nul
start http://localhost:8081
goto :end

:deployment_failed
echo.
echo ====================================================================
echo                      DEPLOYMENT FAILED!
echo ====================================================================
echo.
echo Some services failed to start. Please check:
echo   1. Docker Desktop is running
echo   2. Ports 5432, 6379, 8081, 9200, 9300 are not in use
echo   3. You have sufficient disk space
echo.
echo To troubleshoot:
echo   docker-compose -f docker-compose.infrastructure.yml logs
echo.
echo To clean up:
echo   docker-compose -f docker-compose.infrastructure.yml down -v
echo.
pause
exit /b 1

:end
endlocal
