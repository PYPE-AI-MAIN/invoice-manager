#!/bin/bash

# Check if virtual environment exists, create if it doesn't
if [ ! -d "venv" ]; then
    echo "Creating virtual environment..."
    python3 -m venv venv
fi

# Activate the virtual environment
source venv/bin/activate

# Install/update dependencies
echo "Installing dependencies..."
pip install -r requirements.txt

# Set production environment variables
export FLASK_DEBUG=0
export FLASK_APP=app.py
export ENVIRONMENT=production
export FLASK_ENV=production
# Make sure insecure transport is not allowed in production
unset OAUTHLIB_INSECURE_TRANSPORT

# Check if .env file exists, use .env.example as template if it doesn't
if [ ! -f ".env" ]; then
    echo "Creating .env file from .env.example..."
    if [ -f ".env.example" ]; then
        cp .env.example .env
        echo "Please update the .env file with your configuration values."
        echo "Then run this script again."
        exit 1
    else
        echo "Error: .env.example file not found."
        exit 1
    fi
fi

# Check if gunicorn is installed, install if it isn't
if ! pip show gunicorn > /dev/null; then
    echo "Installing gunicorn for production server..."
    pip install gunicorn
fi

# Start the Flask application in production mode with gunicorn
echo "Starting Flask application in PRODUCTION mode..."
echo "-------------------------------------------------"
echo "Your app should be accessible at: http://localhost:5001"
echo "Press CTRL+C to stop the server"
echo "-------------------------------------------------"

# Try to start with gunicorn
gunicorn --bind 0.0.0.0:5001 --access-logfile - --error-logfile - app:app 2>&1 || {
    echo "Failed to start with gunicorn. Falling back to direct python execution..."
    python app.py
} 