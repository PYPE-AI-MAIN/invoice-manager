#!/bin/bash

# Test script for verifying the Docker setup locally

echo "================================================================================"
echo "TESTING DOCKER CONFIGURATION LOCALLY"
echo "================================================================================"

# Check if Docker is installed
if ! command -v docker >/dev/null 2>&1; then
    echo "Docker is not installed. Please install Docker first."
    exit 1
fi

# Check if Docker Compose is installed
if ! command -v docker-compose >/dev/null 2>&1; then
    echo "Docker Compose is not installed. Please install Docker Compose first."
    exit 1
fi

# Create test environment file if it doesn't exist
if [ ! -f .env.test ]; then
    echo "Creating test environment file..."
    cp .env.production .env.test
    # Update redirect URI for local testing
    sed -i'.bak' 's/https:\/\/internal.pypeai.com/http:\/\/localhost:8080/g' .env.test
    rm -f .env.test.bak 2>/dev/null || true  # Remove backup file
fi

# Create test docker-compose file
cat > docker-compose.test.yml <<EOL
version: '3'

services:
  expense-app:
    build: .
    image: expense-app:test
    restart: "no"
    ports:
      - "8080:8080"
    volumes:
      - ./data:/app/data
    env_file:
      - .env.test
EOL

echo "Building Docker image..."
docker-compose -f docker-compose.test.yml build

echo "Starting container for testing..."
docker-compose -f docker-compose.test.yml up -d

echo "Waiting for application to start..."
sleep 5

echo "Testing HTTP connection to application..."
if curl -s http://localhost:8080 | grep -q "Redirecting\|Login\|invoice"; then
    echo "✅ Application is responding on HTTP"
else
    echo "❌ Application is not responding correctly on HTTP"
    echo "Logs:"
    docker-compose -f docker-compose.test.yml logs
fi

echo "Stopping test container..."
docker-compose -f docker-compose.test.yml down

echo "================================================================================"
echo "Test completed. If all checks passed, the Docker configuration is ready for deployment."
echo "Next steps:"
echo "1. Set up an EC2 instance in AWS"
echo "2. Configure the domain DNS to point to the EC2 instance"
echo "3. Run the ec2-setup.sh script on the EC2 instance"
echo "4. Deploy the application using the instructions in the README.md"
echo "================================================================================"