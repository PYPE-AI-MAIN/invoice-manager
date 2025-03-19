# EC2 Deployment Guide

This is a basic guide for deploying the Invoice Manager application to AWS EC2 using Docker.

## Simplified Deployment Process

1. **Run the deployment script generator**

   ```bash
   ./ec2-deploy.sh your-domain.com your-email@example.com
   ```

   This will create:
   - Detailed deployment instructions
   - EC2 instance setup scripts
   - Application deployment scripts

2. **Follow the generated instructions**

   After running the script, detailed deployment instructions will be generated in a file called `DEPLOY-EC2.md`.

   The basic process will be:
   1. Launch an EC2 instance with Amazon Linux 2
   2. Run the initial setup script on your EC2 instance
   3. Deploy the application using the deployment script
   4. Configure Google OAuth for your domain

Run `./ec2-deploy.sh` now to generate the complete deployment instructions.