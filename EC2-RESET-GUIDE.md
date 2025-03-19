# EC2 Reset and Deployment Guide

This guide will help you reset your EC2 instance and deploy the updated expense app.

## Step 1: Reset EC2 Instance

If you want to completely reset your EC2 instance, you have two options:

### Option A: Terminate and Launch a New Instance (Clean Start)

1. Log in to AWS Console
2. Go to EC2 Dashboard
3. Select your existing instance
4. Click "Instance state" → "Terminate instance"
5. Launch a new EC2 instance with Amazon Linux 2
6. Configure security group to allow:
   - SSH (port 22) from your IP
   - HTTP (port 80) from anywhere
   - HTTPS (port 443) from anywhere
7. Launch with your existing key pair or create a new one

### Option B: Clean Existing Instance (Keep Same IP)

If you want to keep your current instance (and IP address):

1. SSH into your EC2 instance
2. Stop all Docker containers and remove old files:
   ```bash
   cd /opt/expense-app
   docker-compose down
   cd ~
   sudo rm -rf /opt/expense-app/*
   ```

## Step 2: Set Up the EC2 Instance

1. Copy the EC2 setup script to your instance:
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

## Step 3: Transfer Updated Files

1. Create a tarball of your application:
   ```bash
   # On your local machine
   cd /path/to/expense_app
   tar -czf app.tar.gz app.py docker-compose.yml Dockerfile EC2-DEPLOYMENT-GUIDE.md init-ssl.sh app-deploy.sh nginx/ requirements.txt static/ templates/ run-dev.sh run-prod.sh
   ```

2. Copy the tarball to your EC2 instance:
   ```bash
   scp -i your-key.pem app.tar.gz ec2-user@your-instance-ip:~
   ```

3. Extract on your EC2 instance:
   ```bash
   mkdir -p /opt/expense-app
   tar -xzf ~/app.tar.gz -C /opt/expense-app
   ```

## Step 4: Deploy the Application

1. Run the deployment script:
   ```bash
   cd /opt/expense-app
   chmod +x app-deploy.sh
   ./app-deploy.sh your-domain.com your-email@example.com
   ```

2. Verify deployment:
   ```bash
   docker-compose ps
   docker-compose logs
   ```

3. Visit your application at https://your-domain.com

## Troubleshooting

If you encounter any issues, refer to the detailed troubleshooting section in EC2-DEPLOYMENT-GUIDE.md.