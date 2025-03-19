# AWS EC2 Deployment Guide for Expense App

This guide explains how to deploy the Expense App to AWS EC2 using Docker with automated SSL certificate setup.

## Prerequisites

1. An AWS account with permissions to create and manage EC2 instances
2. A domain name with DNS pointing to your EC2 instance's IP address
3. SSH key pair for accessing your EC2 instance

## Deployment Steps

### Step 1: Launch an EC2 Instance

1. Log in to the AWS Management Console
2. Navigate to EC2 service
3. Click "Launch Instance"
4. Choose Amazon Linux 2 AMI (HVM)
5. Select t2.micro instance type (or larger based on needs)
6. Configure Security Group:
   - Allow SSH (port 22) from your IP address
   - Allow HTTP (port 80) from anywhere (0.0.0.0/0)
   - Allow HTTPS (port 443) from anywhere (0.0.0.0/0)
7. Launch Instance
8. Connect to your instance via SSH

### Step 2: Set Up the EC2 Instance

1. Copy the setup script to your instance:
   ```bash
   scp -i your-key.pem ec2-setup.sh ec2-user@your-instance-ip:~
   ```

2. SSH into your instance:
   ```bash
   ssh -i your-key.pem ec2-user@your-instance-ip
   ```

3. Run the setup script:
   ```bash
   chmod +x ~/ec2-setup.sh
   ~/ec2-setup.sh
   ```

4. Log out and log back in for Docker permissions to take effect:
   ```bash
   exit
   ssh -i your-key.pem ec2-user@your-instance-ip
   ```

### Step 3: Deploy the Application

1. Copy your application files to the EC2 instance:

   **Option A: Using SCP** (if you have the files locally)
   ```bash
   # Create a tarball of your application
   tar -czf app.tar.gz *
   
   # Copy the tarball and deployment script
   scp -i your-key.pem app.tar.gz app-deploy.sh ec2-user@your-instance-ip:~
   
   # On the EC2 instance
   mkdir -p /opt/expense-app
   tar -xzf ~/app.tar.gz -C /opt/expense-app
   ```

   **Option B: Using Git** (if your code is in a repository)
   ```bash
   # Just copy the deployment script and let it clone the repository
   scp -i your-key.pem app-deploy.sh ec2-user@your-instance-ip:~
   ```

2. Run the deployment script with your domain name and email:
   ```bash
   cd /opt/expense-app
   chmod +x ~/app-deploy.sh
   ~/app-deploy.sh your-domain.com your-email@example.com
   ```

3. Update Google OAuth configuration:
   - Go to Google Cloud Console → APIs & Services → Credentials
   - Add `https://your-domain.com` to Authorized JavaScript Origins
   - Add `https://your-domain.com/oauth2callback` to Authorized Redirect URIs

4. Visit your application at https://your-domain.com

## Important Configuration Files

- **.env.production**: Contains environment variables including Google API credentials
- **nginx/conf/app.conf**: Nginx configuration for HTTP and HTTPS
- **docker-compose.yml**: Defines the application services and their configuration

## Troubleshooting

### Common Issues and Solutions

#### Application Downloads as a File Instead of Displaying

This typically indicates that your Nginx configuration is stuck in the temporary state used for Let's Encrypt verification. To fix:

1. Check the current Nginx configuration:
   ```bash
   cat nginx/conf/app.conf
   ```

2. If you see `return 200 'Ready for Let\'s Encrypt challenges';`, your Nginx is still in the temporary configuration state. Run:
   ```bash
   ./init-ssl.sh your-domain.com your-email@example.com
   ```

3. Restart the containers:
   ```bash
   docker-compose restart
   ```

#### SSL Certificate Issues

If you see SSL certificate errors:

1. Verify that your domain points to your EC2 instance:
   ```bash
   nslookup your-domain.com
   ```

2. Check Let's Encrypt logs:
   ```bash
   docker-compose logs certbot
   ```

3. Manually request a certificate:
   ```bash
   docker-compose run --rm certbot certonly --webroot -w /var/www/certbot \
     --email your-email@example.com -d your-domain.com --agree-tos --force-renewal
   ```

#### Application Container Not Starting

1. Check the status of all containers:
   ```bash
   docker-compose ps
   ```

2. View application logs:
   ```bash
   docker-compose logs expense-app
   ```

3. Check if .env.production exists and has valid values:
   ```bash
   cat .env.production
   ```

4. Rebuild and restart the application:
   ```bash
   docker-compose down
   docker-compose up -d
   ```

#### Google OAuth Issues

1. Verify your OAuth settings match your domain:
   ```bash
   grep GOOGLE_REDIRECT_URI .env.production
   ```

2. Check the application logs for OAuth errors:
   ```bash
   docker-compose logs expense-app | grep -i oauth
   ```

## Maintenance and Updates

### Updating the Application

To update the application:

1. Pull the latest code:
   ```bash
   cd /opt/expense-app
   git pull
   ```

2. Rebuild the Docker containers:
   ```bash
   docker-compose down
   docker-compose up -d --build
   ```

### Renewing SSL Certificates

SSL certificates from Let's Encrypt are valid for 90 days and are auto-renewed by the certbot container. To manually trigger renewal:

```bash
docker-compose run --rm certbot renew
docker-compose restart nginx
```

### Checking Logs

```bash
# All logs
docker-compose logs

# App-specific logs
docker-compose logs expense-app

# Web server logs
docker-compose logs nginx
```

### Creating a Backup

The system automatically creates daily backups to /opt/backups. To manually create a backup:

```bash
/opt/backup-app.sh
```