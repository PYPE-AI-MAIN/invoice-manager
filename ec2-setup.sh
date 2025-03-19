#!/bin/bash

# Deployment script for setting up the expense app on EC2
# Run this script as the ec2-user on a fresh Amazon Linux 2 instance

# Display a message for each step
echo_step() {
  echo "================================================================================"
  echo "STEP: $1"
  echo "================================================================================"
}

# Exit on error
set -e

echo_step "Updating system packages"
sudo yum update -y

echo_step "Installing Docker"
sudo amazon-linux-extras install docker -y
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker ec2-user
echo "Docker installed successfully. You may need to log out and log back in for group membership to take effect."

echo_step "Installing Docker Compose"
sudo curl -L "https://github.com/docker/compose/releases/download/v2.15.1/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
docker-compose --version

echo_step "Installing Git"
sudo yum install git -y

echo_step "Creating application directories"
sudo mkdir -p /opt/expense-app
sudo chown ec2-user:ec2-user /opt/expense-app

echo_step "Setting up automatic security updates"
sudo yum install -y yum-cron
sudo sed -i 's/apply_updates = no/apply_updates = yes/g' /etc/yum/yum-cron.conf
sudo systemctl enable yum-cron
sudo systemctl start yum-cron

echo_step "Creating backup script"
cat > /opt/backup-expense-app.sh <<EOF
#!/bin/bash
TIMESTAMP=\$(date +%Y%m%d_%H%M%S)
BACKUP_DIR=/opt/backups/\$TIMESTAMP

# Create backup directory
mkdir -p \$BACKUP_DIR

# Backup data directory
tar czf \$BACKUP_DIR/expense_app_data.tar.gz /opt/expense-app/data

# Backup environment files
cp /opt/expense-app/.env.production \$BACKUP_DIR/

# Backup certificates
tar czf \$BACKUP_DIR/certificates.tar.gz /opt/expense-app/nginx/certbot/conf

echo "Backup completed to \$BACKUP_DIR"
# Keep only the last 7 backups
find /opt/backups -type d -mtime +7 -exec rm -rf {} \; 2>/dev/null || true
EOF

sudo chmod +x /opt/backup-expense-app.sh
sudo mkdir -p /opt/backups
sudo chown -R ec2-user:ec2-user /opt/backups

echo_step "Setting up backup cron job"
# Add to crontab - run backup daily at 2am
(crontab -l 2>/dev/null || true; echo "0 2 * * * /opt/backup-expense-app.sh") | crontab -

echo_step "Creating deployment directory"
DEPLOYMENT_DIR="/opt/expense-app"
cd $DEPLOYMENT_DIR

echo_step "Setting up deployment script"
cat > $DEPLOYMENT_DIR/deploy.sh <<EOF
#!/bin/bash
cd $DEPLOYMENT_DIR

# Pull latest changes
if [ -d ".git" ]; then
    git pull
else
    echo "Repository not cloned yet. Please clone it first."
    exit 1
fi

# Build and restart containers
docker-compose down
docker-compose up --build -d

echo "Deployment completed!"
EOF

chmod +x $DEPLOYMENT_DIR/deploy.sh

echo_step "Creating Nginx reload script"
cat > $DEPLOYMENT_DIR/reload-nginx.sh <<EOF
#!/bin/bash
cd $DEPLOYMENT_DIR
docker-compose exec -T nginx nginx -s reload
EOF

chmod +x $DEPLOYMENT_DIR/reload-nginx.sh

echo "================================================================================"
echo "Installation completed successfully!"
echo "================================================================================"
echo ""
echo "Next steps:"
echo "1. Clone your repository into $DEPLOYMENT_DIR"
echo "2. Set up the SSL certificate using ./init-ssl.sh"
echo "3. Start the application using docker-compose up -d"
echo ""
echo "To set up your repository, run:"
echo "cd $DEPLOYMENT_DIR"
echo "git clone <your-repo-url> ."
echo ""
echo "To set up SSL certificates, run:"
echo "./init-ssl.sh internal.pypeai.com your-email@example.com"
echo ""
echo "To deploy after changes, use the deploy script:"
echo "./deploy.sh"
echo ""
echo "================================================================================"