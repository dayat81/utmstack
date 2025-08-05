# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

UTMStack is an enterprise-ready SIEM (Security Information and Event Management) and XDR (Extended Detection and Response) platform built with a microservices architecture. The project combines real-time log correlation, threat intelligence, and malware activity pattern analysis to identify and halt complex cybersecurity threats.

## Architecture

UTMStack consists of multiple independent services that communicate via HTTP APIs, gRPC, and message queues:

### Core Components

- **Backend** (`/backend`): Spring Boot (Java 11) REST API server using JHipster framework, PostgreSQL database, and Elasticsearch integration
- **Frontend** (`/frontend`): Angular 7 SPA with TypeScript, Bootstrap UI, and real-time dashboard components
- **Correlation Engine** (`/correlation`): Go-based rules engine for real-time log analysis and threat detection
- **Agent Manager** (`/agent-manager`): gRPC server (Go) that manages UTMStack agents deployed across the network

### Supporting Services

- **Agent** (`/agent`): Lightweight Go client for log collection and system monitoring
- **Log Auth Proxy** (`/log-auth-proxy`): Go service handling authentication and routing for log ingestion
- **SOC AI** (`/soc-ai`): AI-powered threat analysis service using GPT integration
- **Cloud Integrations**: AWS (`/aws`), Office365 (`/office365`), Sophos (`/sophos`) connectors
- **Installer** (`/installer`): Go-based system installer and configuration manager

### Data Pipeline

- **Mutate** (`/mutate`): Python service for log parsing and transformation using Jinja2 templates
- **Filters** (`/filters`): Logstash configuration files for various log sources and formats

## Common Commands

### Backend Development (Java/Spring Boot)
```bash
cd backend
./mvnw spring-boot:run                    # Run development server
./mvnw clean package                      # Build WAR file
./mvnw test                              # Run tests
./mvnw liquibase:update                  # Update database schema
```

### Frontend Development (Angular)
```bash
cd frontend
npm install                              # Install dependencies
npm start                               # Run development server (http://localhost:4200)
npm run build                           # Build for production
npm run lint                            # Run linting
npm test                                # Run unit tests
```

### Go Services Development
```bash
# For any Go service (correlation, agent-manager, etc.)
go mod tidy                             # Download dependencies
go build .                              # Build binary
go test ./...                           # Run tests
go run main.go                          # Run development server

# Correlation engine specific
cd correlation
make install                            # Build and deploy with Docker
make uninstall                          # Remove Docker deployment
```

### Python Services (Mutate)
```bash
cd mutate
pip install -r requirements.txt        # Install dependencies
python main.py                         # Run service
```

## Development Guidelines

### Code Style
- **Java**: Follow Google Java Style Guide with Spring Boot conventions
- **TypeScript/Angular**: Follow Google TypeScript Style Guide
- **Go**: Follow standard Go formatting (`go fmt`) and Google Go Style Guide
- **Python**: Follow PEP 8 style guide

### Testing
- Add unit tests for all new functionality
- Backend: Use JUnit 5 and Spring Boot Test
- Frontend: Use Jasmine and Karma
- Go services: Use standard `testing` package

### Database Migrations
- Backend uses Liquibase for database schema management
- Migration files are in `backend/src/main/resources/config/liquibase/changelog/`
- Always create new migration files for schema changes

### Security Considerations
- All services use TLS for communication
- Authentication handled via JWT tokens
- gRPC services use mutual TLS authentication
- Never commit secrets or API keys to repository

## Configuration

### Environment Variables
- Backend configuration in `backend/src/main/resources/config/application*.yml`
- Go services typically use environment variables for configuration
- Docker deployments use environment-specific configuration files

### Docker Integration
- Each service has its own Dockerfile
- Services are orchestrated using Docker Compose or Docker Swarm
- Development and production configurations are separate

## Key Integrations

- **Elasticsearch/OpenSearch**: Primary data store for logs and alerts
- **PostgreSQL**: Relational database for configuration and metadata
- **gRPC**: Inter-service communication protocol
- **Logstash**: Log processing and parsing pipeline
- **JHipster**: Backend framework providing REST APIs and security

## Debugging and Monitoring

- Backend logs available via Spring Boot Actuator endpoints
- Go services use structured logging
- Health checks available for all containerized services
- Metrics and monitoring via built-in endpoints

## File Structure Notes

- `/filters`: Contains Logstash filter configurations for different log sources
- `/etc`: System configuration files and Docker configurations
- `/protos`: Protocol buffer definitions for gRPC services
- Version information maintained in `version.yml`