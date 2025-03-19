#!/bin/bash

# DNS Check Script
# This script helps diagnose DNS issues for Let's Encrypt validation

# Check if domain parameter is provided
if [ -z "$1" ]; then
  echo "Error: Please provide a domain name to check"
  echo "Usage: $0 domain.com"
  exit 1
fi

DOMAIN=$1
EC2_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

echo "============================================================="
echo "DNS Configuration Check for $DOMAIN"
echo "============================================================="
echo "EC2 Public IP: $EC2_IP"
echo ""

echo "Checking if the domain resolves to this server's IP address..."
DOMAIN_IP=$(dig +short $DOMAIN A)

echo "Domain $DOMAIN resolves to: $DOMAIN_IP"
echo ""

if [ "$DOMAIN_IP" == "$EC2_IP" ]; then
  echo "SUCCESS: The domain points to this server!"
else
  echo "WARNING: The domain does not point to this server's IP address."
  echo "You need to update your DNS settings to point $DOMAIN to $EC2_IP"
  echo ""
  echo "How to fix this:"
  echo "1. Go to your domain registrar or DNS provider"
  echo "2. Find the DNS management section"
  echo "3. Create or update the A record for $DOMAIN to point to $EC2_IP"
  echo "4. Wait for DNS changes to propagate (can take up to 48 hours, but often much faster)"
fi

echo ""
echo "Checking if port 80 is open (required for Let's Encrypt)..."
nc -z -w5 localhost 80
if [ $? -eq 0 ]; then
  echo "SUCCESS: Port 80 is open and accessible"
else
  echo "WARNING: Port 80 appears to be closed or blocked"
  echo "Make sure your security group allows inbound traffic on port 80"
fi

echo ""
echo "Checking Let's Encrypt connection..."
curl -s https://acme-v02.api.letsencrypt.org/directory > /dev/null
if [ $? -eq 0 ]; then
  echo "SUCCESS: Can connect to Let's Encrypt API"
else
  echo "WARNING: Cannot connect to Let's Encrypt API"
  echo "This could indicate network connectivity issues"
fi

echo ""
echo "============================================================="
echo "Recommendation:"
echo ""
if [ "$DOMAIN_IP" != "$EC2_IP" ]; then
  echo "DNS is not configured correctly. Use deploy-without-ssl.sh for now:"
  echo "  ./deploy-without-ssl.sh $DOMAIN"
  echo ""
  echo "After updating your DNS settings and waiting for propagation,"
  echo "you can add SSL with:"
  echo "  ./init-ssl.sh $DOMAIN your-email@example.com"
else
  echo "Your domain points to the correct IP. If Let's Encrypt still fails,"
  echo "check for rate limiting or other issues in the logs:"
  echo "  docker-compose logs certbot"
fi
echo "============================================================="