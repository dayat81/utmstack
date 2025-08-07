# AGENT.md - UTMStack Development Guide
sudo password is admin
## Quick Commands
```bash
# Backend (Java/Spring Boot)
cd backend && ./mvnw test                    # Run all tests
cd backend && ./mvnw test -Dtest=ClassName  # Run single test class
cd backend && ./mvnw spring-boot:run        # Dev server

# Frontend (Angular 7)
cd frontend && npm test                      # Run all tests
cd frontend && npm test -- --include="**/component.spec.ts"  # Run single test file
cd frontend && npm start                     # Dev server (port 4200)
cd frontend && npm run lint                  # Lint check

# Go services (correlation, agent-manager, etc.)
go test ./...                               # Run all tests in module
go test ./package -v -run TestFunctionName # Run single test
go test -short ./...                        # Run short tests only
go build . && go run main.go               # Build and run

# Python services (mutate)
cd mutate && pip install -r requirements.txt && python main.py
```

## Architecture
UTMStack is a microservices SIEM platform: Backend (Spring Boot/Java 11), Frontend (Angular 7), Correlation (Go), Agent-Manager (gRPC/Go), multiple cloud connectors (AWS, Office365, Sophos), data pipeline (Mutate/Python, Logstash filters), and supporting services.

## Code Style & Conventions
- **Java**: Google Style Guide, Spring Boot patterns, Liquibase migrations in `backend/src/main/resources/config/liquibase/changelog/`
- **TypeScript/Angular**: Google TypeScript Guide, component-based architecture  
- **Go**: Standard formatting (`go fmt`), Google Go Style Guide, structured logging
- **Python**: PEP 8 compliance
- Use existing imports/libraries found in neighboring files, never assume libraries are available
- Follow security: JWT auth, TLS communication, never commit secrets
- Add unit tests for new functionality (JUnit 5, Jasmine/Karma, Go testing package)
