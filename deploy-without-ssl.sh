#!/bin/bash

# Deploy without SSL - For cases where Let's Encrypt validation fails
# -----------------------------------------------------------

# Ensure we have a domain name to use
if [ -z "$1" ]; then
  # Prompt for domain name
  echo "What is your domain name? (e.g., example.com)"
  read -r DOMAIN
  
  if [ -z "$DOMAIN" ]; then
    echo "Error: Domain name is required"
    exit 1
  fi
else
  DOMAIN="$1"
fi

# Output the values for confirmation
echo "Using domain: $DOMAIN"
echo "Is this correct? (y/n)"
read -r confirm
if [[ ! "$confirm" =~ ^([yY][eE][sS]|[yY])$ ]]; then
  echo "Deployment cancelled. Please run the script again with correct parameters."
  exit 1
fi

cd /opt/expense-app

# Create required directories with proper permissions
mkdir -p data nginx/conf nginx/certbot/conf nginx/certbot/www
chmod 755 data nginx nginx/conf nginx/certbot nginx/certbot/conf nginx/certbot/www

# Clone repository if it doesn't exist
if [ ! -d ".git" ] && [ ! -f "app.py" ]; then
  echo "Application code not found. Would you like to:"
  echo "1. Clone from Git repository"
  echo "2. Skip (if you've copied the files manually)"
  read -r choice
  
  if [ "$choice" == "1" ]; then
    echo "Please enter the Git repository URL:"
    read -r repo_url
    git clone "$repo_url" .
  fi
fi

# Create production environment file if it doesn't exist
if [ ! -f ".env.production" ]; then
  echo "Creating .env.production file..."
  cat > .env.production <<EOF
FLASK_DEBUG=0
SECRET_KEY=$(openssl rand -hex 24)
GOOGLE_CLIENT_ID=your_client_id_here
GOOGLE_CLIENT_SECRET=your_client_secret_here
GOOGLE_REDIRECT_URI=http://${DOMAIN}/oauth2callback
GOOGLE_SCOPES=https://www.googleapis.com/auth/gmail.readonly https://www.googleapis.com/auth/drive
GOOGLE_SHARED_DRIVE_ID=your_shared_drive_id_here
EOF

  echo "Please update the .env.production file with your Google credentials."
  echo "Would you like to edit it now? (y/n)"
  read -r response
  if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    ${EDITOR:-nano} .env.production
  fi
fi

# Create a basic Nginx config that doesn't use HTTPS
echo "Creating Nginx configuration for HTTP only (no SSL)..."
cat > nginx/conf/app.conf <<EOF
server {
    listen 80;
    server_name ${DOMAIN};
    server_tokens off;

    client_max_body_size 20M;

    location / {
        proxy_pass http://expense-app:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# Deploy application with Docker Compose
echo "Starting Docker containers..."
docker-compose down
docker-compose up -d

# Check if containers started successfully
sleep 5
if ! docker-compose ps | grep -q "Up"; then
  echo "Warning: Not all containers appear to be running. Checking logs..."
  docker-compose logs
  echo "Would you like to try to restart the containers? (y/n)"
  read -r restart
  if [[ "$restart" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    docker-compose restart
  fi
fi

echo "============================================================="
echo "Deployment complete!"
echo "Your application should now be accessible at: http://${DOMAIN}"
echo ""
echo "IMPORTANT: Update your Google OAuth configuration to include:"
echo "- Authorized origin: http://${DOMAIN}"
echo "- Authorized redirect URI: http://${DOMAIN}/oauth2callback"
echo ""
echo "NOTE: This deployment is using HTTP only (no SSL). To enable SSL later:"
echo "1. Make sure your domain DNS is properly configured to point to this server"
echo "2. Run: ./init-ssl.sh ${DOMAIN} your-email@example.com"
echo "3. Restart Nginx: docker-compose restart nginx"
echo ""
echo "To check the application logs, run:"
echo "docker-compose logs -f"
echo "============================================================="