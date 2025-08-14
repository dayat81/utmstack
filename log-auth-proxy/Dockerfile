# Stage 1: Build the Go binary
FROM golang:1.23-alpine AS builder

WORKDIR /src

# Copy go.mod and go.sum to download dependencies first
COPY go.mod go.sum ./
RUN go mod download

# Copy the rest of the source code
COPY . .

# Build the application
RUN CGO_ENABLED=0 GOOS=linux go build -o /app/log-auth-proxy -v .

# Stage 2: Create the final image
FROM ubuntu:24.04

# Install runtime dependencies
RUN apt-get update && \
    apt-get install -y ca-certificates jq wget && \
    update-ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install grpcurl
RUN GRPCURL_VERSION=1.8.1 && \
    wget -O /tmp/grpcurl.tar.gz https://github.com/fullstorydev/grpcurl/releases/download/v${GRPCURL_VERSION}/grpcurl_${GRPCURL_VERSION}_linux_x86_64.tar.gz && \
    tar -xzf /tmp/grpcurl.tar.gz -C /usr/local/bin && \
    rm /tmp/grpcurl.tar.gz && \
    chmod +x /usr/local/bin/grpcurl

# Copy the built binary from the builder stage
COPY --from=builder /app/log-auth-proxy /app/log-auth-proxy

# Expose the gRPC log-auth-proxy port
EXPOSE 50051
EXPOSE 8080

# Run the log-auth-proxy binary
CMD ["/app/log-auth-proxy"]
