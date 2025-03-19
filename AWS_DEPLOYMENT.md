# AWS Deployment Guide for Expense App

This guide provides detailed step-by-step instructions for deploying the Expense App to AWS EC2 with HTTPS support.

## Prerequisites

Before starting the deployment, ensure you have:

1. An AWS account with permissions to:
   - Create EC2 instances
   - Create Security Groups
   - Create and assign Elastic IPs

2. The domain `internal.pypeai.com` registered and ready for DNS configuration

3. Access to update DNS records for your domain

## Step 1: Launch an EC2 Instance

1. Log in to the AWS Management Console
2. Navigate to EC2 service
3. Click "Launch Instance"
4. Choose Amazon Linux 2 AMI (HVM)
5. Select t2.micro instance type (or larger based on needs)
6. Configure Instance details
   - Network: Default VPC
   - Subnet: Choose an availability zone in ap-south-1 (Mumbai)
   - Auto-assign Public IP: Enable
7. Add Storage: Default 8GB is sufficient, but you can increase if needed
8. Add Tags: Add a "Name" tag with value "expense-app"
9. Configure Security Group:
   - Allow SSH (port 22) from your IP address
   - Allow HTTP (port 80) from anywhere (0.0.0.0/0)
   - Allow HTTPS (port 443) from anywhere (0.0.0.0/0)
10. Review and Launch
11. Select or create a key pair for SSH access
12. Launch Instance

## Step 2: Allocate an Elastic IP

1. In the EC2 dashboard, navigate to "Elastic IPs"
2. Click "Allocate Elastic IP address"
3. Select "Amazon's pool of IPv4 addresses"
4. Click "Allocate"
5. Select the newly allocated IP address
6. Click "Actions" > "Associate Elastic IP address"
7. Select your instance and click "Associate"

## Step 3: Configure DNS

### Option A: Using AWS Route 53

1. Open Route 53 in AWS Console
2. Create a hosted zone for your domain if it doesn't exist
3. Add an A record:
   - Name: internal.pypeai.com
   - Type: A - IPv4 address
   - Value: [Your Elastic IP address]
   - TTL: 300
4. Click "Create"

### Option B: Using External DNS Provider

1. Log in to your domain registrar's DNS management console
2. Add an A record:
   - Host: internal (or subdomain)
   - Points to: [Your Elastic IP address]
   - TTL: 300 or 3600

## Step 4: Configure the EC2 Instance

1. Connect to your instance via SSH:
   ```
   ssh -i your-key.pem ec2-user@your-elastic-ip
   ```

2. Update the system:
   ```
   sudo yum update -y
   ```

3. Install git:
   ```
   sudo yum install git -y
   ```

4. Clone the repository:
   ```
   sudo mkdir -p /opt/expense-app
   sudo chown ec2-user:ec2-user /opt/expense-app
   cd /opt/expense-app
   git clone [repository-url] .
   ```

5. Run the setup script:
   ```
   chmod +x ec2-setup.sh
   ./ec2-setup.sh
   ```

## Step 5: Update Google OAuth Configuration

Before deploying, you need to update your Google OAuth configuration:

1. Go to the [Google Cloud Console](https://console.cloud.google.com/)
2. Navigate to your project
3. Go to "APIs & Services" > "Credentials"
4. Edit your OAuth 2.0 Client ID
5. Add these to "Authorized JavaScript origins":
   ```
   https://internal.pypeai.com
   ```
6. Add these to "Authorized redirect URIs":
   ```
   https://internal.pypeai.com/oauth2callback
   ```
7. Click "Save"

## Step 6: Configure the Application

1. On your EC2 instance, update the .env.production file:
   ```
   nano /opt/expense-app/.env.production
   ```
   
   Ensure these settings are correct:
   ```
   GOOGLE_REDIRECT_URI=https://internal.pypeai.com/oauth2callback
   ```

2. Initialize the SSL certificate:
   ```
   cd /opt/expense-app
   ./init-ssl.sh internal.pypeai.com your-email@example.com
   ```

3. Deploy the application:
   ```
   docker-compose up -d
   ```

## Step 7: Set Up CI/CD Pipeline

1. Add these secrets to your GitHub repository:
   - `EC2_HOST`: Your Elastic IP address
   - `EC2_SSH_KEY`: Private SSH key for accessing your EC2 instance

2. Push code to your main branch to trigger automatic deployments

## Step 8: Verify Deployment

1. Visit https://internal.pypeai.com in your browser
2. You should see the login page
3. Log in with your Google account
4. Verify that all functionality works correctly

## Troubleshooting

### SSL Certificate Issues

If the SSL certificate setup fails:

1. Check DNS propagation:
   ```
   dig internal.pypeai.com
   ```

2. Make sure ports 80 and 443 are open in your security group

3. Check Nginx logs:
   ```
   docker-compose logs nginx
   ```

4. Manually request a certificate:
   ```
   docker-compose run --rm certbot certonly --webroot -w /var/www/certbot \
     --email your-email@example.com -d internal.pypeai.com --agree-tos -v
   ```

### Application Connectivity Issues

1. Check application logs:
   ```
   docker-compose logs expense-app
   ```

2. Check if the application is running:
   ```
   docker-compose ps
   ```

3. Restart the application:
   ```
   docker-compose restart
   ```

## Maintenance and Updates

### Regular Maintenance Tasks

1. Update the system:
   ```
   sudo yum update -y
   ```

2. Update Docker images:
   ```
   docker-compose pull
   docker-compose up -d
   ```

3. Check backups:
   ```
   ls -la /opt/backups
   ```

### Updating the Application

The CI/CD pipeline will automatically deploy changes when you push to the main branch.

For manual deployments:

```
cd /opt/expense-app
git pull
docker-compose up -d --build
```

## Security Best Practices

1. Regularly rotate SSH keys
2. Update the EC2 instance regularly
3. Monitor logs for suspicious activity
4. Keep the Docker engine updated
5. Always access the admin interface over HTTPS

## Backup and Recovery

Regular backups of data are scheduled via cron job. To restore from a backup:

1. Find your backup:
   ```
   ls -la /opt/backups
   ```

2. Restore data:
   ```
   tar -xzf /opt/backups/[timestamp]/expense_app_data.tar.gz -C /tmp
   cp -r /tmp/opt/expense-app/data/* /opt/expense-app/data/
   ```

3. Restart the application:
   ```
   docker-compose restart
   ```