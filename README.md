# Invoice Manager

A simple application that connects to Gmail, fetches invoices, and organizes them in a shared Google Drive folder.

## Features

- Connect to Gmail using Google OAuth
- Automatically identify and download invoice attachments from emails
- Upload invoices to a shared Google Drive with an organized folder structure
- Structured folders: year/month/username
- Production-ready with Docker, HTTPS, and AWS deployment support

## Requirements

- Python 3.9+
- Google account with access to Gmail and Google Drive
- Google Cloud Platform project with Gmail and Drive APIs enabled
- Shared Google Drive (the ID is set in the .env file)

## Local Development Setup

1. **Clone the repository**

   ```bash
   git clone <repository-url>
   cd invoice_app
   ```

2. **Create and activate virtual environment**

   ```bash
   python -m venv venv
   source venv/bin/activate  # On Windows: venv\Scripts\activate
   ```

3. **Install dependencies**

   ```bash
   pip install -r requirements.txt
   ```

4. **Configure Google OAuth credentials**

   Create a `.env` file in the project root with the following:

   ```
   FLASK_DEBUG=1
   SECRET_KEY=your_secret_key_here
   GOOGLE_CLIENT_ID=your_client_id_here
   GOOGLE_CLIENT_SECRET=your_client_secret_here
   GOOGLE_REDIRECT_URI=http://localhost:5001/oauth2callback
   GOOGLE_SCOPES=https://www.googleapis.com/auth/gmail.readonly https://www.googleapis.com/auth/drive
   GOOGLE_SHARED_DRIVE_ID=your_shared_drive_id_here
   ```

   To obtain these credentials:
   
   1. Go to the [Google Cloud Console](https://console.cloud.google.com/)
   2. Create a new project
   3. Enable the Gmail API and Google Drive API
   4. Create OAuth 2.0 credentials
   5. Set the authorized redirect URI to `http://localhost:5001/oauth2callback`
   6. Get your shared drive ID from your Google Drive URL

5. **Run the application for development**

   ```bash
   ./run-dev.sh
   ```

   The application will be available at http://localhost:5001

## Production Deployment to AWS

### Prerequisites

1. An AWS account with permissions to create EC2 instances
2. A domain name (domain.com) with DNS configured to point to your EC2 instance
3. SSH keys for accessing the EC2 instance

### Deployment Steps

1. **Launch an EC2 Instance in AWS**

   - Use Amazon Linux 2 AMI
   - Recommended instance type: t2.micro (or larger depending on load)
   - Configure security group to allow:
     - SSH (port 22) from your IP
     - HTTP (port 80) from anywhere
     - HTTPS (port 443) from anywhere
   - Attach an Elastic IP for a static address

2. **Set Up the EC2 Instance**

   Connect to your instance and run the provided setup script:

   ```bash
   scp -i your-key.pem ec2-setup.sh ec2-user@your-instance-ip:/tmp/
   ssh -i your-key.pem ec2-user@your-instance-ip
   chmod +x /tmp/ec2-setup.sh
   /tmp/ec2-setup.sh
   ```

3. **Clone the Repository on EC2**

   ```bash
   cd /opt/expense-app
   git clone <repository-url> .
   ```

4. **Configure Production Environment**

   Update the `.env.production` file on your EC2 instance:
   
   ```bash
   # Update Google OAuth credentials for production domain
   nano .env.production
   ```

   Ensure these values are set:
   - `GOOGLE_REDIRECT_URI=https://domain.com/oauth2callback`
   - Update Google Client ID and Secret if needed

5. **Set Up SSL Certificate**

   ```bash
   ./init-ssl.sh domain.com your-email@example.com
   ```

6. **Deploy the Application**

   ```bash
   docker-compose up -d
   ```

7. **Verify the Deployment**

   Visit https://domain.com in your browser. The application should load with a valid SSL certificate.

### CI/CD Pipeline Setup

1. **Create GitHub Repository Secrets**

   Add these secrets to your GitHub repository:
   - `EC2_HOST`: Public IP of your EC2 instance
   - `EC2_SSH_KEY`: Private SSH key for EC2 access

2. **Push to Main Branch**

   The included GitHub Actions workflow will automatically deploy new changes to your EC2 instance when you push to the main branch.

## Usage

1. Visit your application URL (local or production) in your web browser
2. Log in with your Google account
3. Navigate to "Fetch Invoices"
4. Select the year and month for which you want to retrieve invoices
5. Click "Fetch & Organize Invoices"
6. View the results and access your organized files in the shared Google Drive

## Folder Structure

Invoices are organized in the shared Google Drive with the following structure:

```
Shared Drive Root
└── Year (e.g., 2025)
    └── Month (e.g., March)
        └── Username
            ├── invoice1.pdf
            ├── invoice2.pdf
            └── ...
```

## Docker Commands

- Build and start containers: `docker-compose up -d`
- View logs: `docker-compose logs -f`
- Stop containers: `docker-compose down`
- Rebuild after changes: `docker-compose up -d --build`

## Maintenance

- SSL certificates will auto-renew via certbot
- Application updates are deployed via CI/CD
- Backups run daily at 2am and are stored in `/opt/backups`

## Security Notes

- The application uses OAuth 2.0 to securely access Gmail and Google Drive 
- No passwords are stored by the application
- Access tokens are stored locally in the `data` directory
- All production traffic is encrypted with HTTPS

## License

This project is licensed under the MIT License - see below for details:

```
MIT License

Copyright (c) 2025 Invoice Manager

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Contribution

Contributions are welcome! If you'd like to contribute to this project:

1. Fork the repository
2. Create a new branch for your feature
3. Add your changes and commit them
4. Push to your fork and submit a pull request

Please ensure your code follows the existing style and includes appropriate documentation.