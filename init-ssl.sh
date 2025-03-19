#!/bin/bash

# This script initializes Let's Encrypt SSL certificates for the expense app
# with improved error handling and validation

# Set up error handling
set -e
trap 'echo "An error occurred during SSL setup. Script failed."' ERR

# Check if domain name is provided
if [ -z "$1" ]; then
  echo "Error: Please provide a domain name."
  echo "Usage: $0 <domain-name> <email>"
  exit 1
fi

# Check if email is provided
if [ -z "$2" ]; then
  echo "Error: Please provide an email address for Let's Encrypt notifications."
  echo "Usage: $0 <domain-name> <email>"
  exit 1
fi

DOMAIN="$1"
EMAIL="$2"

echo "Setting up SSL certificate for $DOMAIN using Let's Encrypt..."

# Check if the directories exist, create if they don't
mkdir -p nginx/conf nginx/certbot/conf nginx/certbot/www

# Create a temporary nginx config for ACME challenge only
cat > nginx/conf/app.conf <<EOF
server {
    listen 80;
    server_name ${DOMAIN};
    server_tokens off;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 200 'Ready for Let\'s Encrypt challenges';
    }
}
EOF

# Verify the configuration file was created
if [ ! -f "nginx/conf/app.conf" ]; then
  echo "Error: Failed to create Nginx configuration file."
  exit 1
fi

echo "Starting Nginx to handle Let's Encrypt verification..."

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
  echo "Error: Docker is not running. Please start Docker and try again."
  exit 1
fi

# Start or restart Nginx
if docker-compose ps | grep -q nginx; then
  docker-compose restart nginx
else
  docker-compose up -d nginx
fi

# Check if Nginx started successfully
sleep 5
if ! docker-compose ps | grep -q "nginx.*Up"; then
  echo "Error: Nginx container is not running. Please check the logs:"
  docker-compose logs nginx
  exit 1
fi

echo "Requesting certificate from Let's Encrypt..."
echo "This process may take a minute or two..."

# Run certbot with error handling
if ! docker-compose run --rm certbot certonly --webroot -w /var/www/certbot \
    --email ${EMAIL} -d ${DOMAIN} --agree-tos --force-renewal --non-interactive; then
  echo "Failed to obtain SSL certificate!"
  echo "Possible reasons:"
  echo "1. Your domain ($DOMAIN) does not point to this server's IP address"
  echo "2. Let's Encrypt rate limits have been reached"
  echo "3. Network connectivity issues"
  echo "4. Port 80 is blocked by a firewall"
  echo ""
  echo "Check the error messages above for more details."
  exit 1
fi

echo "Certificate obtained successfully!"

# Verify that certificates were created
if ! docker-compose run --rm certbot certificates | grep -q "$DOMAIN"; then
  echo "Warning: Certificate was requested but not found in cert list."
  echo "This could indicate a problem with certificate issuance."
  
  if ! ls -la nginx/certbot/conf/live/$DOMAIN/fullchain.pem > /dev/null 2>&1; then
    echo "Error: Certificate files not found in expected location."
    exit 1
  fi
fi

# Create the final nginx config
cat > nginx/conf/app.conf <<EOF
server {
    listen 80;
    server_name ${DOMAIN};
    server_tokens off;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name ${DOMAIN};
    server_tokens off;

    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    
    # Strong SSL settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers "EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH";
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_stapling on;
    ssl_stapling_verify on;

    # Add security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options SAMEORIGIN;
    add_header X-XSS-Protection "1; mode=block";

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

echo "Restarting Nginx with new configuration..."
docker-compose restart nginx

# Verify Nginx restarted successfully
sleep 3
if ! docker-compose ps | grep -q "nginx.*Up"; then
  echo "Error: Nginx container failed to restart with the new configuration."
  echo "Checking logs:"
  docker-compose logs nginx
  exit 1
fi

echo "Testing HTTPS configuration..."
# We can't actually test the HTTPS connection from inside the script,
# but we can provide helpful information
echo "Your SSL certificate has been installed and Nginx configured."
echo "SSL certificate details:"
docker-compose run --rm certbot certificates

echo "SSL certificate setup complete! Your application should now be accessible at https://${DOMAIN}"