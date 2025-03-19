#!/bin/bash

# Production preparation script
# This script prepares your expense app for AWS deployment

echo "================================================================================"
echo "Preparing Expense App for production deployment to AWS"
echo "================================================================================"

# Check for required files and directories
echo "Checking project structure..."
REQUIRED_FILES=("app.py" "Dockerfile" "docker-compose.yml" ".env.production")
MISSING_FILES=0

for file in "${REQUIRED_FILES[@]}"; do
  if [ ! -f "$file" ]; then
    echo "❌ Missing required file: $file"
    MISSING_FILES=1
  else
    echo "✅ Found required file: $file"
  fi
done

if [ $MISSING_FILES -eq 1 ]; then
  echo "Please ensure all required files exist before deploying."
  exit 1
fi

# Make sure directories exist
mkdir -p data nginx/conf nginx/certbot/conf nginx/certbot/www
echo "✅ Created required directories"

# Make sure scripts are executable
chmod +x init-ssl.sh ec2-setup.sh test-docker.sh
echo "✅ Set execution permissions on scripts"

# Create a deployment package
echo "Creating deployment package..."
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DEPLOY_DIR="deploy_$TIMESTAMP"
mkdir -p "$DEPLOY_DIR"

# Copy required files
cp -r app.py Dockerfile docker-compose.yml requirements.txt static templates .env.production init-ssl.sh ec2-setup.sh nginx "$DEPLOY_DIR/"
cp README.md AWS_DEPLOYMENT.md LICENSE "$DEPLOY_DIR/"

# Create empty data directory
mkdir -p "$DEPLOY_DIR/data"

# Create archive
tar -czf "expense_app_deploy_$TIMESTAMP.tar.gz" "$DEPLOY_DIR"
rm -rf "$DEPLOY_DIR"

echo "================================================================================"
echo "Preparation complete!"
echo "Deployment package created: expense_app_deploy_$TIMESTAMP.tar.gz"
echo ""
echo "Next steps:"
echo "1. Transfer the deployment package to your EC2 instance"
echo "2. Extract the package on your EC2 instance"
echo "3. Run the ec2-setup.sh script"
echo "4. Set up SSL with init-ssl.sh"
echo "5. Deploy the application with docker-compose"
echo "================================================================================"