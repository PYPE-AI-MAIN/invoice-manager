#!/bin/bash

# This script initializes Let's Encrypt SSL certificates for the expense app

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

echo "Starting Nginx to handle Let's Encrypt verification..."
docker-compose up -d nginx

# Sleep to allow Nginx to start
sleep 5

echo "Requesting certificate from Let's Encrypt..."
docker-compose run --rm certbot certonly --webroot -w /var/www/certbot \
    --email ${EMAIL} -d ${DOMAIN} --agree-tos --force-renewal --non-interactive

# Check if certificate was successfully issued
if [ $? -ne 0 ]; then
  echo "Failed to obtain SSL certificate!"
  exit 1
fi

echo "Certificate obtained successfully!"

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

echo "SSL certificate setup complete! Your application should now be accessible at https://${DOMAIN}"