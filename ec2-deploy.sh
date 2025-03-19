#!/bin/bash

# Simple EC2 Docker Deployment Script for Invoice Manager
# ------------------------------------------------------
# This script creates the necessary files and instructions for deploying 
# the Invoice Manager application to AWS EC2 using Docker
#
# Usage: ./ec2-deploy.sh <domain> <email>
# Example: ./ec2-deploy.sh example.com user@example.com

# Set up error handling
set -e
trap 'echo "An error occurred. Script failed."' ERR

# Check for required parameters
if [ "$#" -lt 2 ]; then
  echo "Error: Missing required parameters"
  echo "Usage: ./ec2-deploy.sh <domain> <email>"
  echo "Example: ./ec2-deploy.sh example.com user@example.com"
  exit 1
fi

DOMAIN=$1
EMAIL=$2

echo "============================================================="
echo "Creating deployment files for AWS EC2 Docker deployment"
echo "Domain: $DOMAIN"
echo "Email: $EMAIL"
echo "============================================================="

# Step 1: Create EC2 setup script
cat > ec2-setup.sh <<EOL
#!/bin/bash

# EC2 Setup Script - Run this on your EC2 instance
# ------------------------------------------------

# Update system packages
sudo yum update -y

# Install Git
sudo yum install git -y

# Install Docker
sudo amazon-linux-extras install docker -y
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker ec2-user

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/download/v2.15.1/docker-compose-\$(uname -s)-\$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Create application directory
sudo mkdir -p /opt/expense-app
sudo chown ec2-user:ec2-user /opt/expense-app

# Create backup directory
sudo mkdir -p /opt/backups
sudo chown ec2-user:ec2-user /opt/backups

# Set up daily backup script
cat > /opt/backup-app.sh <<EOF
#!/bin/bash
# Simple backup script for the application data
TIMESTAMP=\$(date +%Y%m%d_%H%M%S)
BACKUP_DIR=/opt/backups/\$TIMESTAMP
mkdir -p \$BACKUP_DIR
tar czf \$BACKUP_DIR/app_data.tar.gz /opt/expense-app/data
cp /opt/expense-app/.env.production \$BACKUP_DIR/ 2>/dev/null || true
echo "Backup completed to \$BACKUP_DIR"
# Keep only the last 7 backups
find /opt/backups -type d -mtime +7 -exec rm -rf {} \; 2>/dev/null || true
EOF

chmod +x /opt/backup-app.sh

# Add backup job to crontab (runs at 2 AM daily)
(crontab -l 2>/dev/null || true; echo "0 2 * * * /opt/backup-app.sh") | crontab -

echo "============================================================="
echo "EC2 instance setup complete!"
echo "IMPORTANT: Log out and log back in to apply Docker permissions"
echo "Once logged back in, continue with the application deployment"
echo "============================================================="
EOL

chmod +x ec2-setup.sh

# Step 2: Create the application deployment script
cat > app-deploy.sh <<EOL
#!/bin/bash

# Application Deployment Script - Run this after ec2-setup.sh
# -----------------------------------------------------------

cd /opt/expense-app

# Clone repository
if [ ! -d ".git" ]; then
  echo "Cloning application repository..."
  # Replace with your actual repository URL if available
  git clone https://github.com/yourusername/expense-app.git .
  # If you're transferring files instead of cloning, those should be in place before running this script
fi

# Create required directories
mkdir -p data nginx/conf nginx/certbot/conf nginx/certbot/www

# Create production environment file if it doesn't exist
if [ ! -f ".env.production" ]; then
  echo "Creating .env.production file..."
  cat > .env.production <<EOF
FLASK_DEBUG=0
SECRET_KEY=$(openssl rand -hex 24)
GOOGLE_CLIENT_ID=your_client_id_here
GOOGLE_CLIENT_SECRET=your_client_secret_here
GOOGLE_REDIRECT_URI=https://${DOMAIN}/oauth2callback
GOOGLE_SCOPES=https://www.googleapis.com/auth/gmail.readonly https://www.googleapis.com/auth/drive
GOOGLE_SHARED_DRIVE_ID=your_shared_drive_id_here
EOF

  echo "Please update the .env.production file with your Google credentials."
  echo "Would you like to edit it now? (y/n)"
  read -r response
  if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    nano .env.production
  fi
fi

# Set up SSL certificate
echo "Setting up SSL certificate for $DOMAIN..."
chmod +x init-ssl.sh
./init-ssl.sh "$DOMAIN" "$EMAIL"

