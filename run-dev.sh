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

# Make sure Flask is installed
if ! pip show flask > /dev/null; then
    echo "Flask not found, installing it..."
    pip install flask
fi

# Set development environment variables
export FLASK_DEBUG=1
export FLASK_APP=app.py
export ENVIRONMENT=development
export FLASK_ENV=development
# This allows OAuth to work without HTTPS in development
export OAUTHLIB_INSECURE_TRANSPORT=1

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

# Start the Flask application in development mode
echo "Starting Flask application in DEVELOPMENT mode..."
echo "-------------------------------------------------"
echo "Your app should be accessible at: http://localhost:5001"
echo "Press CTRL+C to stop the server"
echo "-------------------------------------------------"

# Try first with flask run command
flask run --debug --host=0.0.0.0 --port=5001 2>&1 || {
    echo "Failed to start with 'flask run'. Trying with python -m flask..."
    python -m flask run --debug --host=0.0.0.0 --port=5001 2>&1 || {
        echo "Flask run failed. Falling back to direct python execution..."
        python app.py
    }
} 