#!/bin/bash

# Generate development certificates for UTMStack services

set -e

echo "Generating development certificates..."

# Create cert directory
mkdir -p ./cert

# Generate private key
openssl genrsa -out ./cert/utm.key 2048

# Generate certificate
openssl req -new -x509 -key ./cert/utm.key -out ./cert/utm.crt -days 365 -subj "/C=US/ST=FL/L=Coral Springs/O=UTMStack Development/CN=localhost"

# Set proper permissions
chmod 644 ./cert/utm.crt
chmod 600 ./cert/utm.key

echo "✓ Development certificates generated:"
echo "  Certificate: ./cert/utm.crt"
echo "  Private Key: ./cert/utm.key"

# Also copy to docker volume mount location if needed
echo "Certificates ready for development environment."