# Deploy application with Docker Compose
echo "Deploying application with Docker Compose..."
docker-compose up -d

echo "============================================================="
echo "Deployment complete!"
echo "Your application should now be accessible at: https://${DOMAIN}"
echo ""
echo "IMPORTANT: Update your Google OAuth configuration to include:"
echo "- Authorized origin: https://${DOMAIN}"
echo "- Authorized redirect URI: https://${DOMAIN}/oauth2callback"
echo "============================================================="
EOL

chmod +x app-deploy.sh

# Step 3: Create simple deployment instructions
cat > DEPLOY-EC2.md <<EOL
# Simple AWS EC2 Docker Deployment Guide

This guide explains how to deploy the Invoice Manager application to AWS EC2 using Docker.

## Prerequisites

1. An AWS account
2. A domain name (${DOMAIN}) with DNS pointing to your EC2 instance
3. SSH key pair for accessing your EC2 instance

## Deployment Steps

### Step 1: Launch an EC2 Instance

1. Log into AWS Console and go to EC2 service
2. Launch an EC2 instance with Amazon Linux 2
3. Recommended size: t2.micro (or larger if needed)
4. Configure security group to allow:
   - SSH (port 22) from your IP
   - HTTP (port 80) from anywhere
   - HTTPS (port 443) from anywhere
5. Launch the instance and connect to it using SSH

### Step 2: Set Up the EC2 Instance

1. Copy the setup script to your instance:
   \`\`\`bash
   scp -i your-key.pem ec2-setup.sh ec2-user@your-instance-ip:~
   \`\`\`

2. SSH into your instance:
   \`\`\`bash
   ssh -i your-key.pem ec2-user@your-instance-ip
   \`\`\`

3. Run the setup script:
   \`\`\`bash
   chmod +x ~/ec2-setup.sh
   ~/ec2-setup.sh
   \`\`\`

4. Log out and log back in for Docker permissions to take effect:
   \`\`\`bash
   exit
   ssh -i your-key.pem ec2-user@your-instance-ip
   \`\`\`

### Step 3: Deploy the Application

1. Copy your application files to the EC2 instance:

   **Option A: Using SCP** (if you have the files locally)
   \`\`\`bash
   # Create a tarball of your application
   tar -czf app.tar.gz *
   
   # Copy the tarball and deployment script
   scp -i your-key.pem app.tar.gz app-deploy.sh ec2-user@your-instance-ip:~
   
   # On the EC2 instance
   mkdir -p /opt/expense-app
   tar -xzf ~/app.tar.gz -C /opt/expense-app
   \`\`\`

   **Option B: Using Git** (if your code is in a repository)
   \`\`\`bash
   # Just copy the deployment script
   scp -i your-key.pem app-deploy.sh ec2-user@your-instance-ip:~
   
   # The script will clone the repository
   # You may need to modify the repository URL in app-deploy.sh
   \`\`\`

2. Run the deployment script:
   \`\`\`bash
   cd /opt/expense-app  # If using Option A
   # or
   # The script will cd to /opt/expense-app
   
   chmod +x ~/app-deploy.sh
   ~/app-deploy.sh
   \`\`\`

3. Update Google OAuth configuration:
   - Go to Google Cloud Console → APIs & Services → Credentials
   - Add https://${DOMAIN} to Authorized JavaScript Origins
   - Add https://${DOMAIN}/oauth2callback to Authorized Redirect URIs

4. Visit your application at https://${DOMAIN}

## Troubleshooting

If you encounter issues:

1. Check Docker logs:
   \`\`\`bash
   cd /opt/expense-app
   docker-compose logs -f
   \`\`\`

2. Check if the containers are running:
   \`\`\`bash
   docker-compose ps
   \`\`\`

3. Verify SSL certificate setup:
   \`\`\`bash
   docker-compose logs certbot
   \`\`\`

4. Restart the application:
   \`\`\`bash
   docker-compose restart
   \`\`\`
EOL

echo "============================================================="
echo "Deployment files created successfully!"
echo "============================================================="
echo ""
echo "Files created:"
echo "1. ec2-setup.sh - Run this on your EC2 instance first"
echo "2. app-deploy.sh - Run this after ec2-setup.sh"
echo "3. DEPLOY-EC2.md - Simple deployment instructions"
echo ""
echo "To deploy to AWS EC2:"
echo "1. Launch an Amazon Linux 2 EC2 instance"
echo "2. Follow the instructions in DEPLOY-EC2.md"
echo "============================================================="