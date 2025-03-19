#!/bin/bash

# Application Deployment Script - Run this after ec2-setup.sh
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

# Ensure we have an email for Let's Encrypt
if [ -z "$2" ]; then
  # Prompt for email
  echo "What email would you like to use for SSL certificates? (e.g., admin@example.com)"
  read -r EMAIL
  
  if [ -z "$EMAIL" ]; then
    echo "Error: Email is required for Let's Encrypt notifications"
    exit 1
  fi
else
  EMAIL="$2"
fi

# Output the values for confirmation
echo "Using domain: $DOMAIN"
echo "Using email: $EMAIL"
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
GOOGLE_REDIRECT_URI=https://${DOMAIN}/oauth2callback
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

# Ensure init-ssl.sh is executable
if [ ! -x "init-ssl.sh" ]; then
  echo "Making init-ssl.sh executable..."
  chmod +x init-ssl.sh
fi

# Set up SSL certificate
echo "Setting up SSL certificate for $DOMAIN..."
./init-ssl.sh "$DOMAIN" "$EMAIL"

# Check if the SSL setup was successful
if [ $? -ne 0 ]; then
  echo "SSL certificate setup failed. Would you like to:"
  echo "1. Try again"
  echo "2. Continue anyway (not recommended)"
  echo "3. Exit"
  read -r ssl_choice
  
  case $ssl_choice in
    1)
      echo "Trying SSL setup again..."
      ./init-ssl.sh "$DOMAIN" "$EMAIL"
      if [ $? -ne 0 ]; then
        echo "SSL setup failed again. Please check your domain configuration and try again later."
        exit 1
      fi
      ;;
    2)
      echo "Continuing without proper SSL setup. This may cause issues with your application."
      ;;
    *)
      echo "Exiting. Please resolve the SSL issues before continuing."
      exit 1
      ;;
  esac
fi

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
echo "Your application should now be accessible at: https://${DOMAIN}"
echo ""
echo "IMPORTANT: Update your Google OAuth configuration to include:"
echo "- Authorized origin: https://${DOMAIN}"
echo "- Authorized redirect URI: https://${DOMAIN}/oauth2callback"
echo ""
echo "To check the application logs, run:"
echo "docker-compose logs -f"
echo "============================================================="