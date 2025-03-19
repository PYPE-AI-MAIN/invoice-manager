# Enabling SSL After Initial Deployment

This guide explains how to enable SSL with Let's Encrypt after you've already deployed your application using HTTP only.

## Prerequisites

1. Properly configured DNS (domain pointing to your EC2 instance)
2. Application already deployed and running with HTTP

## Check DNS Configuration

First, verify that your domain is properly pointing to your EC2 instance:

```bash
chmod +x check-dns.sh
./check-dns.sh your-domain.com
```

This script will tell you if your domain is correctly pointing to your EC2 instance.

## Enable SSL

Once your DNS is properly configured and propagated:

1. Run the SSL initialization script:
   ```bash
   chmod +x init-ssl.sh
   ./init-ssl.sh your-domain.com your-email@example.com
   ```

2. This script will:
   - Request an SSL certificate from Let's Encrypt
   - Configure Nginx to use HTTPS
   - Set up automatic redirects from HTTP to HTTPS

3. Restart Nginx to apply the changes:
   ```bash
   docker-compose restart nginx
   ```

4. Update your .env.production file to use HTTPS:
   ```bash
   sed -i 's|http://your-domain.com|https://your-domain.com|g' .env.production
   ```

5. Restart the application:
   ```bash
   docker-compose restart expense-app
   ```

6. Update your Google OAuth settings to use HTTPS:
   - Go to Google Cloud Console → APIs & Services → Credentials
   - Update the redirect URI from http://your-domain.com/oauth2callback to https://your-domain.com/oauth2callback

## Troubleshooting

If you encounter issues:

1. Check the Let's Encrypt logs:
   ```bash
   docker-compose logs certbot
   ```

2. Verify your certificate status:
   ```bash
   docker-compose run --rm certbot certificates
   ```

3. Check Nginx configuration:
   ```bash
   docker-compose exec nginx nginx -t
   ```

4. If Let's Encrypt fails due to rate limits:
   - Wait 1 week (rate limits are per domain per week)
   - Use the staging environment for testing:
     ```bash
     docker-compose run --rm certbot certonly --webroot -w /var/www/certbot \
       --email your-email@example.com -d your-domain.com \
       --agree-tos --staging --force-renewal
     ```